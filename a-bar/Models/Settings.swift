import Combine
import Foundation
import SwiftUI

/// Enum representing available theme colors for widget customization
enum ThemeColor: String, Codable, CaseIterable, Identifiable {
  case main
  case mainAlt
  case minor
  case accent
  case red
  case green
  case yellow
  case orange
  case blue
  case magenta
  case cyan
  case foreground
  case background
  case highlight

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .mainAlt: return "Main Alt"
    default: return rawValue.capitalized
    }
  }

  /// Get the actual Color from a theme
  func color(from theme: ABarTheme) -> Color {
    switch self {
    case .main: return theme.main
    case .mainAlt: return theme.mainAlt
    case .minor: return theme.minor
    case .accent: return theme.accent
    case .red: return theme.red
    case .green: return theme.green
    case .yellow: return theme.yellow
    case .orange: return theme.orange
    case .blue: return theme.blue
    case .magenta: return theme.magenta
    case .cyan: return theme.cyan
    case .foreground: return theme.foreground
    case .background: return theme.background
    case .highlight: return theme.highlight
    }
  }
}

/// Manages application settings with persistence
class SettingsManager: ObservableObject {
  static let shared = SettingsManager()

  @Published var settings: ABarSettings
  @Published var draftSettings: ABarSettings
  @Published var hasUnsavedChanges: Bool = false
  
  /// The profile currently being edited in the Layout settings
  /// This is NOT the same as the active profile - it's just what's being edited
  @Published var editingProfileId: UUID? = nil
  
  /// Draft layout being edited (separate from profiles)
  @Published var draftLayout: MultiDisplayLayout = .defaultLayout

  private let settingsKey = "abar-settings"
  private let userDefaults = UserDefaults.standard
  private var cancellables = Set<AnyCancellable>()

  /// Path to the configuration file in the user's home directory
  private var configFilePath: URL? {
    guard let homeDir = FileManager.default.homeDirectoryForCurrentUser as URL? else {
      return nil
    }
    return homeDir.appendingPathComponent(".a-barrc")
  }

  private init() {
    // Load settings from UserDefaults
    let userDefaultsSettings: ABarSettings
    if let data = userDefaults.data(forKey: settingsKey) {
      if let decoded = try? JSONDecoder().decode(ABarSettings.self, from: data) {
        userDefaultsSettings = decoded
      } else if let recovered = SettingsManager.recoverSettingsByMergingDefaults(with: data) {
        userDefaultsSettings = recovered
        // persist the merged settings back so future loads succeed
        if let encoded = try? JSONEncoder().encode(recovered) {
          userDefaults.set(encoded, forKey: settingsKey)
        }
      } else {
        userDefaultsSettings = ABarSettings()
      }
    } else {
      userDefaultsSettings = ABarSettings()
    }

    // Initialize properties first before using self
    self.settings = userDefaultsSettings
    self.draftSettings = userDefaultsSettings
    self.hasUnsavedChanges = false

    // Load settings from config file and merge (after initialization)
    if let fileSettings = loadSettingsFromFile() {
      // Merge file settings with UserDefaults settings
      let mergedSettings = mergeSettings(base: userDefaultsSettings, override: fileSettings)
      self.settings = mergedSettings
      self.draftSettings = mergedSettings
    }

    // Monitor changes to draftSettings with debounce to avoid constant re-renders
    $draftSettings
      .dropFirst()  // Skip the initial value
      .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
      .sink { [weak self] newDraft in
        guard let self = self else { return }
        self.hasUnsavedChanges = (newDraft != self.settings)
      }
      .store(in: &cancellables)
    
    // Monitor changes to draftLayout
    $draftLayout
      .dropFirst()  // Skip the initial value
      .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
      .sink { [weak self] _ in
        guard let self = self else { return }
        self.hasUnsavedChanges = true
      }
      .store(in: &cancellables)
  }

  func saveSettingsNow(_ settings: ABarSettings) {
    if let encoded = try? JSONEncoder().encode(settings) {
      userDefaults.set(encoded, forKey: settingsKey)
    }
    saveSettingsToFile(settings)
  }

  func saveSettings() {
    // Save the layout to the profile being edited (not necessarily the active one)
    if let editId = editingProfileId {
      ProfileManager.shared.updateProfileLayout(id: editId, layout: draftLayout)
    } else if let activeId = ProfileManager.shared.activeProfile?.id {
      // Fallback: save to active profile if no editing profile is set
      ProfileManager.shared.updateProfileLayout(id: activeId, layout: draftLayout)
    }
    
    // Sync profiles from ProfileManager before saving
    draftSettings.profiles = ProfileManager.shared.profiles
    draftSettings.activeProfileId = ProfileManager.shared.activeProfileId.uuidString
    
    settings = draftSettings
    saveSettingsNow(settings)
    hasUnsavedChanges = false
  }

  func resetToDefaults() {
    draftSettings = ABarSettings()
  }

  func discardChanges() {
    draftSettings = settings
    hasUnsavedChanges = false
  }

  /// Save settings to the config file (~/.a-barrc)
  private func saveSettingsToFile(_ settings: ABarSettings) {
    guard let filePath = configFilePath else {
      print("⚠️ Unable to determine config file path")
      return
    }

    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(settings)
      try data.write(to: filePath, options: .atomic)
    } catch {
      print("⚠️ Failed to save settings to file: \(error.localizedDescription)")
    }
  }

  /// Load settings from the config file (~/.a-barrc)
  private func loadSettingsFromFile() -> ABarSettings? {
    guard let filePath = configFilePath else {
      return nil
    }

    guard FileManager.default.fileExists(atPath: filePath.path) else {
      print("ℹ️ Config file not found at \(filePath.path)")
      return nil
    }

    guard let data = try? Data(contentsOf: filePath) else {
      print("⚠️ Failed to read config file at \(filePath.path)")
      return nil
    }

    // First, validate that it's valid JSON
    guard (try? JSONSerialization.jsonObject(with: data, options: [])) != nil else {
      print("⚠️ Config file contains invalid JSON - skipping import")
      return nil
    }

    // Try to decode with standard decoder
    let decoder = JSONDecoder()
    do {
      let settings = try decoder.decode(ABarSettings.self, from: data)
      if let validated = validateSettings(settings) {
        return validated
      } else {
        print("⚠️ Settings validation failed - using recovery mode")
        return tryRecoverSettings(from: data, filePath: filePath)
      }
    } catch let error as DecodingError {
      print("⚠️ Decoding error: \(describeDecodingError(error))")
      return tryRecoverSettings(from: data, filePath: filePath)
    } catch {
      print("⚠️ Failed to load settings: \(error.localizedDescription)")
      return tryRecoverSettings(from: data, filePath: filePath)
    }
  }

  /// Attempt to recover settings by merging with defaults
  private func tryRecoverSettings(from data: Data, filePath: URL) -> ABarSettings? {
    if let recovered = SettingsManager.recoverSettingsByMergingDefaults(with: data) {
      if let validated = validateSettings(recovered) {
        // Save the recovered settings back to file to prevent future errors
        saveSettingsToFile(validated)
        return validated
      }
    }
    print("⚠️ Unable to recover settings - using defaults")
    return nil
  }

  /// Validate settings to ensure they contain sensible values
  private func validateSettings(_ settings: ABarSettings) -> ABarSettings? {
    var validated = settings

    // Validate global settings
    if validated.global.barHeight < 10 || validated.global.barHeight > 100 {
      print("⚠️ Invalid barHeight (\(validated.global.barHeight)), using default")
      validated.global.barHeight = 34
    }

    if validated.global.fontSize < 6 || validated.global.fontSize > 72 {
      print("⚠️ Invalid fontSize (\(validated.global.fontSize)), using default")
      validated.global.fontSize = 11
    }

    if validated.global.barPadding < 0 || validated.global.barPadding > 50 {
      print("⚠️ Invalid barPadding (\(validated.global.barPadding)), using default")
      validated.global.barPadding = 4
    }

    if validated.global.barCornerRadius < 0 || validated.global.barCornerRadius > 50 {
      print("⚠️ Invalid barCornerRadius (\(validated.global.barCornerRadius)), using default")
      validated.global.barCornerRadius = 6
    }

    if validated.global.barElementGap < 0 || validated.global.barElementGap > 50 {
      print("⚠️ Invalid barElementGap (\(validated.global.barElementGap)), using default")
      validated.global.barElementGap = 4
    }

    // Validate refresh intervals
    validated.widgets.battery.refreshInterval = max(1, validated.widgets.battery.refreshInterval)
    validated.widgets.weather.refreshInterval = max(60, validated.widgets.weather.refreshInterval)
    validated.widgets.time.refreshInterval = max(0.1, validated.widgets.time.refreshInterval)
    validated.widgets.cpu.refreshInterval = max(0.5, validated.widgets.cpu.refreshInterval)
    validated.widgets.memory.refreshInterval = max(0.5, validated.widgets.memory.refreshInterval)
    validated.widgets.gpu.refreshInterval = max(0.5, validated.widgets.gpu.refreshInterval)
    validated.widgets.netstats.refreshInterval = max(
      0.5, validated.widgets.netstats.refreshInterval)
    validated.widgets.storage.refreshInterval = max(10, validated.widgets.storage.refreshInterval)

    return validated
  }

  /// Provide human-readable description of decoding errors
  private func describeDecodingError(_ error: DecodingError) -> String {
    switch error {
    case .typeMismatch(let type, let context):
      return
        "Type mismatch for \(type) at \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
    case .valueNotFound(let type, let context):
      return
        "Missing required value of type \(type) at \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
    case .keyNotFound(let key, let context):
      return
        "Missing required key '\(key.stringValue)' at \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
    case .dataCorrupted(let context):
      return
        "Data corrupted at \(context.codingPath.map { $0.stringValue }.joined(separator: ".")): \(context.debugDescription)"
    @unknown default:
      return "Unknown decoding error"
    }
  }

  /// Merge two settings objects, with override taking precedence
  private func mergeSettings(base: ABarSettings, override: ABarSettings) -> ABarSettings {
    // For now, we simply use the override settings as they represent the file content
    // In the future, we could implement more sophisticated merging if needed
    return override
  }
}

extension SettingsManager {
  fileprivate static func recoverSettingsByMergingDefaults(with data: Data) -> ABarSettings? {
    guard
      let saved = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
      let defaultData = try? JSONEncoder().encode(ABarSettings()),
      let defaults = try? JSONSerialization.jsonObject(with: defaultData, options: [])
        as? [String: Any]
    else {
      return nil
    }

    let merged = deepMerge(defaults: defaults, saved: saved)

    guard JSONSerialization.isValidJSONObject(merged),
      let mergedData = try? JSONSerialization.data(withJSONObject: merged, options: [])
    else {
      return nil
    }

    return try? JSONDecoder().decode(ABarSettings.self, from: mergedData)
  }

  fileprivate static func deepMerge(defaults: [String: Any], saved: [String: Any]) -> [String: Any]
  {
    var result = defaults
    for (key, savedValue) in saved {
      if let savedDict = savedValue as? [String: Any],
        let defaultDict = defaults[key] as? [String: Any]
      {
        result[key] = deepMerge(defaults: defaultDict, saved: savedDict)
      } else {
        result[key] = savedValue
      }
    }
    return result
  }
}

/// Root settings object
struct ABarSettings: Codable, Equatable {
  var global: GlobalSettings = GlobalSettings()
  var theme: ThemeSettings = ThemeSettings()
  var widgets: WidgetSettings = WidgetSettings()
  var userWidgets: [UserWidgetDefinition] = []
  var profiles: [LayoutProfile] = []
  var activeProfileId: String? = nil

  // Custom decoder to handle migration from old layout format
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    global = try container.decodeIfPresent(GlobalSettings.self, forKey: .global) ?? GlobalSettings()
    theme = try container.decodeIfPresent(ThemeSettings.self, forKey: .theme) ?? ThemeSettings()
    widgets =
      try container.decodeIfPresent(WidgetSettings.self, forKey: .widgets) ?? WidgetSettings()
    userWidgets =
      try container.decodeIfPresent([UserWidgetDefinition].self, forKey: .userWidgets) ?? []
    profiles =
      try container.decodeIfPresent([LayoutProfile].self, forKey: .profiles) ?? []
    activeProfileId = try container.decodeIfPresent(String.self, forKey: .activeProfileId)
  }

  init() {
    // Default initializer
  }

  private enum CodingKeys: String, CodingKey {
    case global, theme, widgets, userWidgets, profiles, activeProfileId
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(global, forKey: .global)
    try container.encode(theme, forKey: .theme)
    try container.encode(widgets, forKey: .widgets)
    try container.encode(userWidgets, forKey: .userWidgets)
    try container.encode(profiles, forKey: .profiles)
    try container.encodeIfPresent(activeProfileId, forKey: .activeProfileId)
  }
}

/// Global application settings
struct GlobalSettings: Codable, Equatable {
  var barEnabled: Bool = true
  var launchAtLogin: Bool = false
  var barHeight: CGFloat = 34
  var fontSize: CGFloat = 11
  var fontName: String = ""
  var barPadding: CGFloat = 4
  var barCornerRadius: CGFloat = 6
  var showBorder: Bool = false
  var noColorInDataWidgets: Bool = false

  // Yabai configuration
  var yabaiPath: String = "/opt/homebrew/bin/yabai"

  // Icon appearance
  var grayscaleAppIcons: Bool = false

  // Notification settings
  var enableNotifications: Bool = true

  var barElementGap: CGFloat = 4  // Gap between bar elements (widgets)
}

/// Theme and appearance settings
struct ThemeSettings: Codable, Equatable {
  var appearance: Appearance = .auto
  var darkTheme: ThemePreset = .nightShift
  var lightTheme: ThemePreset = .dayShift

  // Color overrides (nil means use theme default)
  var colorOverrides: ColorOverrides = ColorOverrides()

  enum Appearance: String, Codable, CaseIterable {
    case auto
    case dark
    case light

    var displayName: String {
      switch self {
      case .auto: return "Auto"
      case .dark: return "Dark"
      case .light: return "Light"
      }
    }
  }
}

/// Color overrides for theme customization
struct ColorOverrides: Codable, Equatable {
  var main: String?
  var mainAlt: String?
  var minor: String?
  var accent: String?
  var red: String?
  var green: String?
  var yellow: String?
  var orange: String?
  var blue: String?
  var magenta: String?
  var cyan: String?
  var foreground: String?
  var background: String?
}

/// Settings for individual widgets
struct WidgetSettings: Codable, Equatable {
  var spaces: SpacesWidgetSettings = SpacesWidgetSettings()
  var process: ProcessWidgetSettings = ProcessWidgetSettings()
  var battery: BatteryWidgetSettings = BatteryWidgetSettings()
  var weather: WeatherWidgetSettings = WeatherWidgetSettings()
  var time: TimeWidgetSettings = TimeWidgetSettings()
  var date: DateWidgetSettings = DateWidgetSettings()
  var wifi: WifiWidgetSettings = WifiWidgetSettings()
  var sound: SoundWidgetSettings = SoundWidgetSettings()
  var mic: MicWidgetSettings = MicWidgetSettings()
  var keyboard: KeyboardWidgetSettings = KeyboardWidgetSettings()
  var github: GitHubWidgetSettings = GitHubWidgetSettings()
  var cpu: CPUWidgetSettings = CPUWidgetSettings()
  var memory: MemoryWidgetSettings = MemoryWidgetSettings()
  var gpu: GPUWidgetSettings = GPUWidgetSettings()
  var netstats: NetstatsWidgetSettings = NetstatsWidgetSettings()
  var diskActivity: DiskActivityWidgetSettings = DiskActivityWidgetSettings()
  var storage: StorageWidgetSettings = StorageWidgetSettings()
  var hackerNews: HackerNewsWidgetSettings = HackerNewsWidgetSettings()
  
  // Custom decoder to handle missing keys gracefully (for backwards compatibility)
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    
    spaces = (try? container.decode(SpacesWidgetSettings.self, forKey: .spaces)) ?? SpacesWidgetSettings()
    process = (try? container.decode(ProcessWidgetSettings.self, forKey: .process)) ?? ProcessWidgetSettings()
    battery = (try? container.decode(BatteryWidgetSettings.self, forKey: .battery)) ?? BatteryWidgetSettings()
    weather = (try? container.decode(WeatherWidgetSettings.self, forKey: .weather)) ?? WeatherWidgetSettings()
    time = (try? container.decode(TimeWidgetSettings.self, forKey: .time)) ?? TimeWidgetSettings()
    date = (try? container.decode(DateWidgetSettings.self, forKey: .date)) ?? DateWidgetSettings()
    wifi = (try? container.decode(WifiWidgetSettings.self, forKey: .wifi)) ?? WifiWidgetSettings()
    sound = (try? container.decode(SoundWidgetSettings.self, forKey: .sound)) ?? SoundWidgetSettings()
    mic = (try? container.decode(MicWidgetSettings.self, forKey: .mic)) ?? MicWidgetSettings()
    keyboard = (try? container.decode(KeyboardWidgetSettings.self, forKey: .keyboard)) ?? KeyboardWidgetSettings()
    github = (try? container.decode(GitHubWidgetSettings.self, forKey: .github)) ?? GitHubWidgetSettings()
    cpu = (try? container.decode(CPUWidgetSettings.self, forKey: .cpu)) ?? CPUWidgetSettings()
    memory = (try? container.decode(MemoryWidgetSettings.self, forKey: .memory)) ?? MemoryWidgetSettings()
    gpu = (try? container.decode(GPUWidgetSettings.self, forKey: .gpu)) ?? GPUWidgetSettings()
    netstats = (try? container.decode(NetstatsWidgetSettings.self, forKey: .netstats)) ?? NetstatsWidgetSettings()
    diskActivity = (try? container.decode(DiskActivityWidgetSettings.self, forKey: .diskActivity)) ?? DiskActivityWidgetSettings()
    storage = (try? container.decode(StorageWidgetSettings.self, forKey: .storage)) ?? StorageWidgetSettings()
    hackerNews = (try? container.decode(HackerNewsWidgetSettings.self, forKey: .hackerNews)) ?? HackerNewsWidgetSettings()
  }
  
  init() {}
  
  private enum CodingKeys: String, CodingKey {
    case spaces, process, battery, weather, time, date, wifi, sound, mic, keyboard, github
    case cpu, memory, gpu, netstats, diskActivity, storage, hackerNews
  }
}

struct SpacesWidgetSettings: Codable, Equatable {
  var hideEmptySpaces: Bool = false
  var showAllSpacesOnAllScreens: Bool = false
  var displayStickyWindowsSeparately: Bool = true
  var hideDuplicateApps: Bool = true
  var exclusions: String = ""
  var titleExclusions: String = ""
  var exclusionsAsRegex: Bool = false
  var hideCreateSpaceButton: Bool = false
  var switchSpacesWithoutYabai: Bool = false
}

struct ProcessWidgetSettings: Codable, Equatable {
  var showCurrentSpaceOnly: Bool = true
  var hideWindowTitle: Bool = false
  var displayOnlyIcon: Bool = false
  var showLayoutMode: Bool = true
}

struct BatteryWidgetSettings: Codable, Equatable {
  var refreshInterval: TimeInterval = 10
  var toggleCaffeinateOnClick: Bool = true
  var caffeinateOption: String = "systemSleep"
  var backgroundColor: ThemeColor = .magenta
  var showIcon: Bool = true

  enum CaffeinateOption: String, Codable, CaseIterable {
    case displaySleep = "displaySleep"
    case systemSleep = "systemSleep"
    case diskSleep = "diskSleep"
    case all = "all"
  }
}

struct WeatherWidgetSettings: Codable, Equatable {
  var refreshInterval: TimeInterval = 1800  // 30 minutes
  var customLocation: String = ""
  var unit: TemperatureUnit = .celsius
  var hideLocation: Bool = true
  var showIcon: Bool = true

  enum TemperatureUnit: String, Codable, CaseIterable {
    case celsius = "C"
    case fahrenheit = "F"
  }
}

struct TimeWidgetSettings: Codable, Equatable {
  var refreshInterval: TimeInterval = 1
  var hour12: Bool = false
  var showSeconds: Bool = false
  var showDayProgress: Bool = false
  var backgroundColor: ThemeColor = .yellow
  var showIcon: Bool = true
}

struct DateWidgetSettings: Codable, Equatable {
  var refreshInterval: TimeInterval = 30
  var shortFormat: Bool = false
  var locale: String = "en-UK"
  var calendarApp: String = "Calendar"
  var backgroundColor: ThemeColor = .cyan
  var showIcon: Bool = true
}

struct WifiWidgetSettings: Codable, Equatable {
  var refreshInterval: TimeInterval = 20
  var hideWhenDisabled: Bool = false
  var toggleOnClick: Bool = true
  var networkDevice: String = "en0"
  var hideNetworkName: Bool = false
  var backgroundColor: ThemeColor = .red
  var showIcon: Bool = true
}

struct SoundWidgetSettings: Codable, Equatable {
  var refreshInterval: TimeInterval = 2
  var backgroundColor: ThemeColor = .blue
  var showIcon: Bool = true
}

struct MicWidgetSettings: Codable, Equatable {
  var refreshInterval: TimeInterval = 2
  var backgroundColor: ThemeColor = .orange
  var showIcon: Bool = true
}

struct KeyboardWidgetSettings: Codable, Equatable {
  var refreshInterval: TimeInterval = 5
  var backgroundColor: ThemeColor = .mainAlt
  var showIcon: Bool = true
}

struct GitHubWidgetSettings: Codable, Equatable {
  var refreshInterval: TimeInterval = 600  // 10 minutes
  var hideWhenNoNotifications: Bool = false
  var notificationUrl: String = "https://github.com/notifications"
  var ghBinaryPath: String = "/opt/homebrew/bin/gh"
  var showIcon: Bool = true
}

struct CPUWidgetSettings: Codable, Equatable {
  var refreshInterval: TimeInterval = 2
  var monitorApp: MonitorApp = .activityMonitor
  var graphColor: ThemeColor = .yellow
  var showIcon: Bool = true

  enum MonitorApp: String, Codable, CaseIterable {
    case none = "None"
    case activityMonitor = "Activity Monitor"
    case top = "Top"
  }
}

struct MemoryWidgetSettings: Codable, Equatable {
  var refreshInterval: TimeInterval = 4
  var monitorApp: CPUWidgetSettings.MonitorApp = .activityMonitor
}

struct GPUWidgetSettings: Codable, Equatable {
  var refreshInterval: TimeInterval = 4
  var graphColor: ThemeColor = .cyan
  var showIcon: Bool = true
}

struct NetstatsWidgetSettings: Codable, Equatable {
  var refreshInterval: TimeInterval = 4
  var downloadColor: ThemeColor = .magenta
  var uploadColor: ThemeColor = .blue
  var showIcon: Bool = true
}

struct DiskActivityWidgetSettings: Codable, Equatable {
  var refreshInterval: TimeInterval = 4
  var readColor: ThemeColor = .blue
  var writeColor: ThemeColor = .red
  var showIcon: Bool = true
}

struct StorageWidgetSettings: Codable, Equatable {
  var refreshInterval: TimeInterval = 60  // 1 minute
}

/// Manages the multi-display layout configuration
class LayoutManager: ObservableObject {
  static let shared = LayoutManager()

  @Published var multiDisplayLayout: MultiDisplayLayout

  private var cancellables = Set<AnyCancellable>()

  private init() {
    // Initialize with active profile's layout
    self.multiDisplayLayout = ProfileManager.shared.activeProfile?.multiDisplayLayout ?? .defaultLayout

    // Sync with active profile changes
    NotificationCenter.default.publisher(for: .profileDidChange)
      .compactMap { $0.object as? LayoutProfile }
      .sink { [weak self] profile in
        self?.multiDisplayLayout = profile.multiDisplayLayout
      }
      .store(in: &cancellables)
  }

  /// Get bar layout for a specific display and position
  func barLayout(forDisplay index: Int, position: BarPosition) -> SingleBarLayout? {
    multiDisplayLayout.barLayout(forDisplay: index, position: position)
  }

  /// Check if a display has any bars configured
  func hasBar(forDisplay index: Int) -> Bool {
    multiDisplayLayout.configuration(forDisplay: index)?.hasBars ?? false
  }

  /// Check if a specific bar exists for a display
  func hasBar(forDisplay index: Int, position: BarPosition) -> Bool {
    barLayout(forDisplay: index, position: position) != nil
  }

  /// Update the entire multi-display layout
  func updateLayout(_ layout: MultiDisplayLayout) {
    multiDisplayLayout = layout
  }

  /// Update configuration for a specific display
  func updateDisplayConfiguration(_ config: DisplayConfiguration) {
    multiDisplayLayout.setConfiguration(config, forDisplay: config.displayIndex)
  }

  /// Remove configuration for a display
  func removeDisplayConfiguration(forDisplay index: Int) {
    multiDisplayLayout.removeConfiguration(forDisplay: index)
  }

  /// Reset to default layout
  func resetToDefault() {
    multiDisplayLayout = .defaultLayout
  }
}
