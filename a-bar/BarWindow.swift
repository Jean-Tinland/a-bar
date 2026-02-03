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
    let padding: CGFloat = 0

    let screenFrame = screen.frame

    let barY: CGFloat
    switch position {
    case .top:
      barY = screenFrame.maxY - barHeight - padding
    case .bottom:
      barY = screenFrame.minY + padding
    }

    let barFrame = NSRect(
      x: screenFrame.minX + padding,
      y: barY,
      width: screenFrame.width - (padding * 2),
      height: barHeight
    )

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
    // Window appearance
    // .modalPanel - 9 allow for a z-index contained under both the system status bar and the notification center
    self.level = .modalPanel - 9
    self.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .fullScreenNone, .stationary]
    self.isOpaque = false
    self.backgroundColor = .clear
    self.hasShadow = false
    self.isMovableByWindowBackground = false
    self.acceptsMouseMovedEvents = true

    // Allow interaction
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
    .environmentObject(SystemInfoService.shared)
    .environmentObject(LayoutManager.shared)

    hostingView = NSHostingView(rootView: AnyView(barView))
    hostingView?.frame = contentView?.bounds ?? .zero
    hostingView?.autoresizingMask = [.width, .height]

    contentView = hostingView
  }

  func refresh() {
    setupContent()
  }

  func refreshWidget(_ identifier: WidgetIdentifier) {
    // The widgets will auto-refresh through their observed state
    // This method can be extended to force specific widget refreshes
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}
