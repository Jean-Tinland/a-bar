import AppKit
import Combine
import Foundation

/// Service for interacting with yabai window manager
class YabaiService: ObservableObject {
    static let shared = YabaiService()

    @Published private(set) var state = YabaiState()
    @Published private(set) var isConnected = false
    @Published private(set) var lastError: Error?

    private var refreshTimer: Timer?
    private var refreshWorkItem: DispatchWorkItem?
    private let refreshDebounceInterval: TimeInterval = 0.1
    private var cancellables = Set<AnyCancellable>()
    private let settingsManager = SettingsManager.shared

    private var yabaiPath: String {
        settingsManager.settings.global.yabaiPath
    }

    private var spaceObserver: NSObjectProtocol?
    private var appObservers: [NSObjectProtocol] = []
    private var screenObserver: NSObjectProtocol?

    private init() {
        // Observe macOS Space changes
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }

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
            ) { [weak self] note in
                self?.handleAppNotification(note)
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

    // Handle NSWorkspace app notifications
    private func handleAppNotification(_ note: Notification) {
        // Always refresh on these events, but debounce to avoid overlapping
        debounceRefresh()
    }

    /// Start the yabai service
    func start() {
        refresh()
        setupYabaiSignals()
    }

    /// Stop the yabai service
    func stop() {
        if let observer = spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            spaceObserver = nil
        }
        let nc = NSWorkspace.shared.notificationCenter
        for observer in appObservers {
            nc.removeObserver(observer)
        }
        appObservers.removeAll()

        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
            screenObserver = nil
        }
        
        // Remove yabai signals on stop
        removeYabaiSignals()
    }
    
    /// Set up yabai signals to automatically refresh on window events
    private func setupYabaiSignals() {
        Task {
            do {
                // Remove any existing signals first
                removeYabaiSignals()
                
                // Add signal for window destroyed
                let destroyedCmd = "\(yabaiPath) -m signal --add event=window_destroyed action=\"osascript -e 'tell application \\\"a-bar\\\" to refresh \\\"yabai\\\"'\" label=\"abar-window-destroyed\""
                _ = try await ShellExecutor.run(destroyedCmd)
                
                // Add signal for window title changed
                let titleCmd = "\(yabaiPath) -m signal --add event=window_title_changed action=\"osascript -e 'tell application \\\"a-bar\\\" to refresh \\\"yabai\\\"'\" label=\"abar-window-title-changed\""
                _ = try await ShellExecutor.run(titleCmd)
                
                print("✓ Yabai signals registered successfully")
            } catch {
                print("⚠️ Failed to register yabai signals: \(error)")
            }
        }
    }
    
    /// Remove yabai signals registered by a-bar
    private func removeYabaiSignals() {
        Task {
            do {
                _ = try? await ShellExecutor.run("\(yabaiPath) -m signal --remove abar-window-destroyed")
                _ = try? await ShellExecutor.run("\(yabaiPath) -m signal --remove abar-window-title-changed")
            }
        }
    }

    /// Manually refresh all yabai data
    func refresh() {
        Task {
            await refreshSpaces()
            await refreshWindows()
            await refreshDisplays()
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

    /// Refresh spaces data
    func refreshSpaces() async {
        do {
            let output = try await ShellExecutor.run("\(yabaiPath) -m query --spaces")
            let spaces = try JSONDecoder().decode([YabaiSpace].self, from: Data(output.utf8))
            await MainActor.run {
                self.state.spaces = spaces
                self.isConnected = true
                self.lastError = nil
            }
        } catch {
            await handleError(error)
        }
    }

    /// Refresh windows data
    func refreshWindows() async {
        do {
            let output = try await ShellExecutor.run("\(yabaiPath) -m query --windows")
            // Clean up the output (handle yabai quirks)
            let cleanedOutput =
                output
                .replacingOccurrences(of: "\\\n", with: "")
                .replacingOccurrences(of: "00000", with: "0")
            let windows = try JSONDecoder().decode(
                [YabaiWindow].self, from: Data(cleanedOutput.utf8))
            await MainActor.run {
                self.state.windows = windows
                self.isConnected = true
                self.lastError = nil
            }
        } catch {
            await handleError(error)
        }
    }

    /// Refresh displays data
    func refreshDisplays() async {
        do {
            let output = try await ShellExecutor.run("\(yabaiPath) -m query --displays")
            let displays = try JSONDecoder().decode([YabaiDisplay].self, from: Data(output.utf8))
            await MainActor.run {
                self.state.displays = displays
                self.isConnected = true
                self.lastError = nil
            }
        } catch {
            await handleError(error)
        }
    }

    /// Focus on a specific space
    func goToSpace(_ index: Int) async {
        do {
            try await ShellExecutor.run("\(yabaiPath) -m space --focus \(index)")
        } catch {
            await handleError(error)
        }
    }

    /// Rename a space
    func renameSpace(_ index: Int, label: String) async {
        do {
            try await ShellExecutor.run("\(yabaiPath) -m space \(index) --label \"\(label)\"")
        } catch {
            await handleError(error)
        }
    }

    /// Create a new space on a display
    func createSpace(onDisplay displayIndex: Int) async {
        do {
            try await focusDisplay(displayIndex)
            try await ShellExecutor.run("\(yabaiPath) -m space --create")
        } catch {
            await handleError(error)
        }
    }

    /// Remove a space
    func removeSpace(_ index: Int, onDisplay displayIndex: Int) async {
        do {
            try await focusDisplay(displayIndex)
            try await ShellExecutor.run("\(yabaiPath) -m space \(index) --destroy")
        } catch {
            await handleError(error)
        }
    }

    /// Swap a space with another in the given direction
    func swapSpace(_ index: Int, direction: SwapDirection) async {
        let targetIndex = direction == .left ? index - 1 : index + 1
        do {
            try await ShellExecutor.run("\(yabaiPath) -m space \(index) --swap \(targetIndex)")
        } catch {
            await handleError(error)
        }
    }

    /// Focus on a specific window
    func focusWindow(_ id: Int) async {
        do {
            try await ShellExecutor.run("\(yabaiPath) -m window --focus \(id)")
        } catch {
            await handleError(error)
        }
    }

    /// Focus on a specific display
    private func focusDisplay(_ index: Int) async throws {
        try await ShellExecutor.run("\(yabaiPath) -m display --focus \(index)")
    }

    // Timer logic removed

    @MainActor
    private func handleError(_ error: Error) {
        self.lastError = error
        self.isConnected = false
        print("Yabai error: \(error)")
    }

    enum SwapDirection {
        case left
        case right
    }
}
