// 代码目的：
// 验证时钟刷新周期及自定义组件的轮询生命周期。
//
// 代码逻辑：
// 1. 使用临时配置，在离屏窗口挂载真实组件。
// 2. 检查时钟周期、隐藏布局以及删除、停用和替换后的停机。
// 3. 通过脚本计数和布局探针验证任务取消及排队刷新。
//
// 必需输入：
// - 测试 target 中的 TimeWidget、UserWidget 及其依赖。
//
// 预期输出：
// - 不读取用户配置、不访问网络的 XCTest 验证结果。
import AppKit
import SwiftUI
import XCTest

final class WidgetTimerViewTests: XCTestCase {
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
  func testBarUpdatesStopPreviousCustomWidgetRunner() async throws {
    _ = NSApplication.shared
    for update in ["remove", "deactivate", "replaceCommand"] {
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: directory) }
      let settings = SettingsManager(store: SettingsStore(fileURL: directory.appendingPathComponent("settings.json")))
      let marker = directory.appendingPathComponent("old-runs")
      let replacementMarker = directory.appendingPathComponent("new-runs")
      let definition = UserWidgetDefinition(
        command: "printf x >> '" + marker.path + "'", refreshInterval: 1, hideWhenEmpty: true)
      let state = CustomWidgetBarFixtureState(widgets: [definition])
      let host = NSHostingView(rootView: CustomWidgetBarFixture(state: state).environmentObject(settings))
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
      XCTAssertGreaterThanOrEqual(try Data(contentsOf: marker).count, 2, update)
      XCTAssertEqual(host.fittingSize.width, 50, accuracy: 0.5, update)

      var changed = definition
      switch update {
      case "remove": state.widgets = []
      case "deactivate":
        changed.isActive = false
        state.widgets = [changed]
      default:
        changed.command = "printf x >> '" + replacementMarker.path + "'"
        state.widgets = [changed]
      }
      state.revision += 1
      try await Task.sleep(nanoseconds: 300_000_000)
      host.layoutSubtreeIfNeeded()
      // This changed width proves the stable host consumed the update, even for empty content.
      XCTAssertEqual(host.fittingSize.width, 51, accuracy: 0.5, update)
      let runsAtUpdate = try Data(contentsOf: marker).count
      NotificationCenter.default.post(
        name: .refreshUserWidget, object: nil, userInfo: ["widgetId": definition.id])
      try await Task.sleep(nanoseconds: 1_500_000_000)
      XCTAssertEqual(try Data(contentsOf: marker).count, runsAtUpdate, update)
      if update == "replaceCommand" {
        XCTAssertGreaterThanOrEqual(try Data(contentsOf: replacementMarker).count, 2)
      }
    }
  }

  @MainActor
  func testRemovedCustomWidgetDoesNotStartAnAlreadyCancelledTask() async throws {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let settings = SettingsManager(store: SettingsStore(fileURL: directory.appendingPathComponent("settings.json")))
    let marker = directory.appendingPathComponent("runs")
    let definition = UserWidgetDefinition(command: "printf x >> '" + marker.path + "'", refreshInterval: 1)
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
    // Stay on the main actor until removal, so the newly queued refresh Task cannot start.
    host.rootView = AnyView(EmptyView())
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(nanoseconds: 300_000_000)
    XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
  }

  @MainActor
  func testReplacedCustomWidgetDoesNotResumeItsQueuedRefresh() async throws {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let settings = SettingsManager(store: SettingsStore(fileURL: directory.appendingPathComponent("settings.json")))
    let oldMarker = directory.appendingPathComponent("old-runs")
    let newMarker = directory.appendingPathComponent("new-runs")
    let gate = directory.appendingPathComponent("release")
    let finished = directory.appendingPathComponent("old-finished")
    // Bound the shell wait so an assertion failure cannot leave a test process running forever.
    let command = "printf x >> '" + oldMarker.path
      + "'; tries=0; while [ ! -f '" + gate.path
      + "' ] && [ $tries -lt 100 ]; do sleep 0.05; tries=$((tries+1)); done; printf x >> '"
      + finished.path + "'"
    let definition = UserWidgetDefinition(command: command, refreshInterval: 1, hideWhenEmpty: true)
    let state = CustomWidgetBarFixtureState(widgets: [definition])
    let host = NSHostingView(rootView: CustomWidgetBarFixture(state: state).environmentObject(settings))
    let window = NSWindow(
      contentRect: NSRect(x: -10000, y: -10000, width: 200, height: 40),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer {
      try? Data().write(to: gate)
      window.contentView = nil
      window.close()
      settings.flush()
    }

    func waitForFile(_ url: URL) async throws {
      let deadline = Date(timeIntervalSinceNow: 2)
      while !FileManager.default.fileExists(atPath: url.path), Date() < deadline {
        try await Task.sleep(nanoseconds: 20_000_000)
      }
      XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), url.lastPathComponent)
    }

    host.layoutSubtreeIfNeeded()
    try await waitForFile(oldMarker)
    XCTAssertFalse(FileManager.default.fileExists(atPath: finished.path))
    // Queue one more refresh while the old command is still blocked at the gate.
    NotificationCenter.default.post(
      name: .refreshUserWidget, object: nil, userInfo: ["widgetId": definition.id])
    var changed = definition
    changed.command = "printf x >> '" + newMarker.path + "'"
    state.widgets = [changed]
    state.revision += 1
    try await Task.sleep(nanoseconds: 300_000_000)
    host.layoutSubtreeIfNeeded()
    XCTAssertEqual(host.fittingSize.width, 51, accuracy: 0.5)
    try await waitForFile(newMarker)
    XCTAssertFalse(FileManager.default.fileExists(atPath: finished.path),
                   "the old command must still be in flight when its replacement starts")
    try Data().write(to: gate)
    try await waitForFile(finished)
    try await Task.sleep(nanoseconds: 1_500_000_000)
    XCTAssertEqual(try Data(contentsOf: oldMarker).count, 1,
                   "a cancelled result must not restart the old queued command")
    XCTAssertGreaterThanOrEqual(try Data(contentsOf: newMarker).count, 2)
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

private final class CustomWidgetBarFixtureState: ObservableObject {
  @Published var widgets: [UserWidgetDefinition]
  @Published var revision = 0

  init(widgets: [UserWidgetDefinition]) { self.widgets = widgets }
}

private struct CustomWidgetBarFixture: View {
  @ObservedObject var state: CustomWidgetBarFixtureState

  var body: some View {
    HStack(spacing: 10) {
      Color.clear.frame(width: CGFloat(20 + state.revision), height: 10)
      ForEach(state.widgets) { definition in
        UserWidget(config: definition).id(UserWidgetRunner.Identity(definition))
      }
      Color.clear.frame(width: 20, height: 10)
    }
  }
}
