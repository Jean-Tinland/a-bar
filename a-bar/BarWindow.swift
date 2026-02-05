import AppKit
import SwiftUI

/// Custom window that displays the bar on a screen
class BarWindow: NSPanel {
  // We store the screen and position info to manage the bar's layout and content
  private let barScreen: NSScreen
  private let displayIndex: Int
  private let barPosition: BarPosition
  // The hosting view that contains the SwiftUI content of the bar
  private var hostingView: NSHostingView<AnyView>?

  // Initialize the bar window with the appropriate screen, display index, and position (top or bottom)
  init(screen: NSScreen, displayIndex: Int, position: BarPosition) {
    self.barScreen = screen
    self.displayIndex = displayIndex
    self.barPosition = position

    // Calculate frame for the bar
    let settings = SettingsManager.shared.settings.global
    let barHeight = settings.barHeight
    // Padding is hardcoded for now, but can be made user-configurable if needed. It provides spacing from the screen edges.
    let padding: CGFloat = 0

    let screenFrame = screen.frame

    let barY: CGFloat
    switch position {
    case .top:
      // Position the bar at the top of the screen, accounting for the menu bar height and padding
      barY = screenFrame.maxY - barHeight - padding
    case .bottom:
      // Position the bar at the bottom of the screen, accounting for padding
      barY = screenFrame.minY + padding
    }

    // The bar spans the full width of the screen, minus any horizontal padding
    let barFrame = NSRect(
      x: screenFrame.minX + padding,
      y: barY,
      width: screenFrame.width - (padding * 2),
      height: barHeight
    )
    
    //
    super.init(
      contentRect: barFrame,
      styleMask: [.borderless, .nonactivatingPanel, .hudWindow],
      backing: .buffered,
      defer: false
    )

    // Setup the window's properties and content
    setupWindow()
    setupContent()
  }

  // Configure the window's appearance and behavior to make it suitable for displaying the bar
  private func setupWindow() {
    // Window appearance
    // .modalPanel - 9 allow for a z-index contained under both the system status bar and the notification center
    self.level = .modalPanel - 9
    // The collection behavior ensures the bar appears on all spaces, doesn't cycle with other windows, and remains stationary in its assigned position
    self.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .fullScreenNone, .stationary]
    // Appearance settings to make the window blend with the desktop and not interfere with user interactions
    self.isOpaque = false
    // The background color is set to clear to allow the bar's content to define its appearance without an opaque window background
    self.backgroundColor = .clear
    // Remove window decorations and shadows to create a clean, integrated look for the bar
    self.hasShadow = false
    // Disable window movement by dragging the background to ensure the bar stays fixed in its position on the screen
    self.isMovableByWindowBackground = false
    // Allow the window to receive mouse moved events, which can be used for hover effects or interactive elements in the bar
    self.acceptsMouseMovedEvents = true
    // Allow interaction
    self.hidesOnDeactivate = false
    self.becomesKeyOnlyIfNeeded = true
  }

  // Set up the SwiftUI content for the bar by creating a BarView and embedding it in an NSHostingView, which is then set as the content view of the window
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

    // Using AnyView to erase the type of the barView, allowing for flexibility in the view hierarchy and composition
    hostingView = NSHostingView(rootView: AnyView(barView))
    // Set the hosting view's frame to match the content view's bounds, ensuring it fills the entire window. The autoresizing mask allows it to adjust automatically if the window size changes.
    hostingView?.frame = contentView?.bounds ?? .zero
    hostingView?.autoresizingMask = [.width, .height]

    contentView = hostingView
  }

  // Refresh the content of the bar, which can be triggered when settings change or when a manual refresh is needed. This method calls setupContent to recreate the SwiftUI view hierarchy with the latest data and settings.
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
