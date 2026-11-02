import XCTest

/// An exclusion pattern the user typed for yabai must behave identically under AeroSpace, and a
/// pattern that matches nothing must hide nothing. The rules used to be spelled out five times,
/// once per widget, and the copies did not agree - so the sections below are named after the
/// call site whose behaviour each one pins, not after the function under test.
final class WindowFilterTests: XCTestCase {

  // MARK: - Fixtures
  //
  // `YabaiWindow` and `YabaiSpace` keep private optional storage behind their computed
  // accessors, so their memberwise initializers are private too and JSON is the only way in.
  // The AeroSpace types have ordinary initializers.

  private func window(
    _ app: String, title: String = "", x: Double = 0, stackIndex: Int? = nil, id: Int = 1
  ) -> YabaiWindow {
    var fields: [String] = [
      "\"id\":\(id)", "\"pid\":\(1000 + id)", "\"app\":\"\(app)\"", "\"title\":\"\(title)\"",
      "\"display\":1", "\"space\":1",
      "\"frame\":{\"x\":\(x),\"y\":0,\"w\":100,\"h\":100}",
    ]
    if let stackIndex { fields.append("\"stack-index\":\(stackIndex)") }
    return decode(YabaiWindow.self, "{\(fields.joined(separator: ","))}")
  }

  private func space(_ label: String?, index: Int) -> YabaiSpace {
    var fields: [String] = [
      "\"id\":\(index)", "\"index\":\(index)", "\"display\":1", "\"type\":\"bsp\"",
      "\"windows\":[]",
    ]
    if let label { fields.append("\"label\":\"\(label)\"") }
    return decode(YabaiSpace.self, "{\(fields.joined(separator: ","))}")
  }

  private func aeroWindow(
    _ app: String, title: String = "", id: Int = 1
  ) -> AerospaceWindow {
    AerospaceWindow(windowId: id, appName: app, windowTitle: title)
  }

  private func workspace(_ name: String) -> AerospaceWorkspace {
    AerospaceWorkspace(workspace: name)
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

  /// The whole interface the filters need from a window is two strings and two numbers, which a
  /// test is free to supply itself.
  private struct FakeWindow {
    let name: String
    let heading: String
    let stack: Int?
    let left: Double
  }

  // MARK: - Reading the exclusion field

  func testTheFieldSplitsOnCommasAndTrimsEachEntry() {
    XCTAssertEqual(
      WindowFilter.patterns(from: "Finder, Safari ,Xcode"), ["Finder", "Safari", "Xcode"])
  }

  func testAPatternKeepsTheSpacesInsideIt() {
    // Only the ends are trimmed - "Activity Monitor" is one app, not two.
    XCTAssertEqual(WindowFilter.patterns(from: " Activity Monitor "), ["Activity Monitor"])
  }

  func testAnEmptyFieldProducesNoPatterns() {
    XCTAssertEqual(WindowFilter.patterns(from: ""), [])
    XCTAssertEqual(WindowFilter.patterns(from: "   "), [])
    XCTAssertEqual(WindowFilter.patterns(from: ",,,"), [])
  }

  func testATrailingCommaAndSpaceNoLongerHidesEverything() {
    // The bug: `split` drops the empty piece after a bare trailing comma, but "Finder, " splits
    // into ["Finder", " "], and that trims to "". An empty regular expression matches every
    // string, so with regex mode on the whole bar emptied while the user was still typing.
    XCTAssertEqual(WindowFilter.patterns(from: "Finder, "), ["Finder"])

    let spaces = [space("work", index: 1), space("mail", index: 2)]
    let kept = WindowFilter.excludingLabels(
      spaces, excluding: "Finder, ", asRegex: true, label: \.displayLabel)

    XCTAssertEqual(kept.count, 2, "a half-typed field must not hide every space")
  }

  // MARK: - Matching one value

  func testALiteralAppPatternMustMatchTheWholeName() {
    XCTAssertTrue(
      WindowFilter.isExcluded("Finder", by: ["Finder"], asRegex: false, literal: .whole))
    XCTAssertFalse(
      WindowFilter.isExcluded("Finder", by: ["Find"], asRegex: false, literal: .whole))
    XCTAssertFalse(
      WindowFilter.isExcluded("Finder", by: ["finder"], asRegex: false, literal: .whole),
      "whole-string matching is case sensitive")
  }

  func testALiteralTitlePatternNeedsOnlyToAppear() {
    XCTAssertTrue(
      WindowFilter.isExcluded(
        "Inbox (42) - Mail", by: ["Inbox"], asRegex: false, literal: .anywhere))
    XCTAssertFalse(
      WindowFilter.isExcluded("Inbox", by: ["Inbox (42)"], asRegex: false, literal: .anywhere),
      "substring matching does not run the other way round")
  }

  func testARegexPatternIsUnanchoredWhicheverFieldItCameFrom() {
    // `String.matches` is `range(of:options:.regularExpression)`, which searches rather than
    // anchors. A user who types `Mail` to exclude Mail also excludes "Mailbird", in both fields.
    XCTAssertTrue(
      WindowFilter.isExcluded("Mailbird", by: ["Mail"], asRegex: true, literal: .whole))
    XCTAssertTrue(
      WindowFilter.isExcluded("Mailbird", by: ["Mail"], asRegex: true, literal: .anywhere))
    XCTAssertFalse(
      WindowFilter.isExcluded("Mailbird", by: ["^Mail$"], asRegex: true, literal: .whole),
      "anchoring is available, it is just not the default")
  }

  func testARegexThatDoesNotParseMatchesNothing() {
    // The field is typed into live, so it is half-written most of the time. A lone "[" must cost
    // nothing rather than throw or match everything.
    XCTAssertFalse(WindowFilter.isExcluded("Finder", by: ["["], asRegex: true, literal: .whole))
    XCTAssertFalse(WindowFilter.isExcluded("Finder", by: ["*"], asRegex: true, literal: .whole))
  }

  func testNoPatternsExcludeNothing() {
    XCTAssertFalse(WindowFilter.isExcluded("Finder", by: [], asRegex: false, literal: .whole))
    XCTAssertFalse(WindowFilter.isExcluded("Finder", by: [], asRegex: true, literal: .anywhere))
  }

  // MARK: - SpacesWidget: yabai space labels

  func testSpacesWidgetHidesTheSpaceWhoseLabelIsListed() {
    let spaces = [space("work", index: 1), space("mail", index: 2), space("chat", index: 3)]

    let kept = WindowFilter.excludingLabels(
      spaces, excluding: "mail", asRegex: false, label: \.displayLabel)

    XCTAssertEqual(kept.map { $0.displayLabel }, ["work", "chat"])
  }

  func testSpacesWidgetComparesAnUnlabelledSpaceByItsIndex() {
    // `displayLabel` falls back to the index, so "2" in the field hides the second desktop.
    let spaces = [space(nil, index: 1), space(nil, index: 2)]

    let kept = WindowFilter.excludingLabels(
      spaces, excluding: "2", asRegex: false, label: \.displayLabel)

    XCTAssertEqual(kept.map { $0.displayLabel }, ["1"])
  }

  func testSpacesWidgetDoesNotHideSpaceTwelveWhenExcludingSpaceOne() {
    // Labels are matched whole in literal mode. This is the reason for that.
    let spaces = [space(nil, index: 1), space(nil, index: 12)]

    let kept = WindowFilter.excludingLabels(
      spaces, excluding: "1", asRegex: false, label: \.displayLabel)

    XCTAssertEqual(kept.map { $0.displayLabel }, ["12"])
  }

  func testSpacesWidgetMatchesLabelsByRegexWhenAsked() {
    let spaces = [space("dev1", index: 1), space("dev2", index: 2), space("mail", index: 3)]

    let kept = WindowFilter.excludingLabels(
      spaces, excluding: "^dev[0-9]$", asRegex: true, label: \.displayLabel)

    XCTAssertEqual(kept.map { $0.displayLabel }, ["mail"])
  }

  func testSpacesWidgetWithAnEmptyFieldKeepsEverySpace() {
    let spaces = [space("work", index: 1), space("mail", index: 2)]

    XCTAssertEqual(
      WindowFilter.excludingLabels(spaces, excluding: "", asRegex: false, label: \.displayLabel),
      spaces)
    XCTAssertEqual(
      WindowFilter.excludingLabels(spaces, excluding: "", asRegex: true, label: \.displayLabel),
      spaces)
  }

  func testSpacesWidgetKeepsTheOrderYabaiReportedTheSpacesIn() {
    let spaces = [space("c", index: 1), space("a", index: 2), space("b", index: 3)]

    let kept = WindowFilter.excludingLabels(
      spaces, excluding: "nothing", asRegex: false, label: \.displayLabel)

    XCTAssertEqual(kept.map { $0.displayLabel }, ["c", "a", "b"])
  }

  // MARK: - AerospaceSpacesWidget: workspace labels

  func testAerospaceSpacesWidgetHidesTheSameLabelsAsSpacesWidget() {
    let workspaces = [workspace("work"), workspace("mail"), workspace("chat")]

    let kept = WindowFilter.excludingLabels(
      workspaces, excluding: "mail", asRegex: false, label: \.displayLabel)

    XCTAssertEqual(kept.map { $0.workspace }, ["work", "chat"])
  }

  func testAerospaceSpacesWidgetMatchesWorkspaceNamesByRegex() {
    // AeroSpace names workspaces with strings rather than numbers, so regex mode is the one
    // that earns its keep here.
    let workspaces = [workspace("dev-web"), workspace("dev-ios"), workspace("mail")]

    let kept = WindowFilter.excludingLabels(
      workspaces, excluding: "^dev-", asRegex: true, label: \.displayLabel)

    XCTAssertEqual(kept.map { $0.workspace }, ["mail"])
  }

  // MARK: - OpenedAppsView: yabai windows

  func testOpenedAppsExcludesAnAppByItsExactName() {
    let windows = [window("Finder", id: 1), window("Safari", id: 2)]

    let kept = WindowFilter.excludingWindows(
      windows, excludingApps: "Finder", excludingTitles: "", asRegex: false,
      appName: \.app, title: \.title)

    XCTAssertEqual(kept.map { $0.app }, ["Safari"])
  }

  func testOpenedAppsKeepsAnAppWhoseNameOnlyContainsThePattern() {
    // App names are whole-string in literal mode while titles are substring. The asymmetry is
    // deliberate, and this is the half of it that surprises people.
    let windows = [window("Mailbird", id: 1)]

    let kept = WindowFilter.excludingWindows(
      windows, excludingApps: "Mail", excludingTitles: "", asRegex: false,
      appName: \.app, title: \.title)

    XCTAssertEqual(kept.map { $0.app }, ["Mailbird"])
  }

  func testOpenedAppsExcludesAWindowByATitleSubstring() {
    let windows = [
      window("Safari", title: "Inbox (42) - Mail", id: 1),
      window("Safari", title: "a-bar - GitHub", id: 2),
    ]

    let kept = WindowFilter.excludingWindows(
      windows, excludingApps: "", excludingTitles: "Inbox", asRegex: false,
      appName: \.app, title: \.title)

    XCTAssertEqual(kept.map { $0.id }, [2])
  }

  func testOpenedAppsAppliesBothFieldsAtOnce() {
    let windows = [
      window("Finder", title: "Downloads", id: 1),
      window("Safari", title: "Inbox - Mail", id: 2),
      window("Xcode", title: "a-bar", id: 3),
    ]

    let kept = WindowFilter.excludingWindows(
      windows, excludingApps: "Finder", excludingTitles: "Inbox", asRegex: false,
      appName: \.app, title: \.title)

    XCTAssertEqual(kept.map { $0.app }, ["Xcode"])
  }

  func testOpenedAppsWithNeitherFieldSetKeepsEveryWindow() {
    let windows = [window("Finder", id: 1), window("Safari", id: 2)]

    XCTAssertEqual(
      WindowFilter.excludingWindows(
        windows, excludingApps: "", excludingTitles: "", asRegex: false,
        appName: \.app, title: \.title),
      windows)
  }

  func testOpenedAppsKeepsAWindowWithNoTitleWhenATitlePatternIsSet() {
    // yabai reports "" for a window whose title it cannot read. An empty title must not be
    // treated as matching every pattern.
    let windows = [window("Finder", title: "", id: 1)]

    let kept = WindowFilter.excludingWindows(
      windows, excludingApps: "", excludingTitles: "Inbox", asRegex: false,
      appName: \.app, title: \.title)

    XCTAssertEqual(kept.count, 1)
  }

  func testOpenedAppsDedupesByAppKeepingTheFirstWindow() {
    let windows = [
      window("Safari", id: 1), window("Xcode", id: 2), window("Safari", id: 3),
      window("Xcode", id: 4),
    ]

    let kept = WindowFilter.deduplicatedByApp(windows, appName: \.app)

    XCTAssertEqual(kept.map { $0.id }, [1, 2], "the first window of each app survives")
  }

  func testOpenedAppsDedupeIsSkippedWhenHideDuplicateAppsIsOff() {
    // The gate lives at the call site: the widget calls `deduplicatedByApp` or it does not.
    // `AerospaceOpenedAppsView` gates it the same way; `StickyWindowsView` never does.
    let windows = [window("Safari", id: 1), window("Safari", id: 2)]

    XCTAssertEqual(windows.map { $0.id }, [1, 2])
    XCTAssertEqual(WindowFilter.deduplicatedByApp(windows, appName: \.app).map { $0.id }, [1])
  }

  // MARK: - ProcessWidget: spatial ordering

  func testProcessWidgetSortsByStackIndexThenPosition() {
    // Two unstacked windows - yabai reports stack index 0 for those - order left to right.
    let windows = [
      window("Xcode", x: 900, stackIndex: 0, id: 1),
      window("Safari", x: 100, stackIndex: 0, id: 2),
      window("Notes", x: 500, stackIndex: 0, id: 3),
    ]

    let ordered = WindowFilter.orderedByStackThenPosition(
      windows, stackIndex: \.stackIndex, x: \.frame.x)

    XCTAssertEqual(ordered.map { $0.app }, ["Safari", "Notes", "Xcode"])
  }

  func testProcessWidgetPutsAStackInItsOwnOrderBeforePosition() {
    // Windows in a stack share a frame, so x cannot separate them - the stack index must win.
    let windows = [
      window("third", x: 100, stackIndex: 3, id: 1),
      window("first", x: 100, stackIndex: 1, id: 2),
      window("second", x: 100, stackIndex: 2, id: 3),
    ]

    let ordered = WindowFilter.orderedByStackThenPosition(
      windows, stackIndex: \.stackIndex, x: \.frame.x)

    XCTAssertEqual(ordered.map { $0.app }, ["first", "second", "third"])
  }

  func testProcessWidgetPlacesUnstackedWindowsBeforeStacks() {
    let windows = [
      window("Xcode", x: 900, stackIndex: 0, id: 1),
      window("Safari", x: 100, stackIndex: 2, id: 2),
      window("Notes", x: 100, stackIndex: 1, id: 3),
    ]

    let ordered = WindowFilter.orderedByStackThenPosition(
      windows, stackIndex: \.stackIndex, x: \.frame.x)

    XCTAssertEqual(ordered.map { $0.app }, ["Xcode", "Notes", "Safari"])
  }

  func testAWindowWithNoStackIndexSortsAsIfItWereNotStacked() {
    // A missing `stack-index` means the same thing as the 0 yabai sends for an unstacked
    // window - the process widget hides its badge on exactly that value.
    let windows = [
      window("stacked", x: 500, stackIndex: 1, id: 1),
      window("unreported", x: 900, stackIndex: nil, id: 2),
    ]

    let ordered = WindowFilter.orderedByStackThenPosition(
      windows, stackIndex: \.stackIndex, x: \.frame.x)

    XCTAssertEqual(ordered.map { $0.app }, ["unreported", "stacked"])
  }

  func testMixingStackedAndUnstackedWindowsNoLongerDependsOnTheInputOrder() {
    // The bug: the old comparator compared x whenever *either* window lacked a stack index, and
    // the stack index only when both had one. That is not an ordering. With these three it
    // claims A < B, B < C and C < A at the same time, so `sort` could return any arrangement -
    // and did, depending on the order yabai happened to list the windows in.
    let a = FakeWindow(name: "A", heading: "", stack: 1, left: 10)
    let b = FakeWindow(name: "B", heading: "", stack: 2, left: 5)
    let c = FakeWindow(name: "C", heading: "", stack: nil, left: 7)

    let permutations = [
      [a, b, c], [a, c, b], [b, a, c], [b, c, a], [c, a, b], [c, b, a],
    ]

    for input in permutations {
      let ordered = WindowFilter.orderedByStackThenPosition(
        input, stackIndex: \.stack, x: \.left)

      XCTAssertEqual(
        ordered.map { $0.name }, ["C", "A", "B"],
        "the same three windows must order the same way whatever order they arrive in")
    }
  }

  func testWindowsSharingAStackPositionAndAnXKeepTheirArrivalOrder() {
    // `sort` is not stable, so overlapping floating windows used to be free to swap places
    // between refreshes. Nothing on screen explains that, so ties fall back to arrival order.
    let windows = [
      window("A", x: 100, stackIndex: 0, id: 1),
      window("B", x: 100, stackIndex: 0, id: 2),
      window("C", x: 100, stackIndex: 0, id: 3),
    ]

    let ordered = WindowFilter.orderedByStackThenPosition(
      windows, stackIndex: \.stackIndex, x: \.frame.x)

    XCTAssertEqual(ordered.map { $0.app }, ["A", "B", "C"])
  }

  func testOrderingAnEmptyOrSingleListIsANoOp() {
    let one = [window("Finder", id: 1)]

    XCTAssertEqual(
      WindowFilter.orderedByStackThenPosition(
        [] as [YabaiWindow], stackIndex: \.stackIndex, x: \.frame.x),
      [])
    XCTAssertEqual(
      WindowFilter.orderedByStackThenPosition(one, stackIndex: \.stackIndex, x: \.frame.x), one)
  }

  // MARK: - AerospaceOpenedAppsView: the same rules, without the ordering

  func testAerospaceOpenedAppsPreservesSourceOrder() {
    // The row follows `aerospace list-windows` order, which filtering must preserve.
    let windows = [
      aeroWindow("Xcode", id: 1), aeroWindow("Safari", id: 2), aeroWindow("Notes", id: 3),
    ]

    let kept = WindowFilter.excludingWindows(
      windows, excludingApps: "nothing", excludingTitles: "", asRegex: false,
      appName: \.appName, title: \.windowTitle)

    XCTAssertEqual(kept.map { $0.appName }, ["Xcode", "Safari", "Notes"])
  }

  func testAerospaceOpenedAppsExcludesTheSameNamesAsOpenedApps() {
    let windows = [aeroWindow("Finder", id: 1), aeroWindow("Safari", id: 2)]

    let kept = WindowFilter.excludingWindows(
      windows, excludingApps: "Finder", excludingTitles: "", asRegex: false,
      appName: \.appName, title: \.windowTitle)

    XCTAssertEqual(kept.map { $0.appName }, ["Safari"])
  }

  func testAerospaceOpenedAppsDedupesByAppName() {
    let windows = [
      aeroWindow("Safari", id: 1), aeroWindow("Xcode", id: 2), aeroWindow("Safari", id: 3),
    ]

    let kept = WindowFilter.deduplicatedByApp(windows, appName: \.appName)

    XCTAssertEqual(kept.map { $0.windowId }, [1, 2])
  }

  // MARK: - StickyWindowsView: dedupe with no setting behind it

  func testStickyWindowsDedupeWhateverTheHideDuplicateAppsSettingSays() {
    // The pinned row shows one icon per app and always has - it is a reminder that the app is
    // on every space, not a window list. Nothing gates it, and that is on purpose.
    let sticky = [
      window("1Password", id: 1), window("1Password", id: 2), window("Music", id: 3),
    ]

    let kept = WindowFilter.deduplicatedByApp(sticky, appName: \.app)

    XCTAssertEqual(kept.map { $0.app }, ["1Password", "Music"])
  }

  func testDedupingAnEmptyListProducesAnEmptyList() {
    XCTAssertEqual(WindowFilter.deduplicatedByApp([] as [YabaiWindow], appName: \.app), [])
  }

  // MARK: - The two window managers must agree

  func testTheSamePatternHidesTheSameAppUnderBothWindowManagers() {
    let names = ["Finder", "Mailbird", "Safari"]
    let yabai = names.enumerated().map { window($1, id: $0) }
    let aero = names.enumerated().map { aeroWindow($1, id: $0) }

    for (field, regex) in [("Finder", false), ("^Mail", true), ("Safari|Finder", true)]
      as [(String, Bool)]
    {
      let keptYabai = WindowFilter.excludingWindows(
        yabai, excludingApps: field, excludingTitles: "", asRegex: regex,
        appName: \.app, title: \.title)
      let keptAero = WindowFilter.excludingWindows(
        aero, excludingApps: field, excludingTitles: "", asRegex: regex,
        appName: \.appName, title: \.windowTitle)

      XCTAssertEqual(
        keptYabai.map { $0.app }, keptAero.map { $0.appName },
        "\"\(field)\" (regex: \(regex)) must hide the same apps under both")
    }
  }

  func testTheSameTitlePatternHidesTheSameWindowUnderBothWindowManagers() {
    let titles = ["Inbox (42) - Mail", "a-bar - GitHub", ""]
    let yabai = titles.enumerated().map { window("Safari", title: $1, id: $0) }
    let aero = titles.enumerated().map { aeroWindow("Safari", title: $1, id: $0) }

    for (field, regex) in [("Inbox", false), ("^Inbox", true), ("GitHub", false)]
      as [(String, Bool)]
    {
      let keptYabai = WindowFilter.excludingWindows(
        yabai, excludingApps: "", excludingTitles: field, asRegex: regex,
        appName: \.app, title: \.title)
      let keptAero = WindowFilter.excludingWindows(
        aero, excludingApps: "", excludingTitles: field, asRegex: regex,
        appName: \.appName, title: \.windowTitle)

      XCTAssertEqual(
        keptYabai.map { $0.title }, keptAero.map { $0.windowTitle },
        "\"\(field)\" (regex: \(regex)) must hide the same windows under both")
    }
  }

  func testAPatternThatMatchesNothingHidesNothing() {
    let windows = [window("Finder", title: "Downloads", id: 1), window("Safari", id: 2)]
    let spaces = [space("work", index: 1), space("mail", index: 2)]

    for regex in [false, true] {
      XCTAssertEqual(
        WindowFilter.excludingWindows(
          windows, excludingApps: "NoSuchApp", excludingTitles: "NoSuchTitle", asRegex: regex,
          appName: \.app, title: \.title),
        windows)
      XCTAssertEqual(
        WindowFilter.excludingLabels(
          spaces, excluding: "NoSuchSpace", asRegex: regex, label: \.displayLabel),
        spaces)
    }
  }
}
