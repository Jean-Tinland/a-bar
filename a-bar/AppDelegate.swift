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

  func applicationWillTerminate(_ notification: Notification) {
    barWindows.values.forEach { $0.close() }
  }

  private func setupStatusItem() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    if let button = statusItem?.button {
      let image = NSImage(named: "MenuBarIcon")
      image?.isTemplate = true
      image?.size = NSSize(width: 14, height: 14)
      button.image = image
    }

    let menu = NSMenu()
    menu.addItem(
      NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ","))
    menu.addItem(NSMenuItem.separator())
    menu.addItem(NSMenuItem(title: "Refresh", action: #selector(refreshAll), keyEquivalent: "r"))
    menu.addItem(NSMenuItem.separator())

    let toggleItem = NSMenuItem(
      title: "Show Bar", action: #selector(toggleBarVisibility), keyEquivalent: "")
    toggleItem.state = settingsManager.settings.global.barEnabled ? .on : .off
    menu.addItem(toggleItem)

    menu.addItem(NSMenuItem.separator())
    menu.addItem(NSMenuItem(title: "Quit a-bar", action: #selector(quitApp), keyEquivalent: "q"))

    statusItem?.menu = menu
  }

  private func setupBarWindows() {
    // Remove existing windows
    barWindows.values.forEach { $0.close() }
    barWindows.removeAll()

    guard settingsManager.settings.global.barEnabled else { return }

    let screens = NSScreen.screens
    let layout = layoutManager.multiDisplayLayout

    // Create bar windows based on layout configuration
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
    // Start Yabai service
    yabaiService.start()

    // Start system info service
    systemInfoService.start()
  }

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

  private func handleSettingsChange(_ settings: ABarSettings) {
    // Update bar visibility
    if settings.global.barEnabled {
      // Recreate windows to apply any appearance changes
      setupBarWindows()
    } else {
      barWindows.values.forEach { $0.close() }
      barWindows.removeAll()
    }

    // Update launch at login
    updateLaunchAtLogin(settings.global.launchAtLogin)
  }

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

  @objc private func openPreferences() {
    if settingsWindowController == nil {
      let settingsView = SettingsView()
        .environmentObject(settingsManager)
        .environmentObject(yabaiService)
        .environmentObject(layoutManager)

      let hostingController = NSHostingController(rootView: settingsView)
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

  @objc private func refreshAll() {
    yabaiService.refresh()
    systemInfoService.refresh()
    barWindows.values.forEach { $0.refresh() }
  }

  @objc private func toggleBarVisibility() {
    settingsManager.settings.global.barEnabled.toggle()

    // Update menu item state
    if let menu = statusItem?.menu,
      let toggleItem = menu.items.first(where: { $0.action == #selector(toggleBarVisibility) })
    {
      toggleItem.state = settingsManager.settings.global.barEnabled ? .on : .off
    }
  }

  @objc private func quitApp() {
    NSApplication.shared.terminate(nil)
  }

  /// Refresh specific widget by identifier
  func refreshWidget(_ identifier: WidgetIdentifier) {
    barWindows.values.forEach { $0.refreshWidget(identifier) }
  }
}
