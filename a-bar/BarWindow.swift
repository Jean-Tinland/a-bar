import AppKit
import SwiftUI

/// Custom window that displays the bar on a screen
class BarWindow: NSPanel {
  private let barScreen: NSScreen
  private let displayIndex: Int
  private let barPosition: BarPosition
  private var hostingView: NSHostingView<AnyView>?

  init(screen: NSScreen, displayIndex: Int, position: BarPosition) {
    self.barScreen = screen
    self.displayIndex = displayIndex
    self.barPosition = position

    // Calculate frame for the bar
    let settings = SettingsManager.shared.settings.global
    let barHeight = settings.barHeight
    let distanceFromEdges = settings.barDistanceFromEdges
    let screenFrame = screen.frame

    let barY: CGFloat
    switch position {
    case .top:
      barY = screenFrame.maxY - barHeight - distanceFromEdges
    case .bottom:
      barY = screenFrame.minY + distanceFromEdges
    }

    let barFrame = NSRect(
      x: screenFrame.minX + distanceFromEdges,
      y: barY,
      width: screenFrame.width - (distanceFromEdges * 2),
      height: barHeight
    )
    
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
    self.level = .modalPanel - 9
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
      position: barPosition
    )
    .environmentObject(SettingsManager.shared)
    .environmentObject(YabaiService.shared)
    .environmentObject(AerospaceService.shared)
    .environmentObject(SystemInfoService.shared)
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

  func refreshWidget(_ identifier: WidgetIdentifier) {
    // The widgets will auto-refresh through their observed state
    // This method can be extended to force specific widget refreshes
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}
