import ApplicationServices
import Foundation
import Darwin

/// Application-level AX subscriptions cover existing and newly created windows without
/// spawning a process for each move/title notification. All AX I/O stays off the UI thread.
final class YabaiWindowEvents {
    enum Event {
        case moved
        case titleChanged(id: Int, pid: pid_t, element: AXUIElement, title: String?)
        case resynchronized
        case permissionLost
    }
    typealias Subscribe = (pid_t, @escaping (Event) -> Void) -> (() -> Void)?

    private let trusted: () -> Bool
    private let subscribe: Subscribe
    private let titleReader: (AXUIElement) -> String?
    let supportsTitles: Bool
    private var worker: Worker?
    private var generation = 0
    private var handler: ((Event) -> Void)?

    var isTrusted: Bool { trusted() }

    init(trusted: @escaping () -> Bool = AXIsProcessTrusted,
         subscribe: @escaping Subscribe = YabaiWindowEvents.subscribeNative,
         titleReader: @escaping (AXUIElement) -> String? = YabaiWindowEvents.readNativeTitle,
         supportsTitles: Bool = YabaiWindowEvents.nativeWindowIDReader != nil) {
        self.trusted = trusted
        self.subscribe = subscribe
        self.titleReader = titleReader
        self.supportsTitles = supportsTitles
    }

    /// Main-thread lifecycle, matching YabaiService.
    func start(_ handler: @escaping (Event) -> Void) {
        stop()
        self.handler = handler
    }

    func update(_ windows: [YabaiWindow]) {
        guard handler != nil else { return }
        guard trusted() else {
            if worker != nil { stopWorker(); handler?(.permissionLost) }
            return
        }
        var membership: [pid_t: Set<Int>] = [:]
        for window in windows {
            guard let pid = pid_t(exactly: window.pid), pid > 0, pid != getpid() else { continue }
            membership[pid, default: []].insert(window.id)
        }
        if worker == nil {
            let current = generation
            worker = Worker(subscribe: subscribe) { [weak self] event in
                DispatchQueue.main.async { [weak self] in
                    guard let self, current == self.generation else { return }
                    self.handler?(event)
                }
            }
        }
        worker?.perform { $0.update(membership) }
    }

    @MainActor
    func readTitle(_ element: AXUIElement) async -> String? {
        guard let worker else { return nil }
        let current = generation
        let reader = titleReader
        let title = await withCheckedContinuation { continuation in
            worker.perform { state in
                let title = reader(element)
                // Reconciliation can change the service title without an AX event.
                state.invalidateTitle(element)
                continuation.resume(returning: title)
            }
        }
        return current == generation ? title : nil
    }

    func stop() {
        handler = nil
        stopWorker()
    }

    private func stopWorker() {
        generation += 1
        worker?.stop()
        worker = nil
    }

    deinit { stop() }

    private final class Worker {
        private let state: State
        private let runLoop: CFRunLoop

        init(subscribe: @escaping Subscribe, handler: @escaping (Event) -> Void) {
            let state = State(subscribe: subscribe, handler: handler)
            self.state = state
            let ready = DispatchSemaphore(value: 0)
            // The thread owns State rather than Worker, so releasing the owner can stop it.
            let thread = Thread {
                let port = Port()
                RunLoop.current.add(port, forMode: .default)
                state.runLoop = CFRunLoopGetCurrent()
                ready.signal()
                CFRunLoopRun()
                state.stop()
            }
            thread.name = "a-bar.window-events"
            thread.qualityOfService = .utility
            thread.start()
            ready.wait()
            runLoop = state.runLoop!
        }

        func perform(_ body: @escaping (State) -> Void) {
            let state = state
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) { body(state) }
            CFRunLoopWakeUp(runLoop)
        }

        func stop() {
            perform { state in
                state.stop()
                CFRunLoopStop(CFRunLoopGetCurrent())
            }
        }
    }

    private final class State {
        struct Entry {
            let cancel: () -> Void
            var windows: Set<Int>
            var titles: [(AXUIElement, String?)] = []
        }
        var runLoop: CFRunLoop?
        private let subscribe: Subscribe
        private let handler: (Event) -> Void
        private var entries: [pid_t: Entry] = [:]

        init(subscribe: @escaping Subscribe, handler: @escaping (Event) -> Void) {
            self.subscribe = subscribe
            self.handler = handler
        }

        func update(_ membership: [pid_t: Set<Int>]) {
            var added = false
            for pid in Array(entries.keys) where membership[pid] == nil {
                entries.removeValue(forKey: pid)?.cancel()
            }
            for (pid, windows) in membership {
                if let old = entries[pid] {
                    if old.windows != windows {
                        entries[pid]?.windows = windows
                        entries[pid]?.titles.removeAll()
                    }
                } else if let cancel = subscribe(pid, { [weak self] event in self?.receive(event, pid: pid) }) {
                    entries[pid] = Entry(cancel: cancel, windows: windows)
                    added = true
                }
            }
            if added { handler(.resynchronized) }
        }

        func invalidateTitle(_ element: AXUIElement) {
            for pid in Array(entries.keys) {
                entries[pid]?.titles.removeAll { CFEqual($0.0, element) }
            }
        }

        private func receive(_ event: Event, pid: pid_t) {
            guard var entry = entries[pid] else { return }
            switch event {
            case .moved, .resynchronized, .permissionLost:
                handler(event)
            case .titleChanged(_, let owner, let element, let title):
                guard owner == pid else { return }
                guard title != nil else {
                    invalidateTitle(element)
                    handler(event)
                    return
                }
                if let index = entry.titles.firstIndex(where: { CFEqual($0.0, element) }) {
                    guard entry.titles[index].1 != title else { return }
                    entry.titles[index].1 = title
                } else {
                    entry.titles.append((element, title))
                }
                entries[pid] = entry
                handler(event)
            }
        }

        func stop() {
            for entry in entries.values { entry.cancel() }
            entries.removeAll()
        }
    }

    private static func subscribeNative(pid: pid_t, handler: @escaping (Event) -> Void) -> (() -> Void)? {
        let subscription = AXSubscription(pid: pid, handler: handler)
        var observer: AXObserver?
        guard AXObserverCreate(pid, { _, element, notification, context in
            guard let context else { return }
            Unmanaged<AXSubscription>.fromOpaque(context).takeUnretainedValue().receive(element, notification)
        }, &observer) == .success, let observer else { return nil }
        subscription.observer = observer
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.2)
        let names = nativeWindowIDReader == nil
            ? [kAXWindowMovedNotification] : [kAXWindowMovedNotification, kAXTitleChangedNotification]
        for name in names {
            let result = AXObserverAddNotification(observer, application, name as CFString,
                                                   Unmanaged.passUnretained(subscription).toOpaque())
            if result == .success || result == .notificationAlreadyRegistered {
                subscription.names.append(name)
            }
        }
        guard subscription.names.count == names.count else {
            for name in subscription.names {
                AXObserverRemoveNotification(observer, application, name as CFString)
            }
            return nil // A partial subscription must be retried by the existing service check.
        }
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
        return {
            CFRunLoopSourceInvalidate(AXObserverGetRunLoopSource(observer))
            for name in subscription.names {
                AXObserverRemoveNotification(observer, application, name as CFString)
            }
        }
    }

    private final class AXSubscription {
        var observer: AXObserver?
        var names: [String] = []
        let handler: (Event) -> Void
        let pid: pid_t

        init(pid: pid_t, handler: @escaping (Event) -> Void) {
            self.pid = pid
            self.handler = handler
        }

        func receive(_ element: AXUIElement, _ notification: CFString) {
            if notification as String == kAXWindowMovedNotification {
                handler(.moved)
                return
            }
            guard let id = YabaiWindowEvents.windowID(for: element) else {
                handler(.resynchronized)
                return
            }
            AXUIElementSetMessagingTimeout(element, 0.2)
            var role: CFTypeRef?
            let status = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
            guard status == .success else {
                handler(.titleChanged(id: id, pid: pid, element: element, title: nil))
                return
            }
            guard role as? String == kAXWindowRole else { return }
            handler(.titleChanged(id: id, pid: pid, element: element,
                                  title: YabaiWindowEvents.readNativeTitle(element)))
        }
    }

    // AX has no public CGWindowID mapping. Use the same optional SPI as yabai, never title/frame guesses.
    typealias WindowIDReader = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> Int32
    private static let nativeWindowIDReader: WindowIDReader? = {
        guard let image = dlopen(nil, RTLD_LAZY) else { return nil }
        defer { dlclose(image) }
        guard let symbol = dlsym(image, "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(symbol, to: WindowIDReader.self)
    }()

    static func windowID(for element: AXUIElement, using reader: WindowIDReader? = nativeWindowIDReader) -> Int? {
        guard let reader else { return nil }
        var id: CGWindowID = 0
        guard reader(element, &id) == AXError.success.rawValue, id > 0 else { return nil }
        return Int(id)
    }

    private static func readNativeTitle(_ element: AXUIElement) -> String? {
        AXUIElementSetMessagingTimeout(element, 0.2)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value)
        return result == .noValue ? "" : result == .success ? value as? String : nil
    }
}
