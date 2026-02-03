import AppKit
import ApplicationServices
import Combine
import Foundation

/// Helper to request and monitor Accessibility (AX) permissions.
final class AccessibilityHelper: ObservableObject {
    static let shared = AccessibilityHelper()

    @Published private(set) var isTrusted: Bool

    private var pollTimer: Timer?
    private var appActivationObserver: Any?

    private init() {
        self.isTrusted = AXIsProcessTrusted()

        // Start continuous monitoring immediately
        startMonitoring()

        // Monitor app activation to recheck permissions
        setupAppActivationObserver()
    }

    deinit {
        if let observer = appActivationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        stopMonitoring()
    }

    /// Setup observer to recheck accessibility when app becomes active.
    /// This handles cases where user manually adds the app in System Settings.
    private func setupAppActivationObserver() {
        appActivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.recheckPermissions()
        }
    }

    /// Force a recheck of accessibility permissions
    func recheckPermissions() {
        let now = AXIsProcessTrusted()
        if now != isTrusted {
            DispatchQueue.main.async {
                self.isTrusted = now
            }
        }
    }

    /// Request accessibility permission. If `prompt` is true the system
    /// prompt will be shown. If permission isn't granted we open the
    /// Privacy & Security → Accessibility pane.
    func requestAuthorization(prompt: Bool = true) {
        let options: CFDictionary =
            [
                kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: prompt
            ] as CFDictionary

        let granted = AXIsProcessTrustedWithOptions(options)
        DispatchQueue.main.async { self.isTrusted = granted }

        if !granted {
            openAccessibilityPreferences()
        }
    }

    func openAccessibilityPreferences() {
        // Deep link to the Accessibility privacy pane
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        {
            NSWorkspace.shared.open(url)
        }
    }

    /// Start continuous monitoring of accessibility permissions.
    /// This runs continuously to detect when user manually grants permission.
    private func startMonitoring() {
        stopMonitoring()
        DispatchQueue.main.async {
            self.pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) {
                [weak self] _ in
                guard let self = self else { return }
                let now = AXIsProcessTrusted()
                if now != self.isTrusted {
                    DispatchQueue.main.async {
                        self.isTrusted = now
                    }
                }
            }
        }
    }

    private func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}
