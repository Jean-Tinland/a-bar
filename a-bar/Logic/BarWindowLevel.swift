import Foundation

/// Which window-server layer a bar window sits on.
///
/// Since macOS 27 the menu bar is drawn by `MenuBarAgent`, which keeps a full-width window across
/// the top of each display - even while the menu bar is auto-hidden. That window is invisible but
/// still takes the clicks, so a top bar underneath it pulls the native menu bar down instead of
/// reaching its widgets (SketchyBar #852 is the same bug).
///
/// The way out is to sit one layer above that window while the menu bar is hidden, and drop back
/// once it is revealed so the menu bar stays usable. The agent recreates its window each time the
/// menu bar hides again, which is why a layer above is needed: ordering to the front within the
/// same layer only lasts until the next recreation.
enum BarWindowLevel {

  /// Where the bar has always lived: `NSWindow.Level.modalPanel` (8) minus 9, just below normal
  /// windows. Kept as a literal so this file stays free of AppKit.
  static let base = -1

  /// `kCGStatusWindowLevel`, the floor for anything that has to float over the bar.
  static let statusBar = 25

  /// The layer for one bar window.
  ///
  /// `agentLayer` is the highest layer of a `MenuBarAgent` window, or `nil` when there is none -
  /// macOS before 27 - in which case nothing changes. A fullscreen space hides the menu bar too,
  /// but the bar must stay behind the fullscreen window there, not draw over it.
  static func level(
    position: BarPosition,
    menuBarAutohides: Bool,
    menuBarVisible: Bool,
    isFullscreenSpace: Bool,
    agentLayer: Int?
  ) -> Int {
    guard
      position == .top, menuBarAutohides, !menuBarVisible, !isFullscreenSpace,
      let agentLayer
    else { return base }
    return max(base, agentLayer + 1)
  }

  /// A popover anchored to a bar has to stay above it, however high the bar was raised.
  static func popoverLevel(above barLevel: Int) -> Int {
    max(statusBar, barLevel + 1)
  }
}
