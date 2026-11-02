import AppKit
import Foundation
import Darwin
import notify
import ApplicationServices

/// Service for interacting with yabai window manager
class YabaiService: ObservableObject {
    static let shared = YabaiService()

    @Published private(set) var state = YabaiState()
    @Published private(set) var isConnected = false
    @Published private(set) var lastError: Error?
    @Published private(set) var signalsRegistered = false

    private var signalTimer: Timer?
    private var signalTask: Task<Void, Never>?
    private let refreshNotification: String
    private var signalPath: String?
    private static let signalEvents = [
        ("window_destroyed", "abar-window-destroyed"),
        ("window_created", "abar-window-created"),
        ("window_minimized", "abar-window-minimized"),
        ("window_deminimized", "abar-window-deminimized"),
        ("window_title_changed", "abar-window-title-changed"),
        ("window_focused", "abar-window-focused"),
        ("window_moved", "abar-window-moved"),
    ]
    private let settingsManager: SettingsManager
    private let windowEvents: YabaiWindowEvents?
    private let workspaceNotifications: NotificationCenter
    private let screenNotifications: NotificationCenter
    private var requestedAccessibility = false
    private struct NativeTitle {
        let pid: Int
        let element: AXUIElement
        var title: String
        var revision: Int
    }
    private var nativeTitles: [Int: NativeTitle] = [:]
    private var nativeTitleRevision = 0
    private enum RefreshScope: Equatable { case focus(Int?), windows, full }
    private var focusToken: Int32 = -1
    // Native calls are injectable so token zero and registration failure are testable.
    private let registerFocus: (String, inout Int32) -> UInt32
    private let readFocus: (Int32, inout UInt64) -> UInt32
    private let cancelFocus: (Int32) -> UInt32
    private var requestRevision = 0
    private var lastActivatedPID: pid_t?
    private var projectionSupported = true
    private let frontmostPID: () -> pid_t?
    private static let windowFields = "id,pid,app,title,frame,subrole,display,space,stack-index,has-focus,is-visible,is-minimized,is-hidden,is-floating,is-sticky"
    private var focusRefreshNotification: String { refreshNotification + ".window-focused" }
    private var isStarted = false
    private var refreshGeneration = 0
    private var refreshTask: Task<Void, Never>?
    private var moveRefreshTask: Task<Void, Never>?
    private var pendingRefresh: RefreshScope?
    private var hasFullSnapshot = false

    private var titleRefreshNotification: String {
        refreshNotification + ".window-title-changed"
    }

    private var moveRefreshNotification: String {
        refreshNotification + ".window-moved"
    }

    private var yabaiPath: String {
        settingsManager.settings.global.yabaiPath
    }

    private var spaceObserver: NSObjectProtocol?
    private var appObservers: [NSObjectProtocol] = []
    private var screenObserver: NSObjectProtocol?

    init(
        settingsManager: SettingsManager = .shared,
        refreshNotification: String = "user.uid.\(getuid()).com.jeantinland.a-bar.yabai",
        windowEvents: YabaiWindowEvents? = YabaiWindowEvents(),
        workspaceNotifications: NotificationCenter = NSWorkspace.shared.notificationCenter,
        screenNotifications: NotificationCenter = .default,
        frontmostPID: @escaping () -> pid_t? = { NSWorkspace.shared.frontmostApplication?.processIdentifier },
        registerFocus: @escaping (String, inout Int32) -> UInt32 = { notify_register_check($0, &$1) },
        readFocus: @escaping (Int32, inout UInt64) -> UInt32 = { notify_get_state($0, &$1) },
        cancelFocus: @escaping (Int32) -> UInt32 = { notify_cancel($0) }
    ) {
        self.settingsManager = settingsManager
        self.windowEvents = windowEvents
        self.workspaceNotifications = workspaceNotifications
        self.screenNotifications = screenNotifications
        self.refreshNotification = refreshNotification
        self.frontmostPID = frontmostPID
        self.registerFocus = registerFocus
        self.readFocus = readFocus
        self.cancelFocus = cancelFocus
    }

    private func setupObservers() {
        let generation = refreshGeneration
        // Observe macOS Space changes
        spaceObserver = workspaceNotifications.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isStarted, generation == self.refreshGeneration else { return }
            self.refresh()
        }

        // Observe app activation/deactivation/launch/termination/hide/unhide
        let nc = workspaceNotifications
        let notifications: [NSNotification.Name] = [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
        ]
        for name in notifications {
            let observer = nc.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] note in
                guard let self, self.isStarted, generation == self.refreshGeneration else { return }
                self.handleAppNotification(note)
            }
            appObservers.append(observer)
        }

        // Observe display add/removal/reconfiguration
        screenObserver = screenNotifications.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isStarted, generation == self.refreshGeneration else { return }
            self.refresh()
        }
    }

    // Handle NSWorkspace app notifications
    func handleAppNotification(_ note: Notification) {
        if note.name == NSWorkspace.didActivateApplicationNotification {
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
                ?? frontmostPID()
            guard pid != lastActivatedPID else { return }
            lastActivatedPID = pid
            refresh(.focus(nil))
        } else {
            refresh()
        }
    }

    /// Start the yabai service
    func start() {
        if isStarted {
            guard signalPath != yabaiPath else { return }
            stop()
        }
        // Keep the name alive while notifyutil sets state and posts from a separate process.
        if registerFocus(focusRefreshNotification, &focusToken) != NOTIFY_STATUS_OK {
            focusToken = -1
        }
        projectionSupported = true
        lastActivatedPID = frontmostPID()
        for notification in [refreshNotification, titleRefreshNotification, moveRefreshNotification, focusRefreshNotification] {
            CFNotificationCenterAddObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                Unmanaged.passUnretained(self).toOpaque(),
                { _, observer, name, _, _ in
                    guard let observer, let name else { return }
                    let service = Unmanaged<YabaiService>.fromOpaque(observer).takeUnretainedValue()
                    let notification = name.rawValue as String
                    let generation = service.refreshGeneration
                    DispatchQueue.main.async { [weak service] in
                        guard let service, service.isStarted, generation == service.refreshGeneration else { return }
                        if notification == service.focusRefreshNotification {
                            var candidate: UInt64 = 0
                            if service.focusToken >= 0,
                               service.readFocus(service.focusToken, &candidate) == NOTIFY_STATUS_OK,
                               candidate > 0, candidate <= UInt64(UInt32.max) {
                                service.refresh(.focus(Int(candidate)))
                            } else {
                                service.refresh(.full)
                            }
                        } else if notification == service.moveRefreshNotification {
                            service.scheduleMoveRefresh()
                        } else {
                            service.refresh(notification == service.titleRefreshNotification ? .windows : .full)
                        }
                    }
                },
                notification as CFString, nil, .deliverImmediately)
        }
        isStarted = true
        let generation = refreshGeneration
        windowEvents?.start { [weak self] event in
            guard let self, self.isStarted, generation == self.refreshGeneration else { return }
            switch event {
            case .moved: self.scheduleMoveRefresh()
            case .titleChanged(let id, let pid, let element, let title):
                self.applyNativeTitle(id: id, pid: pid, element: element, title: title)
            case .resynchronized: self.refresh()
            case .permissionLost:
                self.nativeTitles.removeAll()
                self.refresh()
            }
        }
        if windowEvents?.isTrusted == false, !requestedAccessibility {
            requestedAccessibility = true
            requestWindowObservationAccess()
        }
        hasFullSnapshot = false
        signalPath = yabaiPath
        setupObservers()
        refresh()
        setupYabaiSignals()
        startSignalTimer()
    }

    /// Stop the yabai service
    func stop() {
        guard isStarted else { return }
        isStarted = false
        windowEvents?.stop()
        nativeTitles.removeAll()
        if focusToken >= 0 { _ = cancelFocus(focusToken); focusToken = -1 }
        lastActivatedPID = nil
        for notification in [refreshNotification, titleRefreshNotification, moveRefreshNotification, focusRefreshNotification] {
            CFNotificationCenterRemoveObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                Unmanaged.passUnretained(self).toOpaque(),
                CFNotificationName(notification as CFString), nil)
        }
        refreshGeneration += 1
        cancelMoveRefresh()
        refreshTask?.cancel()
        refreshTask = nil
        signalTask?.cancel()
        pendingRefresh = nil
        hasFullSnapshot = false
        if let observer = spaceObserver {
            workspaceNotifications.removeObserver(observer)
            spaceObserver = nil
        }
        let nc = workspaceNotifications
        for observer in appObservers {
            nc.removeObserver(observer)
        }
        appObservers.removeAll()

        if let observer = screenObserver {
            screenNotifications.removeObserver(observer)
            screenObserver = nil
        }
        
        // Stop signal timer
        stopSignalTimer()
        
        // Serialize removal with registration, including a quick stop/start cycle.
        updateSignals(register: false, path: signalPath ?? yabaiPath)
        signalPath = nil
        if signalsRegistered { signalsRegistered = false }
    }
    
    /// Start the periodic timer to re-register yabai signals
    private func startSignalTimer() {
        // Stop any existing timer
        stopSignalTimer()
        
        // Create a new timer that fires every 20 seconds
        let generation = refreshGeneration
        signalTimer = Timer.scheduledTimer(withTimeInterval: 20.0, repeats: true) { [weak self] _ in
            guard let self, self.isStarted, generation == self.refreshGeneration else { return }
            self.setupYabaiSignals()
            self.windowEvents?.update(self.state.windows)
        }
    }

    func requestWindowObservationAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    
    /// Stop the periodic signal timer
    private func stopSignalTimer() {
        signalTimer?.invalidate()
        signalTimer = nil
    }
    
    /// Darwin notifications avoid an AppleScript process and watchdog per window event.
    private func signalAction(for event: String) -> String {
        let notification: String
        switch event {
        case "window_title_changed": notification = titleRefreshNotification
        case "window_moved": notification = moveRefreshNotification
        case "window_focused" where focusToken >= 0:
            return "/usr/bin/notifyutil -z 0 -s \(focusRefreshNotification) \"$YABAI_WINDOW_ID\" -p \(focusRefreshNotification)"
        default: notification = refreshNotification
        }
        return "/usr/bin/notifyutil -p \(notification)"
    }

    private func setupYabaiSignals() {
        guard isStarted else { return }
        updateSignals(register: true, path: yabaiPath)
    }

    private func updateSignals(register: Bool, path: String) {
        let previous = signalTask
        let generation = refreshGeneration
        signalTask = Task { @MainActor in
            await previous?.value
            if !register {
                for (_, label) in Self.signalEvents {
                    _ = try? await ShellExecutor.run(executable: path, arguments: ["-m", "signal", "--remove", label])
                }
                return
            }
            guard isStarted, generation == refreshGeneration, !Task.isCancelled else { return }
            do {
                let output = try await ShellExecutor.run(executable: path, arguments: ["-m", "signal", "--list"])
                let signals = try JSONDecoder().decode([YabaiSignal].self, from: Data(output.utf8))
                for (event, label) in Self.signalEvents {
                    guard isStarted, generation == refreshGeneration, !Task.isCancelled else { return }
                    // Retire high-rate shell notifications when upgrading an existing installation.
                    if event == "window_moved" ||
                        (event == "window_title_changed" && windowEvents?.supportsTitles != false) {
                        if signals.contains(where: { $0.label == label }) {
                            try await ShellExecutor.run(executable: path, arguments: ["-m", "signal", "--remove", label])
                        }
                        continue
                    }
                    let action = signalAction(for: event)
                    if signals.contains(where: { $0.label == label && $0.event == event && $0.action == action }) { continue }
                    try await ShellExecutor.run(executable: path, arguments: [
                        "-m", "signal", "--add", "event=\(event)", "action=\(action)", "label=\(label)"])
                }
                guard isStarted, generation == refreshGeneration, !Task.isCancelled else { return }
                if !signalsRegistered { signalsRegistered = true }
            } catch {
                guard isStarted, generation == refreshGeneration, !Task.isCancelled else { return }
                if signalsRegistered { signalsRegistered = false }
                print("Failed to register yabai signals: \(error). Retrying in 20 seconds.")
            }
        }
    }

    /// Manual and structural events always request a complete snapshot.
    func refresh() {
        refresh(.full)
    }

    /// Keep one pending request, with complete snapshots taking precedence over title updates.
    private func enqueueRefresh(_ scope: RefreshScope) {
        if scope == .full || pendingRefresh == nil {
            pendingRefresh = scope
        } else if pendingRefresh != .full {
            // A windows read also carries focus; never discard a queued title update.
            if scope == .windows || pendingRefresh != .windows { pendingRefresh = scope }
        }
    }

    /// AX move delivery can be 140-290ms apart during a drag. Wait 300ms for the final relationships.
    private func scheduleMoveRefresh() {
        guard isStarted else { return }
        cancelMoveRefresh()
        let generation = refreshGeneration
        moveRefreshTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
            } catch { return }
            guard let self, self.isStarted, generation == self.refreshGeneration, !Task.isCancelled else { return }
            self.moveRefreshTask = nil
            self.refresh(.full)
        }
    }

    private func cancelMoveRefresh() {
        moveRefreshTask?.cancel()
        moveRefreshTask = nil
    }

    private func refresh(_ requestedScope: RefreshScope) {
        guard isStarted else { return }
        requestRevision += 1
        if requestedScope == .full { cancelMoveRefresh(); hasFullSnapshot = false }
        enqueueRefresh(requestedScope)
        guard refreshTask == nil else { return }
        let generation = refreshGeneration
        refreshTask = Task { @MainActor in
            while let requested = pendingRefresh {
                guard isStarted, generation == refreshGeneration, !Task.isCancelled else { return }
                pendingRefresh = nil
                let scope: RefreshScope = hasFullSnapshot ? requested : .full
                // A structural event or title fallback supersedes any delayed move snapshot.
                if scope == .full { cancelMoveRefresh() }
                let path = yabaiPath
                let revision = requestRevision
                let titleRevision = nativeTitleRevision
                do {
                    var next: YabaiState
                    var queriedFocusWindowID: Int?
                    switch scope {
                    case .focus(let id):
                        let window: YabaiWindow = try await fetch("windows", path: path,
                            selector: ["--window"] + (id.map { [String($0)] } ?? []))
                        guard isStarted, generation == refreshGeneration, !Task.isCancelled else { return }
                        guard revision == requestRevision else { continue }
                        guard window.hasFocus, window.pid == frontmostPID().map(Int.init),
                              id == nil || window.id == id,
                              let patched = state.updatingFocus(window) else {
                            enqueueRefresh(.full)
                            continue
                        }
                        queriedFocusWindowID = window.id
                        next = patched
                    case .full:
                        async let spaces: [YabaiSpace] = fetch("spaces", path: path)
                        async let windows: [YabaiWindow] = fetch("windows", path: path)
                        async let displays: [YabaiDisplay] = fetch("displays", path: path)
                        next = try await YabaiState(spaces: spaces, windows: windows, displays: displays)
                        next.windows = filteredWindows(next.windows)
                        if next.focusedWindow == nil, let pid = frontmostPID() {
                            next = next.selectingVisibleWindow(for: Int(pid))
                        }
                    case .windows:
                        let windows = filteredWindows(try await fetch("windows", path: path))
                        guard isStarted, generation == refreshGeneration, !Task.isCancelled else { return }
                        // A title event may race a structural change. Do not combine those windows
                        // with cached Space/display membership; wait for the complete follow-up.
                        guard pendingRefresh != .full, canApplyTitleUpdate(windows) else {
                            enqueueRefresh(.full)
                            continue
                        }
                        next = state
                        next.windows = windows
                    }
                    guard let reconciled = await reconcileNativeTitles(next, startedAt: titleRevision,
                        freshWindowID: queriedFocusWindowID, pruneMissing: scope == .full, generation: generation) else { return }
                    next = reconciled
                    if case .focus = scope, revision != requestRevision { continue }
                    if scope == .windows, pendingRefresh == .full { continue }
                    // A stopped service must not overwrite a newer generation's state or flags.
                    guard isStarted, generation == refreshGeneration, !Task.isCancelled else { return }
                    if scope == .full {
                        hasFullSnapshot = true
                        windowEvents?.update(next.windows)
                    }
                    if state != next { state = next }
                    if !isConnected { isConnected = true }
                    if lastError != nil { lastError = nil }
                } catch {
                    guard isStarted, generation == refreshGeneration, !Task.isCancelled else { return }
                    if case .focus = scope, revision != requestRevision { continue }
                    hasFullSnapshot = false
                    handleError(error, generation: generation)
                    // Retry a failed partial read once as a full snapshot. A failed full read
                    // waits for another event instead of creating an unbounded retry loop.
                    if scope != .full { enqueueRefresh(.full) }
                }
            }
            refreshTask = nil
        }
    }

    private func applyNativeTitle(id: Int, pid: pid_t, element: AXUIElement, title: String?) {
        guard id > 0, id <= Int(UInt32.max), pid > 0 else { return }
        let matches = state.windows.indices.filter { state.windows[$0].id == id }
        guard matches.count <= 1,
              matches.first.map({ state.windows[$0].pid == Int(pid) }) ?? true else { return }
        guard let title else {
            nativeTitles.removeValue(forKey: id)
            refresh(.windows)
            return
        }
        nativeTitleRevision += 1
        nativeTitles[id] = NativeTitle(pid: Int(pid), element: element, title: title, revision: nativeTitleRevision)
        guard let index = matches.first else { refresh(); return }
        var next = state
        next.windows[index] = next.windows[index].replacingTitle(title)
        if state != next { state = next }
    }

    /// AX and yabai receive title events independently. Keep an in-flight old snapshot
    /// from undoing a native title, but re-read conflicts so a lost AX event cannot pin stale text.
    @MainActor
    private func reconcileNativeTitles(_ snapshot: YabaiState, startedAt revision: Int,
                                       freshWindowID: Int?, pruneMissing: Bool, generation: Int) async -> YabaiState? {
        var next = snapshot
        // A focus patch contains cached siblings; only the queried window can acknowledge its title.
        for window in snapshot.windows where freshWindowID == nil || window.id == freshWindowID {
            guard let old = nativeTitles[window.id], old.pid == window.pid else { continue }
            if old.title == window.title {
                nativeTitles.removeValue(forKey: window.id)
                continue
            }
            let confirmed = await windowEvents?.readTitle(old.element)
            guard isStarted, generation == refreshGeneration, !Task.isCancelled else { return nil }
            guard var current = nativeTitles[window.id], current.revision == old.revision else { continue }
            guard let confirmed else { nativeTitles.removeValue(forKey: window.id); continue }
            if current.title != confirmed {
                nativeTitleRevision += 1
                current.title = confirmed
                current.revision = nativeTitleRevision
                nativeTitles[window.id] = current
            }
            if confirmed == window.title { nativeTitles.removeValue(forKey: window.id) }
        }
        // A later native callback may arrive while another window's AX read is suspended.
        for index in next.windows.indices {
            let window = next.windows[index]
            if let title = nativeTitles[window.id], title.pid == window.pid {
                next.windows[index] = window.replacingTitle(title.title)
            }
        }
        if pruneMissing {
            nativeTitles = nativeTitles.filter { id, title in
                title.revision > revision || next.windows.contains { $0.id == id && $0.pid == title.pid }
            }
        }
        return next
    }

    private func filteredWindows(_ windows: [YabaiWindow]) -> [YabaiWindow] {
        windows.filter { window in
            guard let subrole = window.subrole else { return false }
            return !subrole.isEmpty && subrole != "AXDialog"
        }
    }

    /// Match identities and the fields that connect windows to cached Spaces/displays.
    /// Removing each ID also rejects duplicates without trapping on malformed input.
    private func canApplyTitleUpdate(_ windows: [YabaiWindow]) -> Bool {
        guard state.windows.count == windows.count else { return false }
        var previous: [Int: YabaiWindow] = [:]
        for window in state.windows {
            guard previous.updateValue(window, forKey: window.id) == nil else { return false }
        }
        for window in windows {
            guard let old = previous.removeValue(forKey: window.id),
                  old.pid == window.pid, old.space == window.space, old.display == window.display,
                  old.hasFocus == window.hasFocus, old.isVisible == window.isVisible,
                  old.isMinimized == window.isMinimized, old.isHidden == window.isHidden,
                  old.isSticky == window.isSticky else { return false }
        }
        return previous.isEmpty
    }

    /// Serialize projection capability with lifecycle state; ShellExecutor performs I/O off-thread.
    @MainActor
    private func fetch<T: Decodable>(_ collection: String, path: String, selector: [String] = []) async throws -> T {
        try Task.checkCancellation()
        let generation = refreshGeneration
        let projected = collection == "windows" && projectionSupported
        let base = ["-m", "query", "--\(collection)"]
        let output: String
        do {
            output = try await ShellExecutor.run(executable: path,
                arguments: base + (projected ? [Self.windowFields] : []) + selector)
        } catch {
            let message = error.localizedDescription
            // Only an explicit rejection of our field argument disables projection.
            guard projected, message.contains(Self.windowFields),
                  message.contains("unknown option") || message.contains("unknown property") else { throw error }
            guard generation == refreshGeneration, !Task.isCancelled else { throw CancellationError() }
            projectionSupported = false
            output = try await ShellExecutor.run(executable: path, arguments: base + selector)
        }
        return try await Self.decode(output)
    }

    /// Nonisolated async decoding leaves large snapshots and sanitizer work off the UI actor.
    private static func decode<T: Decodable>(_ output: String) async throws -> T {
        try Task.checkCancellation()
        let decoder = JSONDecoder()
        // Valid output needs no repair and must retain its literal string values.
        if let value = try? decoder.decode(T.self, from: Data(output.utf8)) { return value }
        return try decoder.decode(
            T.self, from: Data(YabaiJSONSanitizer.sanitize(output).utf8))
    }

    /// Focus on a specific space
    func goToSpace(_ index: Int) async {
        let generation = refreshGeneration
        do {
            try await ShellExecutor.run(executable: yabaiPath, arguments: ["-m", "space", "--focus", String(index)])
            await refreshAfterMutation(generation: generation)
        } catch {
            await handleError(error, generation: generation)
        }
    }

    /// Rename a space
    func renameSpace(_ index: Int, label: String) async {
        let generation = refreshGeneration
        do {
            try await ShellExecutor.run(executable: yabaiPath, arguments: ["-m", "space", String(index), "--label", label])
            await refreshAfterMutation(generation: generation)
        } catch {
            await handleError(error, generation: generation)
        }
    }

    /// Create a new space on a display
    func createSpace(onDisplay displayIndex: Int) async {
        let generation = refreshGeneration
        do {
            try await focusDisplay(displayIndex)
            try await ShellExecutor.run(executable: yabaiPath, arguments: ["-m", "space", "--create"])
            await refreshAfterMutation(generation: generation)
        } catch {
            await handleError(error, generation: generation)
        }
    }

    /// Remove a space
    func removeSpace(_ index: Int, onDisplay displayIndex: Int) async {
        let generation = refreshGeneration
        do {
            try await focusDisplay(displayIndex)
            try await ShellExecutor.run(executable: yabaiPath, arguments: ["-m", "space", String(index), "--destroy"])
            await refreshAfterMutation(generation: generation)
        } catch {
            await handleError(error, generation: generation)
        }
    }

    /// Swap a space with another in the given direction
    func swapSpace(_ index: Int, direction: SwapDirection) async {
        let generation = refreshGeneration
        let targetIndex = direction == .left ? index - 1 : index + 1
        do {
            try await ShellExecutor.run(executable: yabaiPath, arguments: ["-m", "space", String(index), "--swap", String(targetIndex)])
            await refreshAfterMutation(generation: generation)
        } catch {
            await handleError(error, generation: generation)
        }
    }

    /// Focus on a specific window
    func focusWindow(_ id: Int) async {
        let generation = refreshGeneration
        do {
            try await ShellExecutor.run(executable: yabaiPath, arguments: ["-m", "window", "--focus", String(id)])
            await refreshAfterMutation(generation: generation)
        } catch {
            await handleError(error, generation: generation)
        }
    }

    /// Focus on a specific display
    private func focusDisplay(_ index: Int) async throws {
        try await ShellExecutor.run(executable: yabaiPath, arguments: ["-m", "display", "--focus", String(index)])
    }

    @MainActor
    private func refreshAfterMutation(generation: Int) {
        guard generation == refreshGeneration else { return }
        refresh()
    }

    @MainActor
    private func handleError(_ error: Error, generation: Int) {
        guard generation == refreshGeneration else { return }
        self.lastError = error
        self.isConnected = false
        print("Yabai error: \(error)")
    }

    enum SwapDirection {
        case left
        case right
    }
}
