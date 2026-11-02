import XCTest

/// The bar's view of yabai is a set of filters over one snapshot. A window that is minimised,
/// hidden or sticky must be excluded by the filter that claims it and by no other, or the
/// spaces widget shows desktops that are empty and apps that are not there.
final class YabaiStateTests: XCTestCase {

  // MARK: - Fixtures
  //
  // `YabaiSpace` and `YabaiWindow` carry private optional storage behind their computed
  // `hasFocus`/`isSticky` accessors, which makes their memberwise initializers private too.
  // Building them from JSON is therefore the only way in - and is what production does anyway.

  private func space(
    id: Int, index: Int, display: Int = 1, label: String? = nil,
    focused: Bool? = nil, visible: Bool? = nil, windows: [Int] = [],
    type: YabaiSpace.SpaceType = .bsp
  ) -> YabaiSpace {
    var fields: [String] = [
      "\"id\":\(id)", "\"index\":\(index)", "\"display\":\(display)",
      "\"type\":\"\(type.rawValue)\"", "\"windows\":\(windows)",
    ]
    if let label { fields.append("\"label\":\"\(label)\"") }
    if let focused { fields.append("\"has-focus\":\(focused)") }
    if let visible { fields.append("\"is-visible\":\(visible)") }
    return decode(YabaiSpace.self, "{\(fields.joined(separator: ","))}")
  }

  private func window(
    id: Int, app: String, title: String = "", space: Int = 1, display: Int = 1,
    x: Double = 0, focused: Bool? = nil, minimized: Bool? = nil,
    hidden: Bool? = nil, sticky: Bool? = nil, floating: Bool? = nil, stackIndex: Int? = nil
  ) -> YabaiWindow {
    var fields: [String] = [
      "\"id\":\(id)", "\"pid\":\(1000 + id)", "\"app\":\"\(app)\"", "\"title\":\"\(title)\"",
      "\"display\":\(display)", "\"space\":\(space)",
      "\"frame\":{\"x\":\(x),\"y\":0,\"w\":100,\"h\":100}",
    ]
    if let focused { fields.append("\"has-focus\":\(focused)") }
    if let minimized { fields.append("\"is-minimized\":\(minimized)") }
    if let hidden { fields.append("\"is-hidden\":\(hidden)") }
    if let sticky { fields.append("\"is-sticky\":\(sticky)") }
    if let floating { fields.append("\"is-floating\":\(floating)") }
    if let stackIndex { fields.append("\"stack-index\":\(stackIndex)") }
    return decode(YabaiWindow.self, "{\(fields.joined(separator: ","))}")
  }

  private func decode<T: Decodable>(
    _ type: T.Type, _ json: String, file: StaticString = #filePath, line: UInt = #line
  ) -> T {
    do {
      return try JSONDecoder().decode(type, from: Data(json.utf8))
    } catch {
      XCTFail("fixture did not decode: \(error)", file: file, line: line)
      fatalError("unreachable")
    }
  }

  // MARK: - A field yabai stops sending must not mean "true"

  func testAbsentStateFlagsReadAsFalse() {
    // yabai renamed these keys between versions. Decoding must not fail, and a missing flag
    // must not make every window look focused, sticky or minimised.
    let plain = window(id: 1, app: "Safari")

    XCTAssertFalse(plain.hasFocus)
    XCTAssertFalse(plain.isMinimized)
    XCTAssertFalse(plain.isHidden)
    XCTAssertFalse(plain.isSticky)
  }

  func testPresentStateFlagsAreRead() {
    let sticky = window(id: 1, app: "Music", sticky: true)

    XCTAssertTrue(sticky.isSticky)
  }

  func testSpaceFlagsReadTheHyphenatedKeys() {
    let focused = space(id: 1, index: 1, focused: true, visible: true)

    XCTAssertTrue(focused.hasFocus)
    XCTAssertTrue(focused.isVisible)
    XCTAssertFalse(space(id: 2, index: 2).hasFocus)
  }

  func testFocusedWindowModeUsesWindowFlagsInsteadOfSpaceLayout() {
    let cases: [(Bool?, Int?, String)] = [
      (true, nil, "float"), (true, 2, "float"),
      (false, 2, "stack"), (false, 0, "bsp"), (nil, nil, "bsp"),
    ]
    for (floating, stackIndex, expected) in cases {
      let snapshot = YabaiState(
        spaces: [space(id: 1, index: 1, focused: true)],
        windows: [window(id: 10, app: "Fixture", focused: true,
                         floating: floating, stackIndex: stackIndex)])
      XCTAssertEqual(snapshot.focusedSpace?.type, .bsp)
      XCTAssertEqual(snapshot.focusedWindow?.layoutLabel, expected)
    }
  }

  func testStickyDoesNotReplaceTheFocusedWindowMode() {
    let snapshot = YabaiState(
      spaces: [space(id: 1, index: 1, focused: true)],
      windows: [window(id: 10, app: "Fixture", space: 2, focused: true,
                       sticky: true, floating: true)])
    XCTAssertEqual(snapshot.focusedWindow?.layoutLabel, "float")
    XCTAssertEqual(snapshot.focusedWindow?.isSticky, true)
    XCTAssertNotEqual(snapshot.focusedWindow?.space, snapshot.focusedSpace?.index)
    XCTAssertNil(YabaiState().focusedWindow)
  }

  func testSpaceAndWindowLayoutsStayIndependentForEverySpaceType() {
    let types: [YabaiSpace.SpaceType] = [.bsp, .stack, .float]
    for type in types {
      let snapshot = YabaiState(
        spaces: [space(id: 1, index: 1, focused: true, type: type)],
        windows: [window(id: 10, app: "Fixture", focused: true, floating: true, stackIndex: 2)])
      XCTAssertEqual(snapshot.focusedSpace?.type, type)
      XCTAssertEqual(snapshot.focusedWindow?.layoutType, .float)
      XCTAssertEqual(snapshot.focusedWindow?.layoutType.systemImage, "rectangle.on.rectangle")
    }
    XCTAssertEqual(YabaiSpace.SpaceType.bsp.systemImage, "square.grid.2x2")
    XCTAssertEqual(YabaiSpace.SpaceType.stack.systemImage, "rectangle.stack")
    XCTAssertNil(YabaiState(windows: [window(id: 10, app: "Fixture", focused: true)]).focusedSpace)
  }

  // MARK: - A space shows its label, or its number

  func testASpaceWithALabelShowsIt() {
    XCTAssertEqual(space(id: 1, index: 3, label: "code").displayLabel, "code")
  }

  func testASpaceWithoutALabelFallsBackToItsIndex() {
    XCTAssertEqual(space(id: 1, index: 3).displayLabel, "3")
  }

  func testASpaceWithABlankLabelFallsBackToItsIndex() {
    // yabai returns "" rather than omitting the key when a label is cleared.
    XCTAssertEqual(space(id: 1, index: 4, label: "").displayLabel, "4")
  }

  // MARK: - Which windows belong to a space

  private func state() -> YabaiState {
    YabaiState(
      spaces: [
        space(id: 1, index: 1, display: 1, focused: true),
        space(id: 2, index: 2, display: 1),
        space(id: 3, index: 3, display: 2),
      ],
      windows: [
        window(id: 10, app: "Safari", space: 1, x: 300, focused: true),
        window(id: 11, app: "Notes", space: 1, x: 100),
        window(id: 12, app: "Safari", space: 1, x: 200),
        window(id: 13, app: "Music", space: 1, sticky: true),
        window(id: 14, app: "Slack", space: 1, minimized: true),
        window(id: 15, app: "Xcode", space: 1, hidden: true),
        window(id: 16, app: "Mail", space: 2),
      ],
      displays: [
        decode(YabaiDisplay.self, #"{"id":1,"uuid":"A","index":1,"frame":{"x":0,"y":0,"w":1,"h":1},"spaces":[1,2]}"#),
        decode(YabaiDisplay.self, #"{"id":2,"uuid":"B","index":2,"frame":{"x":0,"y":0,"w":1,"h":1},"spaces":[3]}"#),
      ])
  }

  func testMinimisedAndHiddenWindowsAreNeverListed() {
    // They exist in the snapshot but the user cannot see them, so the bar must not either.
    let apps = state().windows(forSpace: 1).map { $0.app }

    XCTAssertFalse(apps.contains("Slack"), "a minimised window is not on screen")
    XCTAssertFalse(apps.contains("Xcode"), "nor is a hidden one")
  }

  func testASpacesWindowsIncludeItsStickyOnes() {
    XCTAssertTrue(state().windows(forSpace: 1).map { $0.app }.contains("Music"))
  }

  func testNonStickyWindowsExcludeTheStickyOnes() {
    // Sticky windows are drawn once, separately - counting them per space duplicates them.
    let apps = state().nonStickyWindows(forSpace: 1).map { $0.app }

    XCTAssertEqual(apps, ["Safari", "Notes", "Safari"])
  }

  func testStickyWindowsAreCollectedAcrossEverySpace() {
    XCTAssertEqual(state().stickyWindows().map { $0.app }, ["Music"])
  }

  func testAStickyWindowThatIsMinimisedIsStillHidden() {
    let hiddenSticky = YabaiState(windows: [
      window(id: 1, app: "Music", sticky: true, stackIndex: nil),
      window(id: 2, app: "Podcasts", minimized: true, sticky: true),
    ])

    XCTAssertEqual(hiddenSticky.stickyWindows().map { $0.app }, ["Music"])
  }

  func testAnEmptySpaceHasNoWindows() {
    XCTAssertEqual(state().windows(forSpace: 9), [])
  }

  // MARK: - Focus

  func testTheFocusedSpaceAndWindowAreFound() {
    XCTAssertEqual(state().focusedSpace?.index, 1)
    XCTAssertEqual(state().focusedWindow?.app, "Safari")
  }

  func testNothingFocusedIsNotAnError() {
    let idle = YabaiState(spaces: [space(id: 1, index: 1)], windows: [])

    XCTAssertNil(idle.focusedSpace)
    XCTAssertNil(idle.focusedWindow)
  }

  // MARK: - Displays

  func testSpacesAreFilteredByDisplay() {
    XCTAssertEqual(state().spaces(forDisplay: 1).map { $0.index }, [1, 2])
    XCTAssertEqual(state().spaces(forDisplay: 2).map { $0.index }, [3])
    XCTAssertEqual(state().spaces(forDisplay: 9), [])
  }

  func testASpaceResolvesToItsDisplayInTwoHops() {
    // space index -> space.display -> display index; a broken hop shows the bar on no monitor.
    XCTAssertEqual(state().display(forSpace: 3)?.index, 2)
    XCTAssertEqual(state().display(forSpace: 1)?.uuid, "A")
    XCTAssertNil(state().display(forSpace: 99), "an unknown space belongs to no display")
  }

  // MARK: - One icon per app

  func testSpaceIconOrderSurvivesDraggingPastAnotherWindow() {
    let target = space(id: 1, index: 1)
    let before = YabaiState(windows: [
      window(id: 10, app: "kitty", x: 100),
      window(id: 20, app: "Codex", x: 500),
    ])
    let after = YabaiState(windows: [
      window(id: 20, app: "Codex", x: 500),
      window(id: 10, app: "kitty", x: 900),
    ])

    let original = OpenedAppsView.windows(for: target, state: before, settings: .init())
    let moved = OpenedAppsView.windows(for: target, state: after, settings: .init())
    XCTAssertEqual(original.map(\.id), [20, 10])
    XCTAssertEqual(moved, original, "geometry and query order must not reorder Space icons")
  }

  func testSpaceAppOrderingPreservesTheDuplicateRepresentative() {
    let target = space(id: 1, index: 1)
    let windows = [
      window(id: 30, app: "Safari", title: "Current", x: 100, focused: true),
      window(id: 20, app: "kitty", x: 500),
      window(id: 10, app: "Safari", title: "Other", x: 900, focused: false),
    ]
    for (snapshot, expectedID, expectedFocus, expectedTitle) in [
      (windows, 30, true, "Current"), (Array(windows.reversed()), 10, false, "Other"),
    ] {
      let state = YabaiState(windows: snapshot)
      let icons = OpenedAppsView.windows(for: target, state: state, settings: .init())
      XCTAssertEqual(icons.map(\.id), [expectedID, 20])
      XCTAssertEqual(icons.map(\.app), ["Safari", "kitty"])
      XCTAssertEqual(icons.first?.hasFocus, expectedFocus)
      XCTAssertEqual(icons.first?.title, expectedTitle)
      var settings = SpacesWidgetSettings()
      settings.hideDuplicateApps = false
      XCTAssertEqual(OpenedAppsView.windows(for: target, state: state, settings: settings).map(\.id), [10, 30, 20])
    }
  }

  func testSpaceIconsStillFollowWindowMembershipChanges() {
    let target = space(id: 1, index: 1)
    let before = YabaiState(windows: [window(id: 10, app: "kitty"), window(id: 20, app: "Codex", space: 2)])
    let movedAndOpened = YabaiState(windows: [
      window(id: 30, app: "Safari"), window(id: 10, app: "kitty", space: 2), window(id: 20, app: "Codex"),
    ])
    let closed = YabaiState(windows: [window(id: 30, app: "Safari")])

    XCTAssertEqual(OpenedAppsView.windows(for: target, state: before, settings: .init()).map(\.id), [10])
    XCTAssertEqual(OpenedAppsView.windows(for: target, state: movedAndOpened, settings: .init()).map(\.id), [20, 30])
    XCTAssertEqual(OpenedAppsView.windows(for: target, state: closed, settings: .init()).map(\.id), [30])
  }

  func testSpaceIconsApplyExclusionsBeforeChoosingADuplicate() {
    var settings = SpacesWidgetSettings()
    settings.exclusions = "Finder"
    settings.titleExclusions = "Private"
    let snapshot = YabaiState(windows: [
      window(id: 10, app: "Safari", title: "Private"), window(id: 20, app: "Safari", title: "Work"),
      window(id: 30, app: "Finder"), window(id: 40, app: "Music", sticky: true),
      window(id: 50, app: "Mail", minimized: true), window(id: 60, app: "Notes", hidden: true),
    ])
    XCTAssertEqual(OpenedAppsView.windows(for: space(id: 1, index: 1), state: snapshot, settings: settings).map(\.id), [20])
  }

  func testRepeatedAppsAreShownOnceInTheOrderTheyFirstAppear() {
    let apps = state().uniqueApps(forSpace: 1)

    XCTAssertEqual(apps.map { $0.app }, ["Safari", "Notes"], "first occurrence wins")
    XCTAssertEqual(apps.first?.id, 10, "and it keeps that window's identity")
  }

  func testStickyAppsCanBeIncludedOnRequest() {
    let apps = state().uniqueApps(forSpace: 1, excludingSticky: false)

    XCTAssertEqual(apps.map { $0.app }, ["Safari", "Notes", "Music"])
  }
}
