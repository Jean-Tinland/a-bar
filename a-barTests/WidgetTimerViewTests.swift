// Purpose: Verify that mounted clock widgets immediately adopt a new refresh interval.
//
// Logic:
// 1. Mount a real TimeWidget in an offscreen window with a temporary settings file.
// 2. Confirm the display stays unchanged with a 60-second interval, then change it to 0.1 seconds.
// 3. Compare two subsequent frames to confirm that the seconds display keeps updating.
//
// Required input: TimeWidget and its dependencies in the test target.
// Expected output: XCTest results without reading the user configuration or using the network.
import AppKit
import SwiftUI
import XCTest

private final class WidgetClickTestPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}

final class WidgetTimerViewTests: XCTestCase {
  @MainActor
  func testBaseWidgetHandlesMouseClicksOnContentAndPadding() throws {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let settings = SettingsManager(store: SettingsStore(fileURL: directory.appendingPathComponent("settings.json")))
    for noPadding in [false, true] {
      var clicks = 0
      let host = NSHostingView(rootView:
        BaseWidgetView(width: 100, noPadding: noPadding, onClick: { clicks += 1 }) {
          Text("12:34").padding(.horizontal, 6).padding(.vertical, 4)
        }
        .environmentObject(settings)
        .frame(width: 100, height: 26))
      // Match the real bar's nonactivating panel; send events only to this offscreen test window.
      let window = WidgetClickTestPanel(
        contentRect: NSRect(x: -10000, y: -10000, width: 100, height: 26),
        styleMask: [.borderless, .nonactivatingPanel, .hudWindow], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.isMovableByWindowBackground = false
      window.becomesKeyOnlyIfNeeded = true
      window.contentView = host
      defer {
        window.contentView = nil
        window.close()
      }
      window.orderFront(nil)
      host.layoutSubtreeIfNeeded()
      RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
      for (index, point) in [NSPoint(x: 50, y: 13), NSPoint(x: 2, y: 13)].enumerated() {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
          let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: index + 1, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0))
          window.sendEvent(event)
          RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        XCTAssertEqual(clicks, index + 1, "a mouse click must fire once, including padded background; noPadding=\(noPadding)")
      }
    }
    settings.flush()
  }

  func testClockUpdatesOnlyWhenItsVisiblePrecisionRequiresIt() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
    let minute = try XCTUnwrap(calendar.date(from: DateComponents(
      year: 2026, month: 10, day: 1, hour: 23, minute: 59, second: 10)))
    var settings = TimeWidgetSettings()
    settings.showSeconds = false
    settings.showDayProgress = false
    for seconds in [0.1, 20, 49, -1] {
      XCTAssertFalse(TimeWidget.shouldUpdateTime(
        from: minute, to: minute.addingTimeInterval(seconds), settings: settings, calendar: calendar))
    }
    for seconds in [50.0, 60, 3600, 86400, -60, -3600, -86400] {
      XCTAssertTrue(TimeWidget.shouldUpdateTime(
        from: minute, to: minute.addingTimeInterval(seconds), settings: settings, calendar: calendar))
    }
    var displayed = minute
    var updates = 0
    for second in 1...60 {
      let next = minute.addingTimeInterval(Double(second))
      if TimeWidget.shouldUpdateTime(from: displayed, to: next, settings: settings, calendar: calendar) {
        displayed = next
        updates += 1
      }
    }
    XCTAssertEqual(updates, 1, "sixty timer ticks need only one minute-only state update")
    for (seconds, progress) in [(true, false), (false, true), (true, true)] {
      settings.showSeconds = seconds
      settings.showDayProgress = progress
      XCTAssertTrue(TimeWidget.shouldUpdateTime(
        from: minute, to: minute.addingTimeInterval(0.1), settings: settings, calendar: calendar))
    }
  }

  @MainActor
  func testHiddenCustomWidgetKeepsItsRefreshTimerWithoutLeavingAGap() async throws {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let settings = SettingsManager(store: SettingsStore(fileURL: directory.appendingPathComponent("settings.json")))
    let marker = directory.appendingPathComponent("runs")
    let inactiveMarker = directory.appendingPathComponent("inactive-runs")
    let definition = UserWidgetDefinition(
      command: "printf x >> '" + marker.path + "'", refreshInterval: 1, hideWhenEmpty: true)
    let inactive = UserWidgetDefinition(
      command: "printf x >> '" + inactiveMarker.path + "'", refreshInterval: 1, isActive: false)
    // Widgets sit in a spaced stack in the bar; one that renders nothing must not take a slot.
    let host = NSHostingView(rootView: HStack(spacing: 10) {
      Color.clear.frame(width: 20, height: 10)
      UserWidget(config: definition)
      UserWidget(config: inactive)
      Color.clear.frame(width: 20, height: 10)
    }.environmentObject(settings))
    let window = NSWindow(
      contentRect: NSRect(x: -10000, y: -10000, width: 200, height: 40),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer {
      window.contentView = nil
      window.close()
      settings.flush()
    }
    host.layoutSubtreeIfNeeded()
    // Empty stdout hides the content after the first run; the next timer must still fire.
    try await Task.sleep(nanoseconds: 2_500_000_000)
    host.layoutSubtreeIfNeeded()
    XCTAssertEqual(host.fittingSize.width, 50, accuracy: 0.5,
                   "hidden and inactive custom widgets must not add a gap to the bar")
    XCTAssertGreaterThanOrEqual(try Data(contentsOf: marker).count, 2)
    XCTAssertFalse(FileManager.default.fileExists(atPath: inactiveMarker.path),
                   "an inactive custom widget must not run its command")
  }

  @MainActor
  func testRemovedCustomWidgetStopsPolling() async throws {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let settings = SettingsManager(store: SettingsStore(fileURL: directory.appendingPathComponent("settings.json")))
    let marker = directory.appendingPathComponent("runs")
    let definition = UserWidgetDefinition(
      command: "printf x >> '" + marker.path + "'", refreshInterval: 1, hideWhenEmpty: true)
    let host = NSHostingView(rootView: AnyView(UserWidget(config: definition).environmentObject(settings)))
    let window = NSWindow(
      contentRect: NSRect(x: -10000, y: -10000, width: 200, height: 40),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer {
      window.contentView = nil
      window.close()
      settings.flush()
    }
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(nanoseconds: 1_300_000_000)
    XCTAssertGreaterThanOrEqual(try Data(contentsOf: marker).count, 2)

    // Polling is tied to the widget's identity, not to it appearing, so removal must end it.
    host.rootView = AnyView(EmptyView())
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(nanoseconds: 300_000_000)
    let runsAtRemoval = try Data(contentsOf: marker).count
    try await Task.sleep(nanoseconds: 1_500_000_000)
    XCTAssertEqual(try Data(contentsOf: marker).count, runsAtRemoval)
  }

  @MainActor
  func testMountedClockUsesChangedRefreshInterval() throws {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let config = directory.appendingPathComponent("settings.json")
    var initial = ABarSettings()
    initial.widgets.time.refreshInterval = 60
    initial.widgets.time.showSeconds = true
    initial.widgets.time.showIcon = false
    initial.widgets.time.showDayProgress = false
    try SettingsCodec.encode(initial).write(to: config)
    let settings = SettingsManager(store: SettingsStore(fileURL: config))
    let host = NSHostingView(rootView: TimeWidget().environmentObject(settings))
    let window = NSWindow(
      contentRect: NSRect(x: -10000, y: -10000, width: 200, height: 40),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer {
      window.contentView = nil
      window.close()
      settings.flush()
    }

    func snapshot() throws -> Data {
      host.layoutSubtreeIfNeeded()
      let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }

    _ = try snapshot()
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
    let slowFrame = try snapshot()
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.2))
    XCTAssertEqual(try snapshot(), slowFrame, "the initial 60-second timer should not tick")

    settings.update { $0.widgets.time.refreshInterval = 0.1 }
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
    let fastFrame = try snapshot()
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.2))
    XCTAssertNotEqual(
      try snapshot(), fastFrame,
      "the mounted clock must keep ticking after its refresh interval changes")
  }
}
