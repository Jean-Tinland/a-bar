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
    }
  }
}

/// Manages application settings with persistence
///
/// There is exactly one writer of the config file: every change goes through `update`
/// (immediate, for things toggled outside the Preferences window) or `saveSettings`
/// (explicit, for the Preferences draft). `SettingsStore` owns the file, `SettingsCodec`
/// owns decoding and normalization.
class SettingsManager: ObservableObject {
  static let shared = SettingsManager()

  /// The settings the app is running on.
  @Published private(set) var settings: ABarSettings

  /// The copy the Preferences window edits; only `saveSettings()` promotes it.
  @Published var draftSettings: ABarSettings
  var hasUnsavedChanges: Bool { layoutModified || draftSettings != settings }
  @Published private(set) var saveState: SettingsStore.SaveState = .idle

  var canSave: Bool {
    if case .failed = saveState { return true }
    return hasUnsavedChanges || isDegraded
  }

  /// The profile currently being edited in the Layout settings
  /// This is NOT the same as the active profile - it's just what's being edited
  @Published var editingProfileId: UUID? = nil

  /// Draft layout being edited (separate from profiles)
  @Published var draftLayout: MultiDisplayLayout

  /// What the last load had to say for itself: recovered values, a fallback source, or
  /// degraded mode. Nil when the config file loaded cleanly.
  @Published private(set) var loadSummary: String?

  private let store: SettingsStore

  /// The layout the editor started from. `draftLayout` differing from it is what "the layout
  /// was modified" means - deriving it beats a flag raced against a debounced publisher.
  private var layoutBaseline: MultiDisplayLayout

  private var cancellables = Set<AnyCancellable>()

  private var layoutModified: Bool { draftLayout != layoutBaseline }

  /// True when the config file could not be read, in which case the app will not overwrite
  /// it until the user explicitly saves.
  var isDegraded: Bool { store.isDegraded }

  /// Layout of the profile the bar is currently using.
  var activeLayout: MultiDisplayLayout { SettingsManager.activeLayout(in: settings) }

  private convenience init() {
    self.init(store: SettingsStore())
  }

  init(store: SettingsStore) {
    self.store = store

    let result = store.load()
    let layout = SettingsManager.activeLayout(in: result.settings)

    self.settings = result.settings
    self.draftSettings = result.settings
    self.draftLayout = layout
    self.layoutBaseline = layout
    self.loadSummary = result.summary
    self.saveState = store.saveState
    store.onSaveStateChange = { [weak self] state in self?.saveState = state }

    if let summary = result.summary {
      print("ℹ️ a-bar settings: \(summary)")
    }

    // Theme colors also depend on the system appearance. Refresh every settings
    // consumer (including popovers and draft previews) without changing or saving settings.
    NSApplication.shared.publisher(for: \.effectiveAppearance, options: [.new])
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.objectWillChange.send() }
      .store(in: &cancellables)
  }

  /// The layout of the active profile, resolved without touching `ProfileManager` so that
  /// initialization cannot recurse back into this type.
  private static func activeLayout(in settings: ABarSettings) -> MultiDisplayLayout {
    let activeId = settings.activeProfileId.flatMap(UUID.init(uuidString:))
    let profile = settings.profiles.first { $0.id == activeId } ?? settings.profiles.first
    return profile?.multiDisplayLayout ?? .defaultLayout
  }

  /// Apply a change to the running settings, persist it, and mirror it into the draft so
  /// that saving from Preferences afterwards cannot silently revert it.
  ///
  /// This is the only way to change `settings`: the menu bar, the AppleScript commands and
  /// `ProfileManager` all come through here.
  ///
  /// The change is applied to both copies, which may hold different lists while Preferences
  /// is open, so express it in terms that are safe against that: address collection elements
  /// by id rather than by index.
  func update(_ mutate: (inout ABarSettings) -> Void) {
    var updatedDraft = draftSettings
    mutate(&updatedDraft)
    SettingsCodec.normalize(&updatedDraft)
    if updatedDraft != draftSettings {
      draftSettings = updatedDraft
    }

    var updated = settings
    mutate(&updated)
    SettingsCodec.normalize(&updated)
    guard updated != settings else { return }

    settings = updated
    store.save(updated)
  }

  /// Write any pending change to disk immediately. Called on termination.
  func flush() {
    store.flush()
  }

  func saveSettings() {
    // Only save the layout if it was actually modified during this session, and only to the
    // profile being edited - never to whichever profile happens to be active.
    if layoutModified, let editingProfileId = editingProfileId {
      ProfileManager.shared.updateProfileLayout(id: editingProfileId, layout: draftLayout)
    }
    layoutBaseline = draftLayout

    // Profiles are owned by ProfileManager and already persisted through `update`.
    draftSettings.profiles = settings.profiles
    draftSettings.activeProfileId = settings.activeProfileId

    var updated = draftSettings
    SettingsCodec.normalize(&updated)
    draftSettings = updated
    settings = updated

    // An explicit save also clears degraded mode: the user has seen what the app is running
    // on and chose to keep it.
    store.saveExplicitly(updated)
  }

  func discardChanges() {
    draftSettings = settings
    loadLayoutForEditing(activeLayout)
  }

  /// Bring the draft back in line with the running settings, used when the Preferences
  /// window opens so that changes made elsewhere show up. Keeps edits in progress.
  func rebaseDraftIfClean() {
    guard !hasUnsavedChanges else { return }
    discardChanges()
  }

  /// Load a layout for editing without marking it as modified
  func loadLayoutForEditing(_ layout: MultiDisplayLayout) {
    layoutBaseline = layout
    draftLayout = layout
  }
}

/// Root settings object
///
/// Every property carries its default here, and this is the only place a default is
/// written: `SettingsCodec` fills whatever a config file is missing from an encoded
/// `ABarSettings()`, so there is no hand-written decoder to drift away from these values.
struct ABarSettings: Codable, Equatable {
  var schemaVersion: Int = SettingsCodec.currentSchemaVersion
  var global: GlobalSettings = GlobalSettings()
  var theme: ThemeSettings = ThemeSettings()
  var widgets: WidgetSettings = WidgetSettings()
  var userWidgets: [UserWidgetDefinition] = []
  var profiles: [LayoutProfile] = []
  var activeProfileId: String? = nil
}

/// Global application settings
struct GlobalSettings: Codable, Equatable {
  var barEnabled: Bool = true
  var launchAtLogin: Bool = false
  var barHeight: CGFloat = 34
  var fontSize: CGFloat = 11
  var fontName: String = ""
  var barHorizontalPadding: CGFloat = 8
  var barVerticalPadding: CGFloat = 4
  var barDistanceFromEdges: CGFloat = 0
  var barCornerRadius: CGFloat = 6
  var barOpacity: CGFloat = 90
  var barElementsCornerRadius: CGFloat = 4
  var barElementsBackgroundOpacity: CGFloat = 100
  var showBorder: Bool = true
  var showElementsBorder: Bool = true
  var noColorInDataWidgets: Bool = false
  var barBackgroundBlur: Bool = false

  // Window manager configuration
  var windowManager: WindowManager = .yabai

  // Yabai configuration
  var yabaiPath: String = "/opt/homebrew/bin/yabai"

  // AeroSpace configuration
  var aerospacePath: String = "/opt/homebrew/bin/aerospace"

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
  var bluetooth: BluetoothWidgetSettings = BluetoothWidgetSettings()
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
  var layoutModeUsesIcon: Bool = false
  var spaceLayoutDisplay: SpaceLayoutDisplay = .text

  enum SpaceLayoutDisplay: String, Codable, CaseIterable {
    case off
    case text
    case icon
  }
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
  /// Safety net only: CoreWLAN events carry state changes, so this can stay slow.
  var refreshInterval: TimeInterval = 20
  /// Minimum delay between active scans. macOS rate-limits them and returns stale
  /// results for scans made too close together.
  var scanInterval: TimeInterval = 15
  var hideWhenDisabled: Bool = false
  /// Empty means auto-detect the first Wi-Fi interface macOS reports.
  var networkDevice: String = ""
  var hideNetworkName: Bool = false
  var showSignalStrength: Bool = true
  var maxNetworkNameLength: Int = 15
  var backgroundColor: ThemeColor = .red
  var showIcon: Bool = true
}

struct BluetoothWidgetSettings: Codable, Equatable {
  var refreshInterval: TimeInterval = 5
  /// Battery levels come from `system_profiler`, which forks a process, so it
  /// is polled far less often than the in-process IOBluetooth state.
  var batteryRefreshInterval: TimeInterval = 60
  var hideWhenDisabled: Bool = false
  var showConnectedDeviceName: Bool = true
  var showConnectedCount: Bool = false
  /// Show the connected device battery in the bar. Off by default: it makes the
  /// bar poll `system_profiler` even when the popover is closed.
  var showBatteryInBar: Bool = false
  var maxDeviceNameLength: Int = 15
  var backgroundColor: ThemeColor = .accent
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

struct HackerNewsWidgetSettings: Codable, Equatable {
  var refreshInterval: TimeInterval = 600  // 10 minutes
  var rotationInterval: TimeInterval = 20  // Rotate story every 20 seconds
  var maxTitleLength: Int = 50
  var showIcon: Bool = true
  var showPoints: Bool = true
}

/// Manages the multi-display layout configuration
class LayoutManager: ObservableObject {
  static let shared = LayoutManager()

  @Published var multiDisplayLayout: MultiDisplayLayout

  private var cancellables = Set<AnyCancellable>()

  init(
    initialLayout: MultiDisplayLayout,
    notificationCenter: NotificationCenter = .default
  ) {
    self.multiDisplayLayout = initialLayout

    // Sync with active profile changes
    notificationCenter.publisher(for: .profileDidChange)
      .compactMap { $0.object as? LayoutProfile }
      .sink { [weak self] profile in
        self?.multiDisplayLayout = profile.multiDisplayLayout
      }
      .store(in: &cancellables)
  }

  /// The shared instance starts on whichever profile is active at launch. Kept private so the
  /// read of `ProfileManager.shared` stays on this one path - see the note on `ProfileManager`'s
  /// own initializer about not letting the two singletons build each other.
  private convenience init() {
    self.init(initialLayout: ProfileManager.shared.activeProfile?.multiDisplayLayout ?? .defaultLayout)
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
}

