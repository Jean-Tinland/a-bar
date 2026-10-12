import AppKit
import Combine
import SwiftUI

/// Main application delegate handling bar windows, services, and menu bar setup
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {

  /// Bar windows keyed by display index and position
  private var barWindows: [BarWindowKey: BarWindow] = [:]
  private var appliedWindowConfiguration: BarWindowPlan.Configuration?
  private var appliedServiceConfiguration: BarWindowPlan.ServiceConfiguration?

  /// Status bar item for menu bar icon
  private var statusItem: NSStatusItem?

  /// Settings window controller
  private var settingsWindowController: NSWindowController?

  /// Last value applied to the login item, so unrelated settings changes cannot thrash
  /// SMAppService - or unregister what the user just enabled.
  private var appliedLaunchAtLogin: Bool?

  /// The window manager whose service is running, for the same reason.
  private var runningWindowManager: WindowManager?
  private var runningWindowManagerPath: String?

  /// Settings manager
  let settingsManager = SettingsManager.shared

  /// Yabai service for window management
  let yabaiService = YabaiService.shared

  /// AeroSpace service for window management
  let aerospaceService = AerospaceService.shared

  /// System info service for system metrics
  let systemInfoService = SystemInfoService.shared
  let bluetoothService = BluetoothService.shared
  let wifiService = WifiService.shared
  let networkModels = NetworkWidgetModels()

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

    // Bring up the profile list before anything reads it
    ProfileManager.bootstrap()

    // Adopt whatever macOS says about the login item before watching for changes
    reconcileLaunchAtLogin()
    
    // Setup menu bar status item
    setupStatusItem()

    // Create bar windows for all screens
    setupBarWindows()

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
    // Writes are debounced, so make sure the last change reaches disk
    settingsManager.flush()

    barWindows.values.forEach { $0.close() }
    yabaiService.stop()
    aerospaceService.stop()
    networkModels.stop()
    systemInfoService.stop()
    bluetoothService.stop()
    wifiService.stop()
    runningWindowManager = nil
    runningWindowManagerPath = nil
  }

  private func setupStatusItem() {
    // Create status item with variable length to accommodate icon
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    // Set menu bar icon
    if let button = statusItem?.button {
      let image = NSImage(named: "MenuBarIcon")
      image?.isTemplate = true
      image?.size = NSSize(width: 28, height: 22)
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
  private func setupBarWindows(force: Bool = false) {
    // Sampling settings must still update when the existing windows can be reused.
    defer { updateServices() }
    let screens = NSScreen.screens
    let configuration = BarWindowPlan.Configuration(
      screenCount: screens.count,
      layout: layoutManager.multiDisplayLayout,
      global: settingsManager.settings.global)
    guard force || configuration != appliedWindowConfiguration else { return }
    appliedWindowConfiguration = configuration

    WidgetPopoverManager.closeAll()
    // Remove existing windows
    barWindows.values.forEach { $0.close() }
    barWindows.removeAll()

    let plan = BarWindowPlan.windows(
      screenCount: screens.count,
      layout: layoutManager.multiDisplayLayout,
      barEnabled: settingsManager.settings.global.barEnabled
    )

    // The plan only names displays that are attached, so the index is safe to subscript with.
    for key in plan {
      let barWindow = BarWindow(
        screen: screens[key.displayIndex],
        displayIndex: key.displayIndex,
        position: key.position,
        networkModels: networkModels
      )
      barWindows[key] = barWindow
      barWindow.makeKeyAndOrderFront(nil)
    }
  }
  
  // Observe screen changes to recreate bar windows when displays are added/removed or arrangement changes
  private func setupScreenObserver() {
    screenObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.setupBarWindows(force: true)
      }
    }
  }

  /// The only place that maps a `WindowManager` onto the service that implements it.
  private func setWindowManager(_ windowManager: WindowManager, running: Bool) {
    switch windowManager {
    case .yabai:
      running ? yabaiService.start() : yabaiService.stop()
    case .aerospace:
      running ? aerospaceService.start() : aerospaceService.stop()
    }
  }

  private var visibleWidgets: Set<WidgetIdentifier> {
    BarWindowPlan.visibleWidgets(
      screenCount: NSScreen.screens.count,
      layout: layoutManager.multiDisplayLayout,
      barEnabled: settingsManager.settings.global.barEnabled
    )
  }

  /// Hidden widgets must not poll or initialize blocking hardware APIs.
  private func updateServices() {
    let widgets = visibleWidgets
    applyWindowManager(WindowManagerServices.requiredService(
      for: settingsManager.settings.global.windowManager, widgets: widgets))
    let settings = settingsManager.settings.widgets
    // All bars share one request and timer per network source. A window rebuild must not stop them.
    poll(networkModels.github, when: widgets.contains(.github),
         input: settings.github.ghBinaryPath, every: settings.github.refreshInterval)
    poll(networkModels.weather, when: widgets.contains(.weather),
         input: settings.weather.customLocation, every: settings.weather.refreshInterval)
    poll(networkModels.hackerNews, when: widgets.contains(.hackerNews),
         input: "", every: settings.hackerNews.refreshInterval)
    let configuration = BarWindowPlan.ServiceConfiguration(
      widgets: widgets, settings: settings)
    let previous = appliedServiceConfiguration

    if previous?.systemWidgets != configuration.systemWidgets
      || previous?.systemIntervals != configuration.systemIntervals {
      systemInfoService.start(widgets: configuration.systemWidgets)
    }
    if previous?.bluetooth != configuration.bluetooth {
      if let bluetooth = configuration.bluetooth {
        bluetoothService.start()
        if bluetooth.showBatteryInBar { bluetoothService.refreshBatteryLevels() }
      } else {
        bluetoothService.stop()
      }
    }
    if previous?.wifi != configuration.wifi {
      if let wifi = configuration.wifi {
        // Changing the interface invalidates its in-flight scan; timer-only changes keep event monitoring.
        if let old = previous?.wifi, old.networkDevice != wifi.networkDevice {
          wifiService.stop()
        }
        wifiService.start()
      } else {
        wifiService.stop()
      }
    }
    appliedServiceConfiguration = configuration
  }

  private func poll<Value>(
    _ model: PollingModel<Value>, when visible: Bool, input: String, every interval: TimeInterval
  ) {
    if visible { model.start(input: input, refreshInterval: interval) } else { model.stop() }
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
      .removeDuplicates()
      .dropFirst()
      .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.setupBarWindows()
      }
      .store(in: &cancellables)
  }

  // Handle changes in settings to update bar windows and launch at login status
  private func handleSettingsChange(_ settings: ABarSettings) {
    // A save can move anchors or change content size. Close popovers while retaining bar state.
    WidgetPopoverManager.closeAll()
    setupBarWindows()

    // Update launch at login
    applyLaunchAtLogin(settings.global.launchAtLogin)
  }

  /// Restart only when the selected service or its executable changed.
  private func applyWindowManager(_ windowManager: WindowManager?) {
    let global = settingsManager.settings.global
    let path = windowManager.map { $0 == .yabai ? global.yabaiPath : global.aerospacePath }
    guard
      let transition = WindowManagerServices.transition(
        to: windowManager, from: runningWindowManager,
        executablePath: path, runningExecutablePath: runningWindowManagerPath)
    else { return }

    if let stop = transition.stop { setWindowManager(stop, running: false) }
    if let start = transition.start { setWindowManager(start, running: true) }
    runningWindowManager = transition.start
    runningWindowManagerPath = path
  }

  /// macOS owns the login item: the user can remove it in System Settings without the app
  /// hearing about it, so adopt what it reports instead of forcing the stored value back on.
  private func reconcileLaunchAtLogin() {
    let adoption = LaunchAtLoginReconciler.adopt(
      registered: LaunchAtLogin.isEnabled,
      stored: settingsManager.settings.global.launchAtLogin
    )
    appliedLaunchAtLogin = adoption.lastApplied

    if let setting = adoption.settingToWrite {
      settingsManager.update { $0.global.launchAtLogin = setting }
    }
  }

  /// Apply the setting only when it actually changed. Reacting to every settings change is
  /// what used to unregister the login item the moment any other setting was saved.
  private func applyLaunchAtLogin(_ enabled: Bool) {
    let outcome = LaunchAtLoginReconciler.apply(
      enabled,
      lastApplied: appliedLaunchAtLogin,
      setEnabled: LaunchAtLogin.setEnabled
    )

    if case .failed(_, let message) = outcome {
      print("⚠️ a-bar: failed to update launch at login: \(message)")
    }
    appliedLaunchAtLogin = outcome.lastApplied
  }

  // Open the preferences window, creating it if it doesn't exist
  @objc private func openPreferences() {
    // Pick up anything changed since the window was last open (menu bar toggle, AppleScript,
    // a profile switch) without discarding edits already in progress.
    settingsManager.rebaseDraftIfClean()

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
    switch runningWindowManager {
    case .yabai:
      yabaiService.refresh()
    case .aerospace:
      aerospaceService.refresh()
    case nil:
      break
    }
    systemInfoService.refresh()
    let widgets = visibleWidgets
    if widgets.contains(.bluetooth) { bluetoothService.refresh() }
    if widgets.contains(.wifi) { wifiService.refresh() }
    barWindows.values.forEach { $0.refresh() }
  }

  // Toggle bar visibility and update menu item state accordingly
  @objc private func toggleBarVisibility() {
    settingsManager.update { $0.global.barEnabled.toggle() }

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
