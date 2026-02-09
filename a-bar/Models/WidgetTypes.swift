import Foundation
import SwiftUI

/// Unique identifier for each widget type
enum WidgetIdentifier: String, Codable, CaseIterable, Identifiable {
  // Window manager widgets (yabai)
  case spaces = "spaces"
  case process = "process"

  // Window manager widgets (AeroSpace)
  case aerospaceSpaces = "aerospace-spaces"
  case aerospaceProcess = "aerospace-process"

  // Data widgets
  case battery = "battery"
  case weather = "weather"
  case time = "time"
  case date = "date-display"
  case wifi = "wifi"
  case sound = "sound"
  case mic = "mic"
  case keyboard = "keyboard"
  case github = "github"
  case hackerNews = "hacker-news"

  // Graph widgets
  case cpu = "cpu"
  case memory = "memory"
  case gpu = "gpu"
  case netstats = "netstats"
  case diskActivity = "disk-activity"
  case storage = "storage"

  // Custom widgets
  case userWidget = "user-widget"

  var id: String { rawValue }

  /// Human-readable display name
  var displayName: String {
    switch self {
    case .spaces: return "Spaces (yabai)"
    case .process: return "Process (yabai)"
    case .aerospaceSpaces: return "Spaces (AeroSpace)"
    case .aerospaceProcess: return "Process (AeroSpace)"
    case .battery: return "Battery"
    case .weather: return "Weather"
    case .time: return "Time"
    case .date: return "Date"
    case .wifi: return "Wi-Fi"
    case .sound: return "Sound"
    case .mic: return "Microphone"
    case .keyboard: return "Keyboard"
    case .github: return "GitHub"
    case .hackerNews: return "Hacker News"
    case .cpu: return "CPU"
    case .memory: return "Memory"
    case .gpu: return "GPU"
    case .netstats: return "Network Stats"
    case .diskActivity: return "Disk Activity"
    case .storage: return "Storage"
    case .userWidget: return "User Widget"
    }
  }

  /// System symbol name for the widget
  var symbolName: String {
    switch self {
    case .spaces: return "square.grid.2x2"
    case .process: return "app.fill"
    case .aerospaceSpaces: return "square.grid.2x2"
    case .aerospaceProcess: return "app.fill"
    case .battery: return "battery.100"
    case .weather: return "cloud.sun"
    case .time: return "clock"
    case .date: return "calendar"
    case .wifi: return "wifi"
    case .sound: return "speaker.wave.2"
    case .mic: return "mic"
    case .keyboard: return "keyboard"
    case .github: return "bell"    
    case .hackerNews: return "newspaper"
    case .cpu: return "cpu"
    case .memory: return "memorychip"
    case .gpu: return "cpu"
    case .netstats: return "network"
    case .diskActivity: return "internaldrive"
    case .storage: return "externaldrive"
    case .userWidget: return "star"
    }
  }

  /// Widget category
  var category: WidgetCategory {
    switch self {
    case .spaces, .process:
      return .yabai
    case .aerospaceSpaces, .aerospaceProcess:
      return .aerospace
    case .cpu, .memory, .gpu, .netstats, .diskActivity, .storage:
      return .graph
    case .userWidget:
      return .custom
    default:
      return .data
    }
  }

  /// Default position (0 = leftmost)
  var defaultPosition: WidgetPosition {
    switch self {
    case .spaces: return .left(0)
    case .process: return .left(2)
    case .aerospaceSpaces: return .left(0)
    case .aerospaceProcess: return .left(2)
    case .userWidget: return .center(0)
    case .hackerNews: return .center(1)
    case .weather: return .right(0)
    case .netstats: return .right(1)
    case .diskActivity: return .right(2)
    case .cpu: return .right(3)
    case .memory: return .right(4)
    case .gpu: return .right(5)
    case .storage: return .right(6)
    case .github: return .right(7)
    case .wifi: return .right(8)
    case .keyboard: return .right(9)
    case .mic: return .right(10)
    case .sound: return .right(11)
    case .battery: return .right(12)
    case .date: return .right(13)
    case .time: return .right(14)
    }
  }
}

/// Categories for grouping widgets
enum WidgetCategory: String, Codable, CaseIterable {
  case yabai = "Yabai"
  case aerospace = "AeroSpace"
  case data = "Data"
  case graph = "Graphs"
  case custom = "Custom"

  var widgets: [WidgetIdentifier] {
    WidgetIdentifier.allCases.filter { $0.category == self }
  }
}

/// Section of the bar
enum WidgetSection: String, Codable, CaseIterable {
  case left
  case center
  case right

  var displayName: String {
    switch self {
    case .left: return "Left"
    case .center: return "Center"
    case .right: return "Right"
    }
  }
}

/// Bar position on screen
enum BarPosition: String, Codable, CaseIterable {
  case top
  case bottom

  var displayName: String {
    switch self {
    case .top: return "Top"
    case .bottom: return "Bottom"
    }
  }
}

/// A single widget instance in a bar section
/// Widgets can appear multiple times across different bars
struct WidgetInstance: Codable, Identifiable, Equatable {
  let id: UUID
  var identifier: WidgetIdentifier
  var enabled: Bool
  var showIcon: Bool
  var userWidgetIndex: Int?  // For user widgets only

  init(
    id: UUID = UUID(),
    identifier: WidgetIdentifier,
    enabled: Bool = true,
    showIcon: Bool = true,
    userWidgetIndex: Int? = nil
  ) {
    self.id = id
    self.identifier = identifier
    self.enabled = enabled
    self.showIcon = showIcon
    self.userWidgetIndex = userWidgetIndex
  }
}

/// Layout configuration for a single bar (top or bottom)
struct SingleBarLayout: Codable, Equatable {
  var left: [WidgetInstance]
  var center: [WidgetInstance]
  var right: [WidgetInstance]

  init(
    left: [WidgetInstance] = [],
    center: [WidgetInstance] = [],
    right: [WidgetInstance] = []
  ) {
    self.left = left
    self.center = center
    self.right = right
  }

  /// Get widgets for a specific section
  func widgets(for section: WidgetSection) -> [WidgetInstance] {
    switch section {
    case .left: return left.filter { $0.enabled }
    case .center: return center.filter { $0.enabled }
    case .right: return right.filter { $0.enabled }
    }
  }

  /// Check if bar has any widgets
  var isEmpty: Bool {
    left.isEmpty && center.isEmpty && right.isEmpty
  }

  /// Default bar layout matching the original a-bar default
  static var defaultTopBar: SingleBarLayout {
    SingleBarLayout(
      left: [
        WidgetInstance(identifier: .spaces),
        WidgetInstance(identifier: .process),
      ],
      center: [],
      right: [
        WidgetInstance(identifier: .weather),
        WidgetInstance(identifier: .netstats),
        WidgetInstance(identifier: .cpu),
        WidgetInstance(identifier: .memory),
        WidgetInstance(identifier: .wifi),
        WidgetInstance(identifier: .keyboard),
        WidgetInstance(identifier: .mic),
        WidgetInstance(identifier: .sound),
        WidgetInstance(identifier: .battery),
        WidgetInstance(identifier: .date),
        WidgetInstance(identifier: .time),
      ]
    )
  }
}

/// Configuration for a single display
struct DisplayConfiguration: Codable, Identifiable, Equatable {
  let id: UUID
  var displayIndex: Int
  var name: String  // User-friendly name (e.g., "Built-in Display", "External Monitor")
  var topBar: SingleBarLayout?
  var bottomBar: SingleBarLayout?

  init(
    id: UUID = UUID(),
    displayIndex: Int,
    name: String = "Display",
    topBar: SingleBarLayout? = nil,
    bottomBar: SingleBarLayout? = nil
  ) {
    self.id = id
    self.displayIndex = displayIndex
    self.name = name
    self.topBar = topBar
    self.bottomBar = bottomBar
  }

  /// Check if display has any bars configured
  var hasBars: Bool {
    topBar != nil || bottomBar != nil
  }
}

/// Complete layout configuration for all displays
struct MultiDisplayLayout: Codable, Equatable {
  var displays: [DisplayConfiguration]

  init(displays: [DisplayConfiguration] = []) {
    self.displays = displays
  }

  /// Get configuration for a specific display index
  func configuration(forDisplay index: Int) -> DisplayConfiguration? {
    displays.first { $0.displayIndex == index }
  }

  /// Get bar layout for a specific display and position
  func barLayout(forDisplay index: Int, position: BarPosition) -> SingleBarLayout? {
    guard let config = configuration(forDisplay: index) else { return nil }
    switch position {
    case .top: return config.topBar
    case .bottom: return config.bottomBar
    }
  }

  /// Update or add a display configuration
  mutating func setConfiguration(_ config: DisplayConfiguration, forDisplay index: Int) {
    if let existingIndex = displays.firstIndex(where: { $0.displayIndex == index }) {
      displays[existingIndex] = config
    } else {
      displays.append(config)
    }
  }

  /// Remove configuration for a display
  mutating func removeConfiguration(forDisplay index: Int) {
    displays.removeAll { $0.displayIndex == index }
  }

  /// Default layout: main display (index 0) with top bar only
  static var defaultLayout: MultiDisplayLayout {
    MultiDisplayLayout(displays: [
      DisplayConfiguration(
        displayIndex: 0,
        name: "Main Display",
        topBar: .defaultTopBar,
        bottomBar: nil
      )
    ])
  }
}

/// Position of a widget in the bar (legacy - kept for migration)
enum WidgetPosition: Codable, Equatable {
  case left(Int)
  case center(Int)
  case right(Int)

  var section: WidgetSection {
    switch self {
    case .left: return .left
    case .center: return .center
    case .right: return .right
    }
  }

  var order: Int {
    switch self {
    case .left(let order), .center(let order), .right(let order):
      return order
    }
  }
}

/// Configuration for a single widget instance (legacy - kept for migration)
struct WidgetConfiguration: Codable, Identifiable, Equatable {
  let id: UUID
  var identifier: WidgetIdentifier
  var enabled: Bool
  var position: WidgetPosition
  var refreshInterval: TimeInterval
  var showOnDisplays: [Int]?
  var showIcon: Bool
  var userWidgetIndex: Int?

  init(
    id: UUID = UUID(),
    identifier: WidgetIdentifier,
    enabled: Bool = true,
    position: WidgetPosition? = nil,
    refreshInterval: TimeInterval = 10,
    showOnDisplays: [Int]? = nil,
    showIcon: Bool = true,
    userWidgetIndex: Int? = nil
  ) {
    self.id = id
    self.identifier = identifier
    self.enabled = enabled
    self.position = position ?? identifier.defaultPosition
    self.refreshInterval = refreshInterval
    self.showOnDisplays = showOnDisplays
    self.showIcon = showIcon
    self.userWidgetIndex = userWidgetIndex
  }

  /// Convert to WidgetInstance
  func toWidgetInstance() -> WidgetInstance {
    WidgetInstance(
      id: id,
      identifier: identifier,
      enabled: enabled,
      showIcon: showIcon,
      userWidgetIndex: userWidgetIndex
    )
  }
}

/// Layout configuration for the bar (legacy - kept for migration)
struct BarLayout: Codable, Equatable {
  var widgets: [WidgetConfiguration]

  static var defaultLayout: BarLayout {
    BarLayout(widgets: [
      WidgetConfiguration(identifier: .spaces),
      WidgetConfiguration(identifier: .process),
      WidgetConfiguration(identifier: .weather),
      WidgetConfiguration(identifier: .netstats),
      WidgetConfiguration(identifier: .cpu),
      WidgetConfiguration(identifier: .memory),
      WidgetConfiguration(identifier: .gpu, enabled: false),
      WidgetConfiguration(identifier: .github, enabled: false),
      WidgetConfiguration(identifier: .wifi),
      WidgetConfiguration(identifier: .keyboard),
      WidgetConfiguration(identifier: .mic),
      WidgetConfiguration(identifier: .sound),
      WidgetConfiguration(identifier: .battery),
      WidgetConfiguration(identifier: .date),
      WidgetConfiguration(identifier: .time),
    ])
  }

  /// Get widgets for a specific section
  func widgets(for section: WidgetSection) -> [WidgetConfiguration] {
    widgets
      .filter { $0.position.section == section && $0.enabled }
      .sorted { $0.position.order < $1.position.order }
  }

  /// Get widget configuration by identifier
  func widget(_ identifier: WidgetIdentifier) -> WidgetConfiguration? {
    widgets.first { $0.identifier == identifier }
  }

  /// Update widget configuration
  mutating func updateWidget(_ configuration: WidgetConfiguration) {
    if let index = widgets.firstIndex(where: { $0.id == configuration.id }) {
      widgets[index] = configuration
    }
  }

  /// Move widget to new position
  mutating func moveWidget(_ id: UUID, to position: WidgetPosition) {
    guard let index = widgets.firstIndex(where: { $0.id == id }) else { return }
    widgets[index].position = position

    // Reorder other widgets in the same section
    let section = position.section
    let sectionWidgets = widgets.enumerated()
      .filter { $0.element.position.section == section }
      .sorted { $0.element.position.order < $1.element.position.order }

    for (newOrder, (originalIndex, _)) in sectionWidgets.enumerated() {
      switch widgets[originalIndex].position {
      case .left:
        widgets[originalIndex].position = .left(newOrder)
      case .center:
        widgets[originalIndex].position = .center(newOrder)
      case .right:
        widgets[originalIndex].position = .right(newOrder)
      }
    }
  }

  /// Convert legacy layout to SingleBarLayout
  func toSingleBarLayout() -> SingleBarLayout {
    SingleBarLayout(
      left: widgets(for: .left).map { $0.toWidgetInstance() },
      center: widgets(for: .center).map { $0.toWidgetInstance() },
      right: widgets(for: .right).map { $0.toWidgetInstance() }
    )
  }
}

/// Definition for a custom user widget
struct UserWidgetDefinition: Codable, Identifiable, Equatable {
  let id: UUID
  var name: String
  var icon: String  // SF Symbol name
  var command: String
  var refreshInterval: TimeInterval  // in seconds
  var clickCommand: String?
  var rightClickCommand: String?
  var backgroundColor: String?  // CSS color or predefined name
  var isActive: Bool
  var hideIcon: Bool
  var hideWhenEmpty: Bool

  init(
    id: UUID = UUID(),
    name: String = "My Widget",
    icon: String = "star",
    command: String = "echo 'Hello'",
    refreshInterval: TimeInterval = 60,
    clickCommand: String? = nil,
    rightClickCommand: String? = nil,
    backgroundColor: String? = nil,
    isActive: Bool = true,
    hideIcon: Bool = false,
    hideWhenEmpty: Bool = false
  ) {
    self.id = id
    self.name = name
    self.icon = icon
    self.command = command
    self.refreshInterval = refreshInterval
    self.clickCommand = clickCommand
    self.rightClickCommand = rightClickCommand
    self.backgroundColor = backgroundColor
    self.isActive = isActive
    self.hideIcon = hideIcon
    self.hideWhenEmpty = hideWhenEmpty
  }

  // Custom decoder for backward compatibility
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    icon = try container.decode(String.self, forKey: .icon)
    command = try container.decode(String.self, forKey: .command)
    refreshInterval = try container.decode(TimeInterval.self, forKey: .refreshInterval)
    clickCommand = try container.decodeIfPresent(String.self, forKey: .clickCommand)
    rightClickCommand = try container.decodeIfPresent(String.self, forKey: .rightClickCommand)
    backgroundColor = try container.decodeIfPresent(String.self, forKey: .backgroundColor)
    isActive = try container.decode(Bool.self, forKey: .isActive)
    hideIcon = try container.decode(Bool.self, forKey: .hideIcon)
    // Provide default value for new property to maintain backward compatibility
    hideWhenEmpty = try container.decodeIfPresent(Bool.self, forKey: .hideWhenEmpty) ?? false
  }
}

/// A data point for graph widgets
struct GraphDataPoint: Identifiable, Equatable {
  let id = UUID()
  let timestamp: Date
  let value: Double

  init(value: Double, timestamp: Date = Date()) {
    self.timestamp = timestamp
    self.value = value
  }
}

/// Graph data history with configurable max length
struct GraphHistory: Equatable {
  var dataPoints: [GraphDataPoint] = []
  let maxLength: Int

  init(maxLength: Int = 50) {
    self.maxLength = maxLength
  }

  mutating func add(_ value: Double) {
    dataPoints.append(GraphDataPoint(value: value))
    if dataPoints.count > maxLength {
      dataPoints.removeFirst(dataPoints.count - maxLength)
    }
  }

  mutating func clear() {
    dataPoints.removeAll()
  }

  var values: [Double] {
    dataPoints.map { $0.value }
  }

  var maxValue: Double {
    dataPoints.map { $0.value }.max() ?? 100
  }
}

/// Network statistics data
struct NetworkStats: Equatable {
  var download: UInt64 = 0
  var upload: UInt64 = 0

  var formattedDownload: String {
    ByteCountFormatter.string(fromByteCount: Int64(download), countStyle: .binary) + "/s"
  }

  var formattedUpload: String {
    ByteCountFormatter.string(fromByteCount: Int64(upload), countStyle: .binary) + "/s"
  }
}
