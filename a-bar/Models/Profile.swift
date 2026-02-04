import Combine
import Foundation

/// Represents a single layout profile
struct LayoutProfile: Codable, Identifiable, Equatable {
  let id: UUID
  var name: String
  var multiDisplayLayout: MultiDisplayLayout
  var isDefault: Bool

  init(
    id: UUID = UUID(),
    name: String,
    multiDisplayLayout: MultiDisplayLayout,
    isDefault: Bool = false
  ) {
    self.id = id
    self.name = name
    self.multiDisplayLayout = multiDisplayLayout
    self.isDefault = isDefault
  }

  /// Default profile with default layout
  static var defaultProfile: LayoutProfile {
    LayoutProfile(
      name: "Default",
      multiDisplayLayout: .defaultLayout,
      isDefault: true
    )
  }
}

/// Manages layout profiles
///
/// Architecture:
/// - `activeProfileId`: The globally active profile that the bar displays
/// - Profiles are stored in the main settings file (.a-barrc)
/// - Settings view can edit any profile without affecting the active one
/// - Changes are only applied when explicitly saved
class ProfileManager: ObservableObject {
  static let shared = ProfileManager()

  /// All available profiles
  @Published var profiles: [LayoutProfile] = []

  /// Currently active profile ID (the one the bar is using)
  @Published var activeProfileId: UUID

  /// Currently active profile
  var activeProfile: LayoutProfile? {
    profiles.first { $0.id == activeProfileId }
  }

  private let profilesKey = "abar-profiles"
  private let activeProfileKey = "abar-active-profile"
  private let userDefaults = UserDefaults.standard

  private init() {
    // Load profiles from settings
    let settings = SettingsManager.shared.settings
    var loadedProfiles: [LayoutProfile]

    if !settings.profiles.isEmpty {
      loadedProfiles = settings.profiles
    } else if let data = userDefaults.data(forKey: profilesKey),
      let decoded = try? JSONDecoder().decode([LayoutProfile].self, from: data),
      !decoded.isEmpty
    {
      loadedProfiles = decoded
    } else {
      // Initialize with default profile
      let defaultProfile = LayoutProfile(
        name: "Default",
        multiDisplayLayout: .defaultLayout,
        isDefault: true
      )
      loadedProfiles = [defaultProfile]
    }

    // Ensure there's always a default profile
    if !loadedProfiles.contains(where: { $0.isDefault }) {
      let defaultProfile = LayoutProfile(
        name: "Default",
        multiDisplayLayout: loadedProfiles.first?.multiDisplayLayout ?? .defaultLayout,
        isDefault: true
      )
      loadedProfiles.insert(defaultProfile, at: 0)
    }

    self.profiles = loadedProfiles

    // Load active profile ID
    if let activeIdString = settings.activeProfileId,
      let activeId = UUID(uuidString: activeIdString),
      loadedProfiles.contains(where: { $0.id == activeId })
    {
      self.activeProfileId = activeId
    } else if let activeIdString = userDefaults.string(forKey: activeProfileKey),
      let activeId = UUID(uuidString: activeIdString),
      loadedProfiles.contains(where: { $0.id == activeId })
    {
      self.activeProfileId = activeId
    } else {
      self.activeProfileId = loadedProfiles.first?.id ?? UUID()
    }
  }

  // MARK: - Profile Switching (Menu Bar)

  /// Switch to a profile by ID - applies immediately to the bar
  func switchToProfile(id: UUID) -> Bool {
    guard let profile = profiles.first(where: { $0.id == id }) else {
      return false
    }

    guard id != activeProfileId else { return true }  // Already active

    activeProfileId = id

    // Apply to the running bar
    applyProfileToBar(profile)

    // Persist the active profile selection
    persistState()

    // Notify listeners
    NotificationCenter.default.post(name: .profileDidChange, object: profile)

    return true
  }

  /// Switch to a profile by name
  func switchToProfile(named name: String) -> Bool {
    guard let profile = profiles.first(where: { $0.name.lowercased() == name.lowercased() }) else {
      return false
    }
    return switchToProfile(id: profile.id)
  }

  /// Apply a profile's layout to the bar
  private func applyProfileToBar(_ profile: LayoutProfile) {
    // Update the layout manager to refresh the bar
    LayoutManager.shared.updateLayout(profile.multiDisplayLayout)
  }

  // MARK: - Profile CRUD Operations

  /// Create a new profile
  func createProfile(name: String, layout: MultiDisplayLayout? = nil) -> LayoutProfile {
    let newProfile = LayoutProfile(
      name: name,
      multiDisplayLayout: layout ?? .defaultLayout,
      isDefault: false
    )
    profiles.append(newProfile)
    persistState()
    return newProfile
  }

  /// Update a profile's layout
  func updateProfileLayout(id: UUID, layout: MultiDisplayLayout) {
    guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
    profiles[index].multiDisplayLayout = layout
    persistState()

    // If this is the active profile, also update the bar
    if id == activeProfileId {
      applyProfileToBar(profiles[index])
    }
  }

  /// Rename a profile
  func renameProfile(id: UUID, newName: String) -> Bool {
    guard let index = profiles.firstIndex(where: { $0.id == id }) else { return false }
    profiles[index].name = newName
    persistState()
    return true
  }

  /// Delete a profile (cannot delete default)
  func deleteProfile(id: UUID) -> Bool {
    guard let profile = profiles.first(where: { $0.id == id }),
      !profile.isDefault
    else { return false }

    profiles.removeAll { $0.id == id }

    // If deleted the active profile, switch to default
    if activeProfileId == id {
      if let defaultProfile = profiles.first(where: { $0.isDefault }) {
        _ = switchToProfile(id: defaultProfile.id)
      } else if let first = profiles.first {
        _ = switchToProfile(id: first.id)
      }
    }

    persistState()
    return true
  }

  /// Duplicate a profile
  func duplicateProfile(id: UUID, newName: String? = nil) -> LayoutProfile? {
    guard let original = profiles.first(where: { $0.id == id }) else { return nil }

    let name = newName ?? "\(original.name) Copy"
    return createProfile(name: name, layout: original.multiDisplayLayout)
  }

  /// Get a profile by ID
  func profile(withId id: UUID) -> LayoutProfile? {
    profiles.first { $0.id == id }
  }

  // MARK: - Persistence

  /// Persist profiles and active profile ID to settings file
  private func persistState() {
    SettingsManager.shared.settings.profiles = profiles
    SettingsManager.shared.settings.activeProfileId = activeProfileId.uuidString
    SettingsManager.shared.saveSettingsNow(SettingsManager.shared.settings)

    // Backup to UserDefaults
    if let encoded = try? JSONEncoder().encode(profiles) {
      userDefaults.set(encoded, forKey: profilesKey)
    }
    userDefaults.set(activeProfileId.uuidString, forKey: activeProfileKey)
  }

  /// Get list of profile names
  var profileNames: [String] {
    profiles.map { $0.name }
  }
}

// MARK: - Notifications

extension Notification.Name {
  static let profileDidChange = Notification.Name("profileDidChange")
}
