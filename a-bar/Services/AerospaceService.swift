import AppKit
import Combine
import Foundation

/// Service for interacting with AeroSpace window manager
class AerospaceService: ObservableObject {
    static let shared = AerospaceService()

    @Published private(set) var state = AerospaceState()
    @Published private(set) var isConnected = false
    @Published private(set) var lastError: Error?

    private var refreshWorkItem: DispatchWorkItem?
    private let refreshDebounceInterval: TimeInterval = 0.1
    private var cancellables = Set<AnyCancellable>()
    private let settingsManager = SettingsManager.shared

    private var aerospacePath: String {
        settingsManager.settings.global.aerospacePath
    }

    private var appObservers: [NSObjectProtocol] = []
    private var screenObserver: NSObjectProtocol?

    private init() {
        // Service initialized but observers not set up until start() is called
    }

    private func setupObservers() {
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
                self?.debounceRefresh()
            }
            appObservers.append(observer)
        }

        // Observe display add/removal/reconfiguration
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
    }

    /// Start the AeroSpace service
    func start() {
        setupObservers()
        refresh()
    }

    /// Stop the AeroSpace service
    func stop() {
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
        Task {
            await refreshAll()
        }
    }

    /// Debounced refresh to prevent overlapping events
    private func debounceRefresh() {
        refreshWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.refresh()
        }
        refreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + refreshDebounceInterval, execute: workItem)
    }

    /// Refresh all AeroSpace data in one pass
    private func refreshAll() async {
        do {
            // 1. Get monitors
            let monitorsOutput = try await ShellExecutor.run(
                "\(aerospacePath) list-monitors --json"
            )
            let monitors = try JSONDecoder().decode(
                [AerospaceMonitor].self, from: Data(monitorsOutput.utf8)
            )

            // 2. Get all workspaces with monitor info
            let workspacesOutput = try await ShellExecutor.run(
                "\(aerospacePath) list-workspaces --all --json --format \"%{workspace} %{workspace-is-focused} %{workspace-is-visible} %{monitor-id} %{monitor-name}\""
            )
            var workspaces = try JSONDecoder().decode(
                [AerospaceWorkspace].self, from: Data(workspacesOutput.utf8)
            )

            // 3. Get focused window
            var focusedWindowId: Int? = nil
            do {
                let focusedOutput = try await ShellExecutor.run(
                    "\(aerospacePath) list-windows --focused --json"
                )
                let focusedWindows = try JSONDecoder().decode(
                    [AerospaceWindow].self, from: Data(focusedOutput.utf8)
                )
                focusedWindowId = focusedWindows.first?.windowId
            } catch {
                // No focused window is fine
            }

            // 4. Get windows for all workspaces
            let allWindowsOutput = try await ShellExecutor.run(
                "\(aerospacePath) list-windows --all --json --format \"%{window-id} %{app-name} %{window-title} %{workspace} %{monitor-id}\""
            )
            let allWindowsRaw = try JSONDecoder().decode(
                [AerospaceWindow].self, from: Data(allWindowsOutput.utf8)
            )

            // 5. Group windows by workspace and mark focused
            for i in workspaces.indices {
                let wsName = workspaces[i].workspace
                workspaces[i].windows = allWindowsRaw
                    .filter { $0.workspace == wsName }
                    .map { window in
                        var w = window
                        w.isFocused = (w.windowId == focusedWindowId)
                        return w
                    }
            }

            let finalWorkspaces = workspaces
            let finalMonitors = monitors
            await MainActor.run { [finalWorkspaces, finalMonitors] in
                self.state = AerospaceState(workspaces: finalWorkspaces, monitors: finalMonitors)
                self.isConnected = true
                self.lastError = nil
            }
        } catch {
            await MainActor.run {
                self.lastError = error
                self.isConnected = false
            }
            print("AeroSpace error: \(error)")
        }
    }

    /// Switch to a specific workspace
    func goToWorkspace(_ name: String) async {
        do {
            try await ShellExecutor.run("\(aerospacePath) workspace \(name)")
            refresh()
        } catch {
            await MainActor.run {
                self.lastError = error
            }
        }
    }

    /// Focus a specific window
    func focusWindow(_ id: Int) async {
        do {
            try await ShellExecutor.run("\(aerospacePath) focus --window-id \(id)")
            refresh()
        } catch {
            await MainActor.run {
                self.lastError = error
            }
        }
    }
}

