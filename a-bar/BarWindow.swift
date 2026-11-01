import AppKit
import SwiftUI

/// Custom window that displays the bar on a screen
class BarWindow: NSPanel {
  let barScreen: NSScreen
  private let displayIndex: Int
  let barPosition: BarPosition
  private let networkModels: NetworkWidgetModels
  private var hostingView: NSHostingView<AnyView>?

  init(screen: NSScreen, displayIndex: Int, position: BarPosition,
       networkModels: NetworkWidgetModels) {
    self.barScreen = screen
    self.displayIndex = displayIndex
    self.barPosition = position
    self.networkModels = networkModels

    // Calculate frame for the bar
    let settings = SettingsManager.shared.settings.global
    let barHeight = settings.barHeight
    let distanceFromEdges = settings.barDistanceFromEdges
    let screenFrame = screen.frame

    let barFrame = BarGeometry.barFrame(
      screenFrame: screenFrame,
      height: barHeight,
      inset: distanceFromEdges,
      position: position)

    //
    super.init(
      contentRect: barFrame,
      styleMask: [.borderless, .nonactivatingPanel, .hudWindow],
      backing: .buffered,
      defer: false
    )

    setupWindow()
    setupContent()
  }

  private func setupWindow() {
    self.level = NSWindow.Level(BarWindowLevel.base)
    self.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .fullScreenNone, .stationary]
    self.isOpaque = false
    self.backgroundColor = .clear
    self.hasShadow = false
    self.isMovableByWindowBackground = false
    self.acceptsMouseMovedEvents = true
    self.hidesOnDeactivate = false
    self.becomesKeyOnlyIfNeeded = true
  }

  private func setupContent() {
    let barView = BarView(
      displayIndex: displayIndex,
      screen: barScreen,
      position: barPosition,
      networkModels: networkModels
    )
    .environmentObject(SettingsManager.shared)
    .environmentObject(YabaiService.shared)
    .environmentObject(AerospaceService.shared)
    .environmentObject(SystemInfoService.shared)
    .environmentObject(BluetoothService.shared)
    .environmentObject(WifiService.shared)
    .environmentObject(LayoutManager.shared)

    hostingView = NSHostingView(rootView: AnyView(barView))
    hostingView?.frame = contentView?.bounds ?? .zero
    hostingView?.autoresizingMask = [.width, .height]

    contentView = hostingView
  }

  // Refresh the content of the bar.  The SwiftUI views already observe
  // their @EnvironmentObject services and will re-render automatically
  // when data changes, so we no longer tear down and recreate the entire
  // NSHostingView hierarchy.  This avoids expensive view-tree rebuilds
  // that used to cause visible hitches and accumulated memory pressure.
  func refresh() {
    // Force a layout pass so the hosting view picks up any frame changes
    // (e.g., after a screen reconfiguration).
    hostingView?.needsLayout = true
  }

  /// Move the bar to another window-server layer without rebuilding it. Called on every menu bar
  /// reveal and hide, so an unchanged level is a no-op.
  func applyLevel(_ rawLevel: Int) {
    guard level.rawValue != rawLevel else { return }
    level = NSWindow.Level(rawLevel)
    orderFrontRegardless()
  }

  func refreshWidget(_ identifier: WidgetIdentifier) {
    // The widgets will auto-refresh through their observed state
    // This method can be extended to force specific widget refreshes
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}
