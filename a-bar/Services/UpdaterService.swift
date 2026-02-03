import Foundation
import Sparkle

/// Manages application updates using Sparkle framework
final class UpdaterService: NSObject, ObservableObject {
  static let shared = UpdaterService()

  /// The Sparkle updater controller
  private var updaterController: SPUStandardUpdaterController!

  /// Published state for UI binding
  @Published var canCheckForUpdates: Bool = false
  @Published var isCheckingForUpdates: Bool = false
  @Published var lastUpdateCheckDate: Date?
  @Published var automaticallyChecksForUpdates: Bool = false {
    didSet {
      updaterController?.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
    }
  }

  private override init() {
    super.init()

    // Initialize Sparkle updater controller
    updaterController = SPUStandardUpdaterController(
      startingUpdater: true,
      updaterDelegate: self,
      userDriverDelegate: nil
    )

    // Bind to updater state
    setupBindings()
  }

  private func setupBindings() {
    // Observe canCheckForUpdates
    updaterController.updater.publisher(for: \.canCheckForUpdates)
      .assign(to: &$canCheckForUpdates)

    // Observe lastUpdateCheckDate
    updaterController.updater.publisher(for: \.lastUpdateCheckDate)
      .assign(to: &$lastUpdateCheckDate)

    // Observe automaticallyChecksForUpdates
    automaticallyChecksForUpdates = updaterController.updater.automaticallyChecksForUpdates
  }

  /// Manually check for updates
  func checkForUpdates() {
    guard canCheckForUpdates else { return }
    isCheckingForUpdates = true
    updaterController.checkForUpdates(nil)
  }

  /// Check for updates in background (no UI if no update)
  func checkForUpdatesInBackground() {
    updaterController.updater.checkForUpdatesInBackground()
  }

  /// Get the current app version
  var currentVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
  }

  /// Get the current build number
  var buildNumber: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
  }

  /// Format the last check date
  var lastCheckDateString: String? {
    guard let date = lastUpdateCheckDate else { return nil }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: date, relativeTo: Date())
  }
}

// MARK: - SPUUpdaterDelegate
extension UpdaterService: SPUUpdaterDelegate {

  func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
    DispatchQueue.main.async {
      self.isCheckingForUpdates = false
    }
  }

  func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
    DispatchQueue.main.async {
      self.isCheckingForUpdates = false
    }
  }

  func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
    DispatchQueue.main.async {
      self.isCheckingForUpdates = false
    }
  }

  func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
    DispatchQueue.main.async {
      self.isCheckingForUpdates = false
    }
    print("Update check aborted with error: \(error.localizedDescription)")
  }

  // Allow Sparkle to check version even for same versions (useful for debugging)
  func allowedChannels(for updater: SPUUpdater) -> Set<String> {
    return Set(["stable"])
  }
}
