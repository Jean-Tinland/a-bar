import Foundation
import Combine
import AppKit
import ApplicationServices

/// Helper to request and monitor Accessibility (AX) permissions.
final class AccessibilityHelper: ObservableObject {
    static let shared = AccessibilityHelper()

    @Published private(set) var isTrusted: Bool

    private var pollTimer: Timer?

    private init() {
        self.isTrusted = AXIsProcessTrusted()
    }

    /// Request accessibility permission. If `prompt` is true the system
    /// prompt will be shown. If permission isn't granted we open the
    /// Privacy & Security → Accessibility pane and start polling for change.
    func requestAuthorization(prompt: Bool = true) {
        let options: CFDictionary = [
            kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: prompt
        ] as CFDictionary

        let granted = AXIsProcessTrustedWithOptions(options)
        DispatchQueue.main.async { self.isTrusted = granted }

        if !granted {
            openAccessibilityPreferences()
            startMonitoring()
        } else {
            stopMonitoring()
        }
    }

    func openAccessibilityPreferences() {
        // Deep link to the Accessibility privacy pane
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func startMonitoring() {
        stopMonitoring()
        DispatchQueue.main.async {
            self.pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                let now = AXIsProcessTrusted()
                DispatchQueue.main.async { self.isTrusted = now }
                if now { self.stopMonitoring() }
            }
        }
    }

    private func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}
