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

        var systemImage: String {
            switch self {
            case .bsp: return "square.grid.2x2"
            case .stack: return "rectangle.stack"
            case .float: return "rectangle.on.rectangle"
            }
        }
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
    private(set) var title: String
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

    // Match the SketchyBar window classifier; sticky remains an independent state.
    var layoutType: YabaiSpace.SpaceType {
        if isFloating { return .float }
        return (stackIndex ?? 0) > 0 ? .stack : .bsp
    }

    var layoutLabel: String { layoutType.rawValue }
    
    var isTopmost: Bool {
        return _isTopmost ?? false
    }
    
    var isGrabbed: Bool {
        return _isGrabbed ?? false
    }
    
    // Private properties (current yabai keys)
    private var _hasFocus: Bool?
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
    
    func replacingTitle(_ title: String) -> YabaiWindow {
        var window = self
        window.title = title
        return window
    }

    fileprivate mutating func setFocus(_ focused: Bool) { _hasFocus = focused }

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
    
    /// Patch only a known member of the currently focused Space/display. Sticky windows
    /// keep their home Space, so their display and the cached current Space are checked separately.
    func updatingFocus(_ window: YabaiWindow) -> YabaiState? {
        guard window.hasFocus, !window.isHidden, !window.isMinimized,
              let current = focusedSpace, current.display == window.display,
              displays.contains(where: { $0.index == window.display && $0.hasFocus }),
              window.isSticky || window.space == current.index,
              let index = windows.firstIndex(where: { $0.id == window.id }),
              windows.filter({ $0.id == window.id }).count == 1 else { return nil }
        let old = windows[index]
        guard old.pid == window.pid, old.app == window.app, old.space == window.space,
              old.display == window.display, old.isSticky == window.isSticky,
              old.isHidden == window.isHidden, old.isMinimized == window.isMinimized,
              old.isVisible == window.isVisible, old.subrole == window.subrole,
              spaces.contains(where: { $0.index == window.space && $0.windows.contains(window.id) }) else { return nil }
        var next = self
        for i in next.windows.indices { next.windows[i].setFocus(false) }
        next.windows[index] = window
        return next
    }

    /// Unmanaged apps may not expose a focused yabai window. Match the front app only,
    /// preferring its visible window on the current Space; Desktop keeps no selection.
    func selectingVisibleWindow(for pid: Int) -> YabaiState {
        let candidates = windows.indices.filter {
            windows[$0].pid == pid && windows[$0].isVisible &&
                !windows[$0].isHidden && !windows[$0].isMinimized
        }
        let selected = candidates.first {
            windows[$0].space == focusedSpace?.index || windows[$0].isSticky
        } ?? candidates.first
        var next = self
        for i in next.windows.indices { next.windows[i].setFocus(i == selected) }
        return next
    }

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
        return WindowFilter.deduplicatedByApp(spaceWindows, appName: \.app)
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

/// Values actually rendered by Process and Spaces. Geometry stays in the raw snapshot;
/// callers sort first, so a position change invalidates the UI only if the order changes.
struct YabaiWindowPresentation: Equatable, Identifiable {
    let id: Int
    let app: String
    let title: String
    let hasFocus: Bool
    let stackIndex: Int?
    let isSticky: Bool
    let layoutType: YabaiSpace.SpaceType
    var layoutLabel: String { layoutType.rawValue }

    init(_ window: YabaiWindow) {
        id = window.id
        app = window.app
        title = window.title
        hasFocus = window.hasFocus
        stackIndex = window.stackIndex
        isSticky = window.isSticky
        layoutType = window.layoutType
    }
}
