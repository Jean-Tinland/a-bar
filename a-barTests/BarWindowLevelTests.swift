import XCTest

/// A top bar has to rise above macOS 27's invisible menu-bar window while the menu bar is hidden,
/// and nowhere else - a bar raised at the wrong moment covers the menu bar or a fullscreen app.
final class BarWindowLevelTests: XCTestCase {

  private func level(
    position: BarPosition = .top,
    autohides: Bool = true,
    visible: Bool = false,
    fullscreen: Bool = false,
    agentLayer: Int? = 24
  ) -> Int {
    BarWindowLevel.level(
      position: position, menuBarAutohides: autohides, menuBarVisible: visible,
      isFullscreenSpace: fullscreen, agentLayer: agentLayer)
  }

  // MARK: - Raised

  func testATopBarRisesAboveTheHiddenMenuBarWindow() {
    XCTAssertEqual(level(agentLayer: 24), 25)
  }

  func testTheRaiseFollowsWhateverLayerTheAgentUses() {
    // 27.0 puts the agent on the main-menu layer, 27.2 on the status layer.
    XCTAssertEqual(level(agentLayer: 25), 26)
  }

  // MARK: - Left where it was

  func testARevealedMenuBarGetsItsClicksBack() {
    XCTAssertEqual(level(visible: true), BarWindowLevel.base)
  }

  func testABottomBarIsNeverRaised() {
    XCTAssertEqual(level(position: .bottom), BarWindowLevel.base)
  }

  func testAFullscreenSpaceKeepsTheBarBehindTheApp() {
    XCTAssertEqual(level(fullscreen: true), BarWindowLevel.base)
  }

  func testAMenuBarThatNeverHidesIsLeftAlone() {
    XCTAssertEqual(level(autohides: false), BarWindowLevel.base)
  }

  func testWithoutTheAgentNothingChanges() {
    // macOS before 27 has no MenuBarAgent window to get under.
    XCTAssertEqual(level(agentLayer: nil), BarWindowLevel.base)
  }

  func testAnAgentBelowTheBarNeverPullsItDown() {
    XCTAssertEqual(level(agentLayer: -20), BarWindowLevel.base)
  }

  // MARK: - Popovers

  func testAPopoverStaysOnTheStatusLayerOverABarAtItsUsualLevel() {
    XCTAssertEqual(BarWindowLevel.popoverLevel(above: BarWindowLevel.base), BarWindowLevel.statusBar)
  }

  func testAPopoverStaysAboveARaisedBar() {
    XCTAssertEqual(BarWindowLevel.popoverLevel(above: 26), 27)
  }
}
