import Foundation

/// Represents a yabai space (desktop/workspace)
struct YabaiSpace: Codable, Identifiable, Equatable {
    let id: Int
    let uuid: String?
    let index: Int
    let label: String?
    let type: SpaceType
    let display: Int
    let windows: [Int]
    let firstWindow: Int?
    let lastWindow: Int?
    
    // Focus state - handle both old and new yabai versions
    var hasFocus: Bool {
        return _hasFocus ?? false
    }
    
    var isVisible: Bool {
        return _isVisible ?? false
    }
    
    var isNativeFullscreen: Bool {
        return _isNativeFullscreen ?? false
    }
    
    // Private properties (current yabai keys)
    private let _hasFocus: Bool?
    private let _isVisible: Bool?
    private let _isNativeFullscreen: Bool?
    
    enum CodingKeys: String, CodingKey {
        case id, uuid, index, label, type, display, windows
        case firstWindow = "first-window"
        case lastWindow = "last-window"
        case _hasFocus = "has-focus"
        case _isVisible = "is-visible"
        case _isNativeFullscreen = "is-native-fullscreen"
    }
    
    /// Space layout type
    enum SpaceType: String, Codable {
        case bsp
        case stack
        case float
    }
    
    /// Display label for the space
    var displayLabel: String {
        if let label = label, !label.isEmpty {
            return label
        }
        return "\(index)"
    }
}

/// Represents a yabai window
struct YabaiWindow: Codable, Identifiable, Equatable {
    let id: Int
    let pid: Int
    let app: String
    let title: String
    let scratchpad: String?
    let frame: WindowFrame
    let role: String?
    let subrole: String?
    let rootWindow: Bool?
    let display: Int
    let space: Int
    let stackIndex: Int?
    let level: Int?
    let subLevel: Int?
    let layer: String?
    let subLayer: String?
    let opacity: Double?
    
    // Window state properties
    var hasFocus: Bool {
        return _hasFocus ?? false
    }
    
    var isVisible: Bool {
        return _isVisible ?? false
    }
    
    var isMinimized: Bool {
        return _isMinimized ?? false
    }
    
    var isHidden: Bool {
        return _isHidden ?? false
    }
    
    var isFloating: Bool {
        return _isFloating ?? false
    }
    
    var isSticky: Bool {
        return _isSticky ?? false
    }
    
    var isTopmost: Bool {
        return _isTopmost ?? false
    }
    
    var isGrabbed: Bool {
        return _isGrabbed ?? false
    }
    
    // Private properties (current yabai keys)
    private let _hasFocus: Bool?
    private let _isVisible: Bool?
    private let _isMinimized: Bool?
    private let _isHidden: Bool?
    private let _isFloating: Bool?
    private let _isSticky: Bool?
    private let _isTopmost: Bool?
    private let _isGrabbed: Bool?
    
    enum CodingKeys: String, CodingKey {
        case id, pid, app, title, scratchpad, frame, role, subrole, display, space, stackIndex = "stack-index", level, opacity, layer
        case rootWindow = "root-window"
        case subLevel = "sub-level"
        case subLayer = "sub-layer"
        case _hasFocus = "has-focus"
        case _isVisible = "is-visible"
        case _isMinimized = "is-minimized"
        case _isHidden = "is-hidden"
        case _isFloating = "is-floating"
        case _isSticky = "is-sticky"
        case _isTopmost = "is-topmost"
        case _isGrabbed = "is-grabbed"
    }
    
    /// Window frame/dimensions
    struct WindowFrame: Codable, Equatable {
        let x: Double
        let y: Double
        let w: Double
        let h: Double
    }
}

/// Represents a yabai display (monitor)
struct YabaiDisplay: Codable, Identifiable, Equatable {
    let id: Int
    let uuid: String
    let index: Int
    let label: String?
    let frame: DisplayFrame
    let spaces: [Int]
    
    var hasFocus: Bool {
        return _hasFocus ?? false
    }
    
    private let _hasFocus: Bool?
    
    enum CodingKeys: String, CodingKey {
        case id, uuid, index, label, frame, spaces
        case _hasFocus = "has-focus"
    }
    
    /// Display frame/dimensions
    struct DisplayFrame: Codable, Equatable {
        let x: Double
        let y: Double
        let w: Double
        let h: Double
    }
}

/// Combined state of all yabai data
struct YabaiState: Equatable {
    var spaces: [YabaiSpace] = []
    var windows: [YabaiWindow] = []
    var displays: [YabaiDisplay] = []
    
    /// Get windows for a specific space
    func windows(forSpace spaceIndex: Int) -> [YabaiWindow] {
        return windows.filter { $0.space == spaceIndex && !$0.isMinimized && !$0.isHidden }
    }
    
    /// Get sticky windows (visible on all spaces)
    func stickyWindows() -> [YabaiWindow] {
        return windows.filter { $0.isSticky && !$0.isMinimized && !$0.isHidden }
    }
    
    /// Get non-sticky windows for a specific space
    func nonStickyWindows(forSpace spaceIndex: Int) -> [YabaiWindow] {
        return windows.filter { 
            $0.space == spaceIndex && 
            !$0.isSticky && 
            !$0.isMinimized && 
            !$0.isHidden 
        }
    }
    
    /// Get the currently focused space
    var focusedSpace: YabaiSpace? {
        return spaces.first { $0.hasFocus }
    }
    
    /// Get the currently focused window
    var focusedWindow: YabaiWindow? {
        return windows.first { $0.hasFocus }
    }
    
    /// Get spaces for a specific display
    func spaces(forDisplay displayIndex: Int) -> [YabaiSpace] {
        return spaces.filter { $0.display == displayIndex }
    }
    
    /// Get display for a specific space
    func display(forSpace spaceIndex: Int) -> YabaiDisplay? {
        guard let space = spaces.first(where: { $0.index == spaceIndex }) else { return nil }
        return displays.first { $0.index == space.display }
    }
    
    /// Get unique apps in a space
    func uniqueApps(forSpace spaceIndex: Int, excludingSticky: Bool = true) -> [YabaiWindow] {
        let spaceWindows = excludingSticky ? nonStickyWindows(forSpace: spaceIndex) : windows(forSpace: spaceIndex)
        var seenApps = Set<String>()
        return spaceWindows.filter { window in
            if seenApps.contains(window.app) {
                return false
            }
            seenApps.insert(window.app)
            return true
        }
    }
}

struct YabaiSignal: Codable, Equatable {
    let index: Int
    let label: String
    let app: String
    let title: String
    let active: Bool?
    let event: String
    let action: String
}
