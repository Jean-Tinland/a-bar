import XCTest

/// The blast radius of a bad value must be the smallest element that contains it.
final class SettingsCodecTests: XCTestCase {

  // MARK: - One bad value must not cost the file

  func testUnknownWidgetIdentifierDropsOnlyThatWidget() {
    // The dev-build case: a WIP widget written to the config, then opened by a build that
    // has never heard of it. This used to reset every setting in the file.
    var config = SettingsFixtures.json(SettingsFixtures.settings())
    SettingsFixtures.set(
      "wip-widget",
      at: "profiles.0.multiDisplayLayout.displays.0.topBar.right.1.identifier",
      in: &config)

    let (settings, repairs) = decodeSettings(config)

    let right = settings.profiles[0].multiDisplayLayout.displays[0].topBar?.right
    XCTAssertEqual(right?.map { $0.identifier }, [.cpu, .wifi], "only the unknown widget goes")
    XCTAssertEqual(settings.global.barHeight, 42)
    XCTAssertEqual(settings.theme.darkTheme, .tokyoNight)
    XCTAssertEqual(settings.widgets.battery.refreshInterval, 12)
    XCTAssertEqual(settings.userWidgets.count, 1)
    XCTAssertEqual(settings.profiles[0].name, "Work")
    XCTAssertEqual(repairs.count, 1)
    XCTAssertEqual(repairs.first?.action, .droppedElement)
  }

  func testUnknownThemePresetResetsOnlyThatField() {
    var config = SettingsFixtures.json(SettingsFixtures.settings())
    SettingsFixtures.set("not-a-theme", at: "theme.darkTheme", in: &config)

    let (settings, repairs) = decodeSettings(config)

    XCTAssertEqual(settings.theme.darkTheme, ThemeSettings().darkTheme)
    XCTAssertEqual(settings.theme.appearance, .dark, "the sibling survives")
    XCTAssertEqual(settings.global.barHeight, 42)
    XCTAssertEqual(settings.profiles.count, 1)
    XCTAssertEqual(repairs.map { $0.action }, [.filledDefault])
  }

  func testTypeMismatchResetsOnlyThatField() {
    var config = SettingsFixtures.json(SettingsFixtures.settings())
    SettingsFixtures.set("tall", at: "global.barHeight", in: &config)

    let (settings, repairs) = decodeSettings(config)

    XCTAssertEqual(settings.global.barHeight, GlobalSettings().barHeight)
    XCTAssertEqual(settings.global.fontName, "Menlo")
    XCTAssertEqual(settings.global.barOpacity, 55)
    XCTAssertEqual(repairs.map { $0.action }, [.filledDefault])
  }

  func testSeveralBadValuesAreEachRepairedIndependently() {
    var config = SettingsFixtures.json(SettingsFixtures.settings())
    SettingsFixtures.set("tall", at: "global.barHeight", in: &config)
    SettingsFixtures.set("not-a-theme", at: "theme.darkTheme", in: &config)
    SettingsFixtures.set(
      "wip-widget", at: "profiles.0.multiDisplayLayout.displays.0.topBar.left.0.identifier",
      in: &config)

    let (settings, repairs) = decodeSettings(config)

    XCTAssertEqual(repairs.count, 3)
    XCTAssertEqual(settings.global.fontName, "Menlo")
    XCTAssertEqual(settings.widgets.weather.customLocation, "Lyon")
    XCTAssertEqual(settings.profiles[0].multiDisplayLayout.displays[0].topBar?.left, [])
  }

  // MARK: - Fields added after a config was written

  func testOlderTimeSettingsDefaultToTimersWithoutLosingPreferences() {
    var config = SettingsFixtures.json(SettingsFixtures.settings())
    SettingsFixtures.set(true, at: "widgets.time.showSeconds", in: &config)
    SettingsFixtures.set(5, at: "widgets.time.refreshInterval", in: &config)
    SettingsFixtures.set(nil, at: "widgets.time.clockDestination", in: &config)

    let (settings, repairs) = decodeSettings(config)

    XCTAssertEqual(settings.widgets.time.clockDestination, .timers)
    XCTAssertTrue(settings.widgets.time.showSeconds)
    XCTAssertEqual(settings.widgets.time.refreshInterval, 5)
    XCTAssertEqual(settings.schemaVersion, 1)
    XCTAssertTrue(repairs.isEmpty)
  }

  func testClockDestinationsRoundTripAndSelectTheExpectedSection() {
    for (destination, url) in [
      (TimeWidgetSettings.ClockDestination.timers, "clock-timer:default"),
      (.alarms, "clock-alarm:default"),
    ] {
      var saved = SettingsFixtures.settings()
      saved.widgets.time.clockDestination = destination
      saved.widgets.time.hour12 = true
      let (settings, repairs) = decodeSettings(SettingsFixtures.json(saved))
      XCTAssertEqual(settings.widgets.time, saved.widgets.time)
      XCTAssertEqual(settings.widgets.time.clockDestination.url.absoluteString, url)
      XCTAssertTrue(repairs.isEmpty)
    }

    var config = SettingsFixtures.json(SettingsFixtures.settings())
    SettingsFixtures.set(true, at: "widgets.time.hour12", in: &config)
    SettingsFixtures.set("unknown", at: "widgets.time.clockDestination", in: &config)
    let (settings, repairs) = decodeSettings(config)
    XCTAssertEqual(settings.widgets.time.clockDestination, .timers)
    XCTAssertTrue(settings.widgets.time.hour12)
    XCTAssertEqual(repairs.map { $0.path }, ["widgets.time.clockDestination"])
  }

  func testMissingWidgetFieldKeepsItsSiblings() {
    // Adding one field to a widget's settings used to silently reset that widget's whole
    // block, because a synthesized decoder treats a missing key as an error.
    var config = SettingsFixtures.json(SettingsFixtures.settings())
    SettingsFixtures.set(nil, at: "widgets.battery.showIcon", in: &config)

    let (settings, repairs) = decodeSettings(config)

    XCTAssertEqual(settings.widgets.battery.refreshInterval, 12)
    XCTAssertEqual(settings.widgets.battery.backgroundColor, .green)
    XCTAssertEqual(settings.widgets.battery.showIcon, BatteryWidgetSettings().showIcon)
    XCTAssertTrue(repairs.isEmpty, "filled from the defaults, no repair needed")
  }

  func testMissingSectionIsFilledFromDefaults() {
    var config = SettingsFixtures.json(SettingsFixtures.settings())
    config.removeValue(forKey: "theme")

    let (settings, repairs) = decodeSettings(config)

    XCTAssertEqual(settings.theme, ThemeSettings())
    XCTAssertEqual(settings.global.barHeight, 42)
    XCTAssertTrue(repairs.isEmpty)
  }

  func testUserWidgetMissingFieldIsFilledNotDropped() {
    var config = SettingsFixtures.json(SettingsFixtures.settings())
    SettingsFixtures.set(nil, at: "userWidgets.0.cycleDuration", in: &config)

    let (settings, repairs) = decodeSettings(config)

    XCTAssertEqual(settings.userWidgets.count, 1, "an older custom widget is not lost")
    XCTAssertEqual(settings.userWidgets.first?.name, "Disk")
    XCTAssertEqual(settings.userWidgets.first?.command, "df -h")
    XCTAssertEqual(settings.userWidgets.first?.cycleDuration, UserWidgetDefinition().cycleDuration)
    XCTAssertTrue(repairs.isEmpty)
  }

  func testUnusableUserWidgetFieldIsFilledWithoutLosingTheWidget() {
    var config = SettingsFixtures.json(SettingsFixtures.settings())
    SettingsFixtures.set(["not": "a string"], at: "userWidgets.0.command", in: &config)

    let (settings, repairs) = decodeSettings(config)

    XCTAssertEqual(settings.userWidgets.count, 1)
    XCTAssertEqual(settings.userWidgets.first?.name, "Disk", "the definition is kept to be fixed")
    XCTAssertEqual(settings.userWidgets.first?.command, UserWidgetDefinition().command)
    XCTAssertEqual(repairs.map { $0.action }, [.filledDefault])
  }

  func testUnusableArrayElementIsDroppedNotFabricated() {
    var config = SettingsFixtures.json(SettingsFixtures.settings())
    SettingsFixtures.set("garbage", at: "userWidgets.0", in: &config)

    let (settings, repairs) = decodeSettings(config)

    XCTAssertTrue(settings.userWidgets.isEmpty, "no phantom widget is invented")
    XCTAssertEqual(settings.global.barHeight, 42)
    XCTAssertEqual(repairs.map { $0.action }, [.droppedElement])
  }

  func testUnknownKeysAreIgnoredWithoutLoss() {
    var config = SettingsFixtures.json(SettingsFixtures.settings())
    config["somethingFromTheFuture"] = ["a": 1]
    SettingsFixtures.set(true, at: "widgets.battery.wipFlagFromADevBuild", in: &config)

    let (settings, repairs) = decodeSettings(config)

    XCTAssertTrue(repairs.isEmpty)
    XCTAssertEqual(settings.global.barHeight, 42)
    XCTAssertEqual(settings.widgets.battery.refreshInterval, 12)
  }

  // MARK: - Unusable documents

  func testTruncatedJSONIsUnreadable() {
    switch SettingsCodec.decode(Data("{ \"global\": ".utf8)) {
    case .unreadable:
      break
    case .ok:
      XCTFail("a truncated document must not be reported as loadable")
    }
  }

  func testNonObjectJSONIsUnreadable() {
    switch SettingsCodec.decode(Data("[1, 2, 3]".utf8)) {
    case .unreadable:
      break
    case .ok:
      XCTFail("a top-level array is not a config")
    }
  }

  // MARK: - Migration

  func testPreProfileConfigRecoversItsLayout() {
    // Before profiles existed the layout lived at the root. The commit that introduced
    // profiles dropped that key with no migration, silently resetting upgraders' layouts.
    var settings = SettingsFixtures.settings()
    let layout = settings.profiles[0].multiDisplayLayout
    settings.profiles = []
    settings.activeProfileId = nil

    var config = SettingsFixtures.json(settings)
    config.removeValue(forKey: "schemaVersion")
    config.removeValue(forKey: "profiles")
    config["multiDisplayLayout"] = SettingsFixtures.json(encoding: layout)

    let (decoded, _) = decodeSettings(config)

    XCTAssertEqual(decoded.profiles.count, 1)
    XCTAssertEqual(decoded.profiles[0].multiDisplayLayout, layout)
    XCTAssertTrue(decoded.profiles[0].isDefault)
    XCTAssertEqual(decoded.activeProfileId, decoded.profiles[0].id.uuidString)
    XCTAssertEqual(decoded.schemaVersion, SettingsCodec.currentSchemaVersion)
    XCTAssertEqual(decoded.global.barHeight, 42, "the rest of the old config survives")
  }

  func testCurrentConfigIsNotMigratedAgain() {
    let settings = SettingsFixtures.settings()
    let (decoded, repairs) = decodeSettings(SettingsFixtures.json(settings))

    XCTAssertTrue(repairs.isEmpty)
    XCTAssertEqual(decoded, settings)
  }

  func testDefaultsRoundTrip() {
    var defaults = ABarSettings()
    SettingsCodec.normalize(&defaults)

    let (decoded, repairs) = decodeSettings(SettingsFixtures.json(defaults))

    XCTAssertTrue(repairs.isEmpty)
    XCTAssertEqual(decoded, defaults)
  }

  // MARK: - Normalization

  private let intervalMinimums: [(WritableKeyPath<ABarSettings, TimeInterval>, TimeInterval)] = [
    (\.widgets.battery.refreshInterval, 1),
    (\.widgets.weather.refreshInterval, 60),
    (\.widgets.time.refreshInterval, 0.1),
    (\.widgets.date.refreshInterval, 1),
    (\.widgets.wifi.refreshInterval, 5),
    (\.widgets.wifi.scanInterval, 5),
    (\.widgets.bluetooth.refreshInterval, 1),
    (\.widgets.bluetooth.batteryRefreshInterval, 15),
    (\.widgets.sound.refreshInterval, 0.5),
    (\.widgets.mic.refreshInterval, 0.5),
    (\.widgets.keyboard.refreshInterval, 1),
    (\.widgets.github.refreshInterval, 60),
    (\.widgets.cpu.refreshInterval, 0.5),
    (\.widgets.memory.refreshInterval, 0.5),
    (\.widgets.gpu.refreshInterval, 0.5),
    (\.widgets.netstats.refreshInterval, 0.5),
    (\.widgets.diskActivity.refreshInterval, 0.5),
    (\.widgets.storage.refreshInterval, 10),
    (\.widgets.hackerNews.refreshInterval, 60),
    (\.widgets.hackerNews.rotationInterval, 1),
    (\.userWidgets[0].refreshInterval, 1),
    (\.userWidgets[0].cycleDuration, 1),
  ]

  func testAllIntervalsAreClampedWhenLoadingJSON() {
    for value in [-1.0, 0, 0.01] {
      var settings = ABarSettings()
      settings.userWidgets = [UserWidgetDefinition()]
      for (path, _) in intervalMinimums { settings[keyPath: path] = value }
      let (decoded, _) = decodeSettings(SettingsFixtures.json(settings))
      for (path, minimum) in intervalMinimums {
        XCTAssertEqual(decoded[keyPath: path], minimum, "\(path), input=\(value)")
      }
    }
  }

  func testNonfiniteIntervalsUseDefaultsAndRemainEncodable() {
    var defaults = ABarSettings()
    defaults.userWidgets = [UserWidgetDefinition()]
    for value in [TimeInterval.nan, .infinity, -.infinity] {
      var settings = defaults
      for (path, _) in intervalMinimums { settings[keyPath: path] = value }
      SettingsCodec.normalize(&settings)
      for (path, _) in intervalMinimums {
        XCTAssertEqual(settings[keyPath: path], defaults[keyPath: path], "\(path)")
      }
      XCTAssertNoThrow(try SettingsCodec.encode(settings))
    }
  }

  func testValidFractionalIntervalsArePreserved() {
    var settings = ABarSettings()
    settings.userWidgets = [UserWidgetDefinition()]
    for (path, minimum) in intervalMinimums { settings[keyPath: path] = minimum + 0.25 }
    SettingsCodec.normalize(&settings)
    for (path, minimum) in intervalMinimums {
      XCTAssertEqual(settings[keyPath: path], minimum + 0.25, "\(path)")
    }
  }


  func testOutOfRangeValuesAreClampedNotDefaulted() {
    var settings = ABarSettings()
    settings.global.barHeight = 500
    settings.global.barOpacity = -20
    settings.widgets.cpu.refreshInterval = 0.01

    SettingsCodec.normalize(&settings)

    XCTAssertEqual(settings.global.barHeight, 100, "clamped to the maximum, not reset to 34")
    XCTAssertEqual(settings.global.barOpacity, 0)
    XCTAssertEqual(settings.widgets.cpu.refreshInterval, 0.5)
  }

  func testDefaultsAreTakenFromThePropertyInitializers() {
    // The decoder fallback used to disagree with the property default (4 vs 8), so a fresh
    // install and an upgrade ended up with different padding.
    var config = SettingsFixtures.json(SettingsFixtures.settings())
    SettingsFixtures.set(nil, at: "global.barHorizontalPadding", in: &config)

    let (settings, _) = decodeSettings(config)

    XCTAssertEqual(settings.global.barHorizontalPadding, GlobalSettings().barHorizontalPadding)
  }
}
