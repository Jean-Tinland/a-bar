import AppKit
import Foundation

/// Service for interacting with AeroSpace window manager
class AerospaceService: ObservableObject {
    static let shared = AerospaceService()

    @Published private(set) var state = AerospaceState()
    @Published private(set) var isConnected = false
    @Published private(set) var lastError: Error?

    private var refreshWorkItem: DispatchWorkItem?
    private var refreshTask: Task<Void, Never>?
    private var pendingRefresh = false
    private var isStarted = false
    private var refreshGeneration = 0
    private let refreshDebounceInterval: TimeInterval = 0.1
    private let settingsManager: SettingsManager

    private var aerospacePath: String {
        settingsManager.settings.global.aerospacePath
    }

    private var appObservers: [NSObjectProtocol] = []
    private var screenObserver: NSObjectProtocol?

    init(settingsManager: SettingsManager = .shared) {
        // Observers are not set up until start() is called.
        self.settingsManager = settingsManager
    }

    private func setupObservers() {
        let generation = refreshGeneration
        // Observe app activation/deactivation/launch/termination/hide/unhide
        let nc = NSWorkspace.shared.notificationCenter
        let notifications: [NSNotification.Name] = [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didDeactivateApplicationNotification,
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
            ) { [weak self] _ in
                guard let self, self.isStarted, generation == self.refreshGeneration else { return }
                self.debounceRefresh()
            }
            appObservers.append(observer)
        }

        // Observe display add/removal/reconfiguration
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isStarted, generation == self.refreshGeneration else { return }
            self.refresh()
        }
    }

    /// Start the AeroSpace service
    func start() {
        guard !isStarted else { return }
        isStarted = true
        setupObservers()
        refresh()
    }

    /// Stop the AeroSpace service
    func stop() {
        isStarted = false
        refreshGeneration += 1
        refreshWorkItem?.cancel()
        refreshWorkItem = nil
        refreshTask?.cancel()
        refreshTask = nil
        pendingRefresh = false
        let nc = NSWorkspace.shared.notificationCenter
        for observer in appObservers {
            nc.removeObserver(observer)
        }
        appObservers.removeAll()

        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
            screenObserver = nil
        }
    }

    /// Manually refresh all AeroSpace data
    func refresh() {
        guard isStarted else { return }
        pendingRefresh = true
        guard refreshTask == nil else { return }
        let generation = refreshGeneration
        refreshTask = Task { @MainActor in
            repeat {
                guard isStarted, generation == refreshGeneration, !Task.isCancelled else { return }
                pendingRefresh = false
                await refreshAll(generation: generation)
                guard isStarted, generation == refreshGeneration, !Task.isCancelled else { return }
            } while pendingRefresh
            refreshTask = nil
        }
    }

    /// Debounced refresh to prevent overlapping events
    private func debounceRefresh() {
        guard isStarted else { return }
        let generation = refreshGeneration
        refreshWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isStarted, generation == self.refreshGeneration else { return }
            self.refreshWorkItem = nil
            self.refresh()
        }
        refreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + refreshDebounceInterval, execute: workItem)
    }

    /// Refresh all AeroSpace data in one pass
    @MainActor
    private func refreshAll(generation: Int) async {
        let path = aerospacePath
        do {
            try Task.checkCancellation()
            // 1. Get monitors
            let monitorsOutput = try await ShellExecutor.run(
                "\(path) list-monitors --json"
            )
            let monitors = try JSONDecoder().decode(
                [AerospaceMonitor].self, from: Data(monitorsOutput.utf8)
            )

            try Task.checkCancellation()

            // 2. Get all workspaces with monitor info
            let workspacesOutput = try await ShellExecutor.run(
                "\(path) list-workspaces --all --json --format \"%{workspace} %{workspace-is-focused} %{workspace-is-visible} %{monitor-id} %{monitor-name}\""
            )
            let workspaces = try JSONDecoder().decode(
                [AerospaceWorkspace].self, from: Data(workspacesOutput.utf8)
            )

            try Task.checkCancellation()

            // 3. Get focused window
            var focusedWindowId: Int? = nil
            do {
                let focusedOutput = try await ShellExecutor.run(
                    "\(path) list-windows --focused --json"
                )
                let focusedWindows = try JSONDecoder().decode(
                    [AerospaceWindow].self, from: Data(focusedOutput.utf8)
                )
                focusedWindowId = focusedWindows.first?.windowId
            } catch {
                // No focused window is fine
            }

            try Task.checkCancellation()

            // 4. Get windows for all workspaces
            let allWindowsOutput = try await ShellExecutor.run(
                "\(path) list-windows --all --json --format \"%{window-id} %{app-name} %{window-title} %{workspace} %{monitor-id}\""
            )
            let allWindowsRaw = try JSONDecoder().decode(
                [AerospaceWindow].self, from: Data(allWindowsOutput.utf8)
            )

            // 5. Group windows by workspace and mark focused
            let finalWorkspaces = AerospaceMerge.merge(
                workspaces: workspaces,
                windows: allWindowsRaw,
                focusedWindowId: focusedWindowId)
            let finalMonitors = monitors
            guard isStarted, generation == refreshGeneration, !Task.isCancelled else { return }
            state = AerospaceState(workspaces: finalWorkspaces, monitors: finalMonitors)
            isConnected = true
            lastError = nil
        } catch {
            guard isStarted, generation == refreshGeneration, !Task.isCancelled else { return }
            lastError = error
            isConnected = false
            print("AeroSpace error: \(error)")
        }
    }

    /// Switch to a specific workspace
    func goToWorkspace(_ name: String) async {
        let generation = refreshGeneration
        do {
            try await ShellExecutor.run("\(aerospacePath) workspace \(name)")
            await MainActor.run {
                guard generation == self.refreshGeneration else { return }
                self.refresh()
            }
        } catch {
            await MainActor.run {
                guard generation == self.refreshGeneration else { return }
                self.lastError = error
            }
        }
    }

    /// Focus a specific window
    func focusWindow(_ id: Int) async {
        let generation = refreshGeneration
        do {
            try await ShellExecutor.run("\(aerospacePath) focus --window-id \(id)")
            await MainActor.run {
                guard generation == self.refreshGeneration else { return }
                self.refresh()
            }
        } catch {
            await MainActor.run {
                guard generation == self.refreshGeneration else { return }
                self.lastError = error
            }
        }
    }
}

