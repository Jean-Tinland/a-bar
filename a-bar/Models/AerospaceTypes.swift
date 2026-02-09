import Foundation

/// Represents an AeroSpace workspace
struct AerospaceWorkspace: Codable, Identifiable, Equatable {
    /// Workspace name (AeroSpace uses string names, not indices)
    let workspace: String

    /// Whether this workspace is currently focused
    var isFocused: Bool

    /// Whether this workspace is currently visible
    var isVisible: Bool

    /// The monitor ID this workspace belongs to
    let monitorId: Int

    /// The monitor name
    let monitorName: String

    /// Windows in this workspace (populated separately)
    var windows: [AerospaceWindow] = []

    var id: String { workspace }

    /// Display label for the workspace
    var displayLabel: String {
        workspace
    }

    enum CodingKeys: String, CodingKey {
        case workspace
        case isFocused = "workspace-is-focused"
        case isVisible = "workspace-is-visible"
        case monitorId = "monitor-id"
        case monitorName = "monitor-name"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        workspace = try container.decode(String.self, forKey: .workspace)
        monitorId = try container.decode(Int.self, forKey: .monitorId)
        monitorName = try container.decodeIfPresent(String.self, forKey: .monitorName) ?? ""

        // AeroSpace returns booleans as strings ("true"/"false") in some versions
        if let boolValue = try? container.decode(Bool.self, forKey: .isFocused) {
            isFocused = boolValue
        } else if let stringValue = try? container.decode(String.self, forKey: .isFocused) {
            isFocused = stringValue.lowercased() == "true"
        } else {
            isFocused = false
        }

        if let boolValue = try? container.decode(Bool.self, forKey: .isVisible) {
            isVisible = boolValue
        } else if let stringValue = try? container.decode(String.self, forKey: .isVisible) {
            isVisible = stringValue.lowercased() == "true"
        } else {
            isVisible = false
        }
    }

    init(
        workspace: String,
        isFocused: Bool = false,
        isVisible: Bool = false,
        monitorId: Int = 1,
        monitorName: String = "",
        windows: [AerospaceWindow] = []
    ) {
        self.workspace = workspace
        self.isFocused = isFocused
        self.isVisible = isVisible
        self.monitorId = monitorId
        self.monitorName = monitorName
        self.windows = windows
    }
}

/// Represents an AeroSpace window
struct AerospaceWindow: Codable, Identifiable, Equatable {
    let windowId: Int
    let appName: String
    let windowTitle: String
    let workspace: String
    let monitorId: Int

    /// Whether this window is focused (populated separately)
    var isFocused: Bool = false

    var id: Int { windowId }

    enum CodingKeys: String, CodingKey {
        case windowId = "window-id"
        case appName = "app-name"
        case windowTitle = "window-title"
        case workspace
        case monitorId = "monitor-id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        windowId = try container.decode(Int.self, forKey: .windowId)
        appName = try container.decode(String.self, forKey: .appName)
        windowTitle = try container.decodeIfPresent(String.self, forKey: .windowTitle) ?? ""
        workspace = try container.decodeIfPresent(String.self, forKey: .workspace) ?? ""
        monitorId = try container.decodeIfPresent(Int.self, forKey: .monitorId) ?? 1
    }

    init(
        windowId: Int,
        appName: String,
        windowTitle: String = "",
        workspace: String = "",
        monitorId: Int = 1,
        isFocused: Bool = false
    ) {
        self.windowId = windowId
        self.appName = appName
        self.windowTitle = windowTitle
        self.workspace = workspace
        self.monitorId = monitorId
        self.isFocused = isFocused
    }
}

/// Represents an AeroSpace monitor
struct AerospaceMonitor: Codable, Identifiable, Equatable {
    let monitorId: Int
    let monitorName: String

    var id: Int { monitorId }

    enum CodingKeys: String, CodingKey {
        case monitorId = "monitor-id"
        case monitorName = "monitor-name"
    }
}

/// Combined state of all AeroSpace data
struct AerospaceState: Equatable {
    var workspaces: [AerospaceWorkspace] = []
    var monitors: [AerospaceMonitor] = []

    /// Get workspaces for a specific monitor
    func workspaces(forMonitor monitorId: Int) -> [AerospaceWorkspace] {
        return workspaces.filter { $0.monitorId == monitorId }
    }

    /// Get the currently focused workspace
    var focusedWorkspace: AerospaceWorkspace? {
        return workspaces.first { $0.isFocused }
    }

    /// Get the currently focused window
    var focusedWindow: AerospaceWindow? {
        for workspace in workspaces {
            if let focused = workspace.windows.first(where: { $0.isFocused }) {
                return focused
            }
        }
        return nil
    }

    /// Get all windows across all workspaces
    var allWindows: [AerospaceWindow] {
        workspaces.flatMap { $0.windows }
    }

    /// Get windows for a specific workspace
    func windows(forWorkspace name: String) -> [AerospaceWindow] {
        return workspaces.first { $0.workspace == name }?.windows ?? []
    }

    /// Get unique apps in a workspace
    func uniqueApps(forWorkspace name: String) -> [AerospaceWindow] {
        let windows = self.windows(forWorkspace: name)
        var seenApps = Set<String>()
        return windows.filter { window in
            if seenApps.contains(window.appName) {
                return false
            }
            seenApps.insert(window.appName)
            return true
        }
    }
}

/// Enum representing the window manager choice
enum WindowManager: String, Codable, CaseIterable, Identifiable {
    case yabai
    case aerospace = "aerospace"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .yabai: return "yabai"
        case .aerospace: return "AeroSpace"
        }
    }
}
