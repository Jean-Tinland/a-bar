import AppKit
import Combine
import ServiceManagement
import SwiftUI

/// Key for identifying a bar window by display index and position
struct BarWindowKey: Hashable {
  let displayIndex: Int
  let position: BarPosition
}

/// Main application delegate handling bar windows, services, and menu bar setup
class AppDelegate: NSObject, NSApplicationDelegate {

  /// Bar windows keyed by display index and position
  private var barWindows: [BarWindowKey: BarWindow] = [:]

  /// Status bar item for menu bar icon
  private var statusItem: NSStatusItem?

  /// Settings window controller
  private var settingsWindowController: NSWindowController?

  /// Settings manager
  let settingsManager = SettingsManager.shared

  /// Yabai service for window management
  let yabaiService = YabaiService.shared

  /// AeroSpace service for window management
  let aerospaceService = AerospaceService.shared

  /// System info service for system metrics
  let systemInfoService = SystemInfoService.shared

  /// Layout manager for widget arrangement
  let layoutManager = LayoutManager.shared

  /// User widget manager
  let userWidgetManager = UserWidgetManager.shared

  /// Cancellables for Combine subscriptions
  private var cancellables = Set<AnyCancellable>()

  /// Screen change observer
  private var screenObserver: Any?

  func applicationDidFinishLaunching(_ notification: Notification) {
    // Terminate any existing a-bar instances to prevent multiple processes
    terminateExistingInstances()
    
    // Setup menu bar status item
    setupStatusItem()

    // Create bar windows for all screens
    setupBarWindows()

    // Start services
    startServices()

    // Setup screen change observer
    setupScreenObserver()

    // Subscribe to settings changes
    subscribeToSettingsChanges()
  }
  
  /// Terminate any existing a-bar instances before launching this one.
  /// This prevents multiple a-bar processes from running simultaneously.
  private func terminateExistingInstances() {
    let currentPID = ProcessInfo.processInfo.processIdentifier
    let bundleID = Bundle.main.bundleIdentifier
    
    let existingInstances = NSWorkspace.shared.runningApplications.filter { app in
      app.bundleIdentifier == bundleID && 
      app.processIdentifier != currentPID
    }
    
    for app in existingInstances {
      app.terminate()
      
      // Wait up to 2 seconds for graceful termination
      let deadline = Date().addingTimeInterval(2.0)
      while !app.isTerminated && Date() < deadline {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
      }
      
      // Force terminate if still running
      if !app.isTerminated {
        app.forceTerminate()
      }
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    barWindows.values.forEach { $0.close() }
    yabaiService.stop()
    aerospaceService.stop()
  }

  private func setupStatusItem() {
    // Create status item with variable length to accommodate icon
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    // Set menu bar icon
    if let button = statusItem?.button {
      let image = NSImage(named: "MenuBarIcon")
      image?.isTemplate = true
      image?.size = NSSize(width: 14, height: 14)
      button.image = image
    }

    // Initial menu setup
    rebuildMenu()

    // Subscribe to profile changes to rebuild menu
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(profileDidChange),
      name: .profileDidChange,
      object: nil
    )
  }

  /// Rebuild the status item menu (called when profiles change)
  private func rebuildMenu() {
    let menu = NSMenu()

    // Add Preferences menu item
    menu.addItem(
      NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ","))

    menu.addItem(NSMenuItem.separator())

    // Add profile submenu before Refresh
    let profileMenu = NSMenu()
    let profileManager = ProfileManager.shared


    // Add profile items
    for profile in profileManager.profiles {
      // Create menu item for each profile
      let item = NSMenuItem(
        title: profile.name,
        action: #selector(selectProfile(_:)),
        keyEquivalent: ""
      )
      // Store profile ID in representedObject for later retrieval
      item.representedObject = profile.id
      // Set state to indicate active profile
      item.state = profile.id == profileManager.activeProfileId ? .on : .off
      profileMenu.addItem(item)
    }

    let profileMenuItem = NSMenuItem(title: "Profile", action: nil, keyEquivalent: "")
    // Attach the profile submenu to the main menu
    profileMenuItem.submenu = profileMenu
    menu.addItem(profileMenuItem)

    menu.addItem(NSMenuItem.separator())
    // Add Refresh menu item
    menu.addItem(NSMenuItem(title: "Refresh", action: #selector(refreshAll), keyEquivalent: "r"))
    menu.addItem(NSMenuItem.separator())

    let toggleItem = NSMenuItem(
      title: "Show Bar", action: #selector(toggleBarVisibility), keyEquivalent: "")
    toggleItem.state = settingsManager.settings.global.barEnabled ? .on : .off
    // Add toggle bar visibility menu item
    menu.addItem(toggleItem)

    menu.addItem(NSMenuItem.separator())
    // Add Quit menu item
    menu.addItem(NSMenuItem(title: "Quit a-bar", action: #selector(quitApp), keyEquivalent: "q"))

    statusItem?.menu = menu
  }

  // Handle profile selection from menu
  @objc private func selectProfile(_ sender: NSMenuItem) {
    // Retrieve profile ID from representedObject and switch profile
    guard let profileId = sender.representedObject as? UUID else { return }
    _ = ProfileManager.shared.switchToProfile(id: profileId)
    rebuildMenu()
  }

  // Handle profile changes to rebuild menu
  @objc private func profileDidChange(_ notification: Notification) {
    rebuildMenu()
  }

  // Create bar windows based on current screen configuration and layout settings
  private func setupBarWindows() {
    // Remove existing windows
    barWindows.values.forEach { $0.close() }
    barWindows.removeAll()

    guard settingsManager.settings.global.barEnabled else { return }

    let screens = NSScreen.screens
    let layout = layoutManager.multiDisplayLayout

    // Create bar windows on each screen based on layout configuration
    for (displayIndex, screen) in screens.enumerated() {
      guard let displayConfig = layout.configuration(forDisplay: displayIndex) else {
        continue  // No configuration for this display
      }

      // Create top bar if configured
      if displayConfig.topBar != nil {
        let key = BarWindowKey(displayIndex: displayIndex, position: .top)
        let barWindow = BarWindow(
          screen: screen,
          displayIndex: displayIndex,
          position: .top
        )
        barWindows[key] = barWindow
        barWindow.makeKeyAndOrderFront(nil)
      }

      // Create bottom bar if configured
      if displayConfig.bottomBar != nil {
        let key = BarWindowKey(displayIndex: displayIndex, position: .bottom)
        let barWindow = BarWindow(
          screen: screen,
          displayIndex: displayIndex,
          position: .bottom
        )
        barWindows[key] = barWindow
        barWindow.makeKeyAndOrderFront(nil)
      }
    }
  }
  
  // Observe screen changes to recreate bar windows when displays are added/removed or arrangement changes
  private func setupScreenObserver() {
    screenObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.setupBarWindows()
    }
  }

  private func startServices() {
    // Start the appropriate window manager service based on settings
    let windowManager = settingsManager.settings.global.windowManager
    switch windowManager {
    case .yabai:
      yabaiService.start()
    case .aerospace:
      aerospaceService.start()
    }

    // Start system info service
    systemInfoService.start()
  }

  // Subscribe to settings changes to update bar windows and launch at login status
  private func subscribeToSettingsChanges() {
    settingsManager.$settings
      .dropFirst()
      .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
      .sink { [weak self] settings in
        self?.handleSettingsChange(settings)
      }
      .store(in: &cancellables)

    // Subscribe to layout changes specifically to recreate windows
    layoutManager.$multiDisplayLayout
      .dropFirst()
      .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.setupBarWindows()
      }
      .store(in: &cancellables)
  }

  // Handle changes in settings to update bar windows and launch at login status
  private func handleSettingsChange(_ settings: ABarSettings) {
    // Update bar visibility
    if settings.global.barEnabled {
      // Recreate windows to apply any appearance changes
      setupBarWindows()
    } else {
      barWindows.values.forEach { $0.close() }
      barWindows.removeAll()
    }

    // Restart window manager services if the WM changed
    restartWindowManagerServices(settings.global.windowManager)

    // Update launch at login
    updateLaunchAtLogin(settings.global.launchAtLogin)
  }

  /// Restart window manager services based on the selected WM
  private func restartWindowManagerServices(_ windowManager: WindowManager) {
    switch windowManager {
    case .yabai:
      aerospaceService.stop()
      yabaiService.start()
    case .aerospace:
      yabaiService.stop()
      aerospaceService.start()
    }
  }

  // Update launch at login status using ServiceManagement framework (macOS 13+)
  private func updateLaunchAtLogin(_ enabled: Bool) {
    if #available(macOS 13.0, *) {
      do {
        if enabled {
          try SMAppService.mainApp.register()
        } else {
          try SMAppService.mainApp.unregister()
        }
      } catch {
        print("Failed to update launch at login: \(error)")
      }
    }
  }

  // Open the preferences window, creating it if it doesn't exist
  @objc private func openPreferences() {
    if settingsWindowController == nil {
      // Create the settings view and embed it in a hosting controller
      let settingsView = SettingsView()
        .environmentObject(settingsManager)
        .environmentObject(yabaiService)
        .environmentObject(aerospaceService)
        .environmentObject(layoutManager)

      // Create a new window for the settings and set its content to the hosting controller
      let hostingController = NSHostingController(rootView: settingsView)
      // Configure the window properties (title, size, style)
      let window = NSWindow(contentViewController: hostingController)
      window.title = "a-bar Preferences"
      window.setContentSize(NSSize(width: 700, height: 500))
      window.styleMask = [.titled, .closable, .resizable]
      window.center()

      settingsWindowController = NSWindowController(window: window)
    }

    settingsWindowController?.showWindow(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  // Refresh all bar windows and services (called from menu)
  @objc private func refreshAll() {
    let windowManager = settingsManager.settings.global.windowManager
    switch windowManager {
    case .yabai:
      yabaiService.refresh()
    case .aerospace:
      aerospaceService.refresh()
    }
    systemInfoService.refresh()
    barWindows.values.forEach { $0.refresh() }
  }

  // Toggle bar visibility and update menu item state accordingly
  @objc private func toggleBarVisibility() {
    settingsManager.settings.global.barEnabled.toggle()

    // Update menu item state
    if let menu = statusItem?.menu,
      let toggleItem = menu.items.first(where: { $0.action == #selector(toggleBarVisibility) })
    {
      toggleItem.state = settingsManager.settings.global.barEnabled ? .on : .off
    }
  }

  // Quit the application
  @objc private func quitApp() {
    NSApplication.shared.terminate(nil)
  }

  /// Refresh specific widget by identifier
  func refreshWidget(_ identifier: WidgetIdentifier) {
    barWindows.values.forEach { $0.refreshWidget(identifier) }
  }
}
