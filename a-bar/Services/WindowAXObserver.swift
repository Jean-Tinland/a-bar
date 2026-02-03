import Cocoa
import ApplicationServices
import Combine

/// Observes Accessibility window notifications for a given PID (or self) and
/// exposes focused window title updates via `@Published`.
final class WindowAXObserver: ObservableObject {
    @Published var focusedWindowTitle: String?

    private var observer: AXObserver?
    private let appElement: AXUIElement
    private let pid: pid_t
    private var currentWindow: AXUIElement?

    init(pid: pid_t? = nil, promptForAccessibility: Bool = true) {
        self.pid = pid ?? ProcessInfo.processInfo.processIdentifier
        self.appElement = AXUIElementCreateApplication(self.pid)

        if promptForAccessibility {
            let options: NSDictionary = [
                kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true
            ]
            AXIsProcessTrustedWithOptions(options)
        }

        setupObserver()
        refreshFocusedWindowTitle()
    }

    deinit {
        teardownObserver()
    }

    private func setupObserver() {
        var obsRef: AXObserver?
        let callback: AXObserverCallback = { observer, element, notification, refcon in
            guard let refcon = refcon else { return }
            let instance = Unmanaged<WindowAXObserver>.fromOpaque(refcon).takeUnretainedValue()
            instance.handle(notification: notification as String, element: element)
        }

        let result = AXObserverCreate(self.pid, callback, &obsRef)
        guard result == .success, let obs = obsRef else { return }

        self.observer = obs

        let notifications: [CFString] = [
            kAXFocusedWindowChangedNotification as CFString,
            kAXWindowCreatedNotification as CFString,
            kAXUIElementDestroyedNotification as CFString
        ]

        for notif in notifications {
            AXObserverAddNotification(obs, appElement, notif, Unmanaged.passUnretained(self).toOpaque())
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), CFRunLoopMode.commonModes)
    }

    private func teardownObserver() {
        guard let obs = observer else { return }

        let notifications: [CFString] = [
            kAXFocusedWindowChangedNotification as CFString,
            kAXWindowCreatedNotification as CFString,
            kAXUIElementDestroyedNotification as CFString
        ]
        for notif in notifications {
            AXObserverRemoveNotification(obs, appElement, notif)
        }

        // Remove title observer from current window if any
        if let window = currentWindow {
            AXObserverRemoveNotification(obs, window, kAXTitleChangedNotification as CFString)
        }

        let source = AXObserverGetRunLoopSource(obs)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, CFRunLoopMode.commonModes)

        observer = nil
    }

    private func handle(notification: String, element: AXUIElement) {
        switch notification {
        case let n where n == kAXFocusedWindowChangedNotification as String:
            refreshFocusedWindowTitle()
        case let n where n == kAXWindowCreatedNotification as String:
            refreshFocusedWindowTitle()
        case let n where n == kAXTitleChangedNotification as String:
            // Title changed on the observed window
            refreshFocusedWindowTitle()
        case let n where n == kAXUIElementDestroyedNotification as String:
            DispatchQueue.main.async { self.focusedWindowTitle = nil }
        default:
            break
        }
    }

    private func refreshFocusedWindowTitle() {
        var window: AnyObject?
        let err = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &window)
        guard err == .success else {
            DispatchQueue.main.async { self.focusedWindowTitle = nil }
            // Remove title observer from old window
            if let oldWindow = currentWindow, let obs = observer {
                AXObserverRemoveNotification(obs, oldWindow, kAXTitleChangedNotification as CFString)
            }
            currentWindow = nil
            return
        }
        let windowElement = window as! AXUIElement

        // If window changed, update title observer
        if let oldWindow = currentWindow, let obs = observer {
            AXObserverRemoveNotification(obs, oldWindow, kAXTitleChangedNotification as CFString)
        }
        currentWindow = windowElement
        if let obs = observer {
            AXObserverAddNotification(obs, windowElement, kAXTitleChangedNotification as CFString, Unmanaged.passUnretained(self).toOpaque())
        }

        var titleObj: AnyObject?
        let titleErr = AXUIElementCopyAttributeValue(windowElement, kAXTitleAttribute as CFString, &titleObj)
        let title = (titleErr == .success) ? (titleObj as? String) : nil

        DispatchQueue.main.async { self.focusedWindowTitle = title ?? "Untitled Window" }
    }
}
