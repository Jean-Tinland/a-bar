import AppKit
import Combine
import SwiftUI
import XCTest
import Darwin
import ApplicationServices

/// Window and Space events arrive in bursts, and each one used to start its own overlapping
/// set of yabai queries. A burst has to collapse into one active batch plus a single
/// follow-up. Full snapshots publish atomically; title updates may reuse cached Spaces and
/// displays only while their window relationships remain unchanged. A stopped or repointed
/// generation must never write over a newer one.
///
/// A temporary stand-in for the yabai binary returns fixed JSON on demand, so these tests can
/// count queries and watch what gets published without touching the real desktop, the user's
/// config, or the yabai signals they already have registered.
final class YabaiServiceTests: XCTestCase {
    private var directory: URL!
    private var service: YabaiService!
    private var manager: SettingsManager!
    private var notificationName: String!
    private var observations = Set<AnyCancellable>()
    private var activeServiceDirectory: URL?
    private var expectedRemovals: [URL: Int] = [:]
    private let notifications = NotificationCenter()

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("abar-refresh-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("yabai")
        try """
        #!/bin/sh
        # Stands in for yabai, so nothing here reaches the real one. Logs every call, holds
        # each query at the test's gate file, then prints the fixture for the collection asked
        # for. Reads the JSON fixtures beside it; writes the call log next to them.
        root=${0%/*}
        trap 'printf "%s\\n" "$*" >> "$root/completed"' EXIT
        printf '%s\\n' "$2 $3" >> "$root/calls"
        printf '%s\\n' "$*" >> "$root/arguments"
        printf '%s\\n' "$*" >> "$root/started"
        if [ "$2" = query ]; then
          while [ -f "$root/hold" ]; do sleep 0.01; done
          sleep 0.02
          if [ -f "$root/reject-projection" ] && [ "$4" != --window ] && [ -n "$4" ]; then
            printf "unknown option '%s'\\n" "$4" >&2
            exit 1
          fi
          case "$*" in
            *" --window "*|*" --window") cat "$root/single-window.json" ;;
            *) cat "$root/$3.json" ;;
          esac
        elif [ "$3" = --list ]; then
          if [ -f "$root/signals.json" ]; then cat "$root/signals.json"; else printf '[]\\n'; fi
        elif [ "$2" != signal ]; then
          while [ -f "$root/hold-mutation" ]; do sleep 0.01; done
          if [ -f "$root/fail-command" ] && [ "$(cat "$root/fail-command")" = "$2" ]; then
            printf 'fixture mutation failed\\n' >&2
            exit 1
          fi
        fi
        """.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        try write("calls", "")
        try write("--spaces.json", #"[{"id":1,"index":1,"display":1,"type":"bsp","windows":[10],"has-focus":true}]"#)
        try write("--windows.json", #"[{"id":10,"pid":123,"app":"Fixture","title":"Example","display":1,"space":1,"subrole":"AXStandardWindow","frame":{"x":0,"y":0,"w":100,"h":100},"has-focus":true}]"#)
        try write("--displays.json", #"[{"id":1,"uuid":"fixture","index":1,"frame":{"x":0,"y":0,"w":1920,"h":1080},"spaces":[1],"has-focus":true}]"#)
        var settings = ABarSettings()
        settings.global.yabaiPath = executable.path
        let config = directory.appendingPathComponent("config.json")
        try SettingsCodec.encode(settings).write(to: config)
        manager = SettingsManager(store: SettingsStore(fileURL: config))
        notificationName = "user.uid.\(getuid()).a-bar-test.\(UUID())"
        service = YabaiService(
            settingsManager: manager,
            refreshNotification: notificationName, windowEvents: nil, workspaceNotifications: notifications, screenNotifications: notifications, frontmostPID: { 123 })
    }

    override func tearDownWithError() throws {
        observations.removeAll()
        stopService()
        // Release blocked reads before waiting; stopped generations must finish without publishing.
        for root in fixtureDirectories {
            try? FileManager.default.removeItem(at: root.appendingPathComponent("hold"))
            try? FileManager.default.removeItem(at: root.appendingPathComponent("hold-mutation"))
        }
        let cleaned = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                self.signalCleanupComplete && self.fixtureDirectories.allSatisfy { root in
                    self.log("started", at: root).count == self.log("completed", at: root).count
                }
            }, object: nil)
        wait(for: [cleaned], timeout: 3)
        manager.flush()
        service = nil
        try FileManager.default.removeItem(at: directory)
        activeServiceDirectory = nil
        expectedRemovals.removeAll()
    }

    private var fixtureDirectories: Set<URL> {
        Set(expectedRemovals.keys).union([directory.standardizedFileURL])
    }

    private func log(_ name: String, at root: URL) -> [String] {
        ((try? String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)) ?? "")
            .split(separator: "\n").map(String.init)
    }

    private var signalCleanupComplete: Bool {
        expectedRemovals.allSatisfy { root, count in
            log("completed", at: root).filter { $0.hasPrefix("-m signal --remove ") }.count >= count
        }
    }

    private func expectSignalCleanup(at root: URL) {
        let completed = log("completed", at: root).filter { $0.hasPrefix("-m signal --remove ") }.count
        expectedRemovals[root] = max(expectedRemovals[root, default: 0], completed) + 7
    }

    private func startService() {
        let root = URL(fileURLWithPath: manager.settings.global.yabaiPath)
            .deletingLastPathComponent().standardizedFileURL
        if let previous = activeServiceDirectory, previous != root {
            expectSignalCleanup(at: previous)
        }
        activeServiceDirectory = root
        service.start()
    }

    private func stopService() {
        if let root = activeServiceDirectory {
            expectSignalCleanup(at: root)
            activeServiceDirectory = nil
        }
        service.stop()
    }

    private func write(_ name: String, _ value: String) throws {
        try value.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    private var calls: [String] {
        ((try? String(contentsOf: directory.appendingPathComponent("calls"), encoding: .utf8)) ?? "")
            .split(separator: "\n").map(String.init)
    }

    private var queries: [String] { calls.filter { $0.hasPrefix("query ") } }

    private var arguments: [String] {
        ((try? String(contentsOf: directory.appendingPathComponent("arguments"), encoding: .utf8)) ?? "")
            .split(separator: "\n").map(String.init)
    }

    private func readFixture(_ name: String) throws -> [[String: Any]] {
        let data = try Data(contentsOf: directory.appendingPathComponent(name))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    }

    private func writeFixture(_ name: String, _ value: [[String: Any]]) throws {
        let data = try JSONSerialization.data(withJSONObject: value)
        try write(name, String(decoding: data, as: UTF8.self))
    }

    @MainActor
    private func postRefresh(titleOnly: Bool) async throws {
        let name = titleOnly ? notificationName + ".window-title-changed" : notificationName!
        try await ShellExecutor.run(executable: "/usr/bin/notifyutil", arguments: ["-p", name])
    }

    @MainActor
    private func startAndClearCalls() async throws {
        startService()
        await waitFor { service.isConnected && service.signalsRegistered }
        try write("calls", "")
        try write("arguments", "")
    }

    private func registeredMoveNotification() throws -> String {
        notificationName + ".window-moved"
    }

    private func postNotification(_ name: String) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(name as CFString), nil, nil, true)
    }

    @MainActor
    private func stopAndWait() async {
        stopService()
        await waitFor { signalCleanupComplete }
    }

    @MainActor
    func testSuccessfulMutationsPublishFreshSnapshotWithoutExternalEvents() async throws {
        try await startAndClearCalls()
        let mutations: [() async -> Void] = [
            { await self.service.goToSpace(1) },
            { await self.service.renameSpace(1, label: "Renamed") },
            { await self.service.createSpace(onDisplay: 1) },
            { await self.service.removeSpace(1, onDisplay: 1) },
            { await self.service.swapSpace(1, direction: .right) },
            { await self.service.focusWindow(10) },
        ]
        for (index, mutate) in mutations.enumerated() {
            let label = "Result \(index)"
            var spaces = try readFixture("--spaces.json")
            spaces[0]["label"] = label
            try writeFixture("--spaces.json", spaces)
            await mutate()
            await waitFor { service.state.spaces.first?.label == label }
        }
    }

    @MainActor
    func testFailedMutationsKeepSnapshotAndDoNotRefresh() async throws {
        try await startAndClearCalls()
        let original = service.state
        try write("fail-command", "space")
        await service.renameSpace(1, label: "Failed")
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNotNil(service.lastError)
        XCTAssertEqual(service.state, original)
        XCTAssertTrue(queries.isEmpty)

        try write("fail-command", "display")
        await service.createSpace(onDisplay: 1)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(service.state, original)
        XCTAssertTrue(queries.isEmpty)
        XCTAssertFalse(arguments.contains("-m space --create"))
    }

    @MainActor
    func testMutationFromOldGenerationDoesNotRefreshRestartedService() async throws {
        try await startAndClearCalls()
        try write("hold-mutation", "")
        let mutation = Task { await service.renameSpace(1, label: "Old") }
        await waitFor { arguments.contains("-m space 1 --label Old") }
        var spaces = try readFixture("--spaces.json")
        spaces[0]["label"] = "Restarted"
        try writeFixture("--spaces.json", spaces)
        stopService()
        startService()
        await waitFor { service.signalsRegistered && service.state.spaces.first?.label == "Restarted" }
        let queryCount = queries.count
        try FileManager.default.removeItem(at: directory.appendingPathComponent("hold-mutation"))
        await mutation.value
        // Let any incorrectly queued follow-up reach the fixture CLI.
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(queries.count, queryCount)
    }

    @MainActor
    private func waitFor(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(3)
        while !condition() && Date() < deadline { try? await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertTrue(condition(), "condition did not become true", file: file, line: line)
    }

    @MainActor
    func testProcessLabelsFollowEventsAndKeepFocusedStickyWindowsAcrossSpaces() async throws {
        _ = NSApplication.shared
        manager.update {
            $0.widgets.process.displayOnlyIcon = true
            $0.widgets.process.showLayoutMode = true
            $0.widgets.process.layoutModeUsesIcon = false
            $0.widgets.process.spaceLayoutDisplay = .text
        }
        var fixture = try readFixture("--windows.json")
        fixture[0]["space"] = 2
        fixture[0]["is-floating"] = true
        fixture[0]["is-sticky"] = true
        try writeFixture("--windows.json", fixture)
        try await startAndClearCalls()
        let host = NSHostingView(rootView: ProcessWidget()
            .environmentObject(manager).environmentObject(service)
            .fixedSize(horizontal: true, vertical: false).frame(height: 30))
        let window = NSWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: 400, height: 30),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        func renderedWidth() -> CGFloat {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
            host.layoutSubtreeIfNeeded()
            return host.fittingSize.width
        }
        let bothLabels = renderedWidth()
        XCTAssertGreaterThan(bothLabels, 80,
            "a focused sticky window on another Space must show its icon and both labels")
        XCTAssertTrue(queries.isEmpty, "rendering labels must not start extra yabai queries")
        manager.update { $0.widgets.process.layoutModeUsesIcon = true }
        let layoutIcon = renderedWidth()
        XCTAssertLessThan(layoutIcon, bothLabels - 5, "the focused float label switches from text to an icon")
        manager.update { $0.widgets.process.layoutModeUsesIcon = false }
        XCTAssertEqual(renderedWidth(), bothLabels, accuracy: 0.5)

        manager.update { $0.widgets.process.showLayoutMode = false }
        let stickyOnly = renderedWidth()
        XCTAssertLessThan(stickyOnly, bothLabels - 10)
        XCTAssertGreaterThan(stickyOnly, 45, "sticky remains visible in icon-only mode")
        XCTAssertEqual(service.state.focusedSpace?.type, .bsp)
        XCTAssertEqual(service.state.focusedWindow?.layoutLabel, "float")
        manager.update { $0.widgets.process.spaceLayoutDisplay = .off }
        let noSpaceBadge = renderedWidth()
        XCTAssertGreaterThan(noSpaceBadge, 45, "sticky remains visible with the independent Space badge off")
        XCTAssertLessThan(noSpaceBadge, stickyOnly - 10, "the independent Space badge can be hidden")
        manager.update { $0.widgets.process.spaceLayoutDisplay = .icon }
        let spaceIcon = renderedWidth()
        XCTAssertGreaterThan(spaceIcon, noSpaceBadge + 5, "the Space icon remains when the focused layout badge is off")
        XCTAssertLessThan(spaceIcon, stickyOnly - 5, "Space text and icon are separate display modes")
        manager.update { $0.widgets.process.spaceLayoutDisplay = .text }
        XCTAssertEqual(renderedWidth(), stickyOnly, accuracy: 0.5)
        XCTAssertTrue(queries.isEmpty, "badge settings must not introduce data reads")

        // Change the fixture without an event: the view must keep the published snapshot.
        fixture[0]["is-sticky"] = false
        try writeFixture("--windows.json", fixture)
        XCTAssertEqual(renderedWidth(), stickyOnly, accuracy: 0.5)
        XCTAssertTrue(queries.isEmpty, "no polling is introduced by the labels")
        try await postRefresh(titleOnly: false)
        await waitFor { service.state.focusedWindow?.isSticky == false }
        XCTAssertLessThan(renderedWidth(), stickyOnly - 10)

        // A subsequent focus/state event publishes the new mode through the same service.
        fixture[0]["space"] = 1
        fixture[0]["is-floating"] = false
        fixture[0]["stack-index"] = 2
        try writeFixture("--windows.json", fixture)
        manager.update { $0.widgets.process.showLayoutMode = true }
        try await postRefresh(titleOnly: false)
        await waitFor { service.state.focusedWindow?.layoutLabel == "stack" }
        XCTAssertGreaterThan(renderedWidth(), 65)

        // An unknown current Space keeps the existing Desktop presentation, including
        // when a sticky window still reports focus in the same complete snapshot.
        fixture[0]["is-sticky"] = true
        try writeFixture("--windows.json", fixture)
        var spaces = try readFixture("--spaces.json")
        spaces[0]["has-focus"] = false
        try writeFixture("--spaces.json", spaces)
        service.refresh()
        await waitFor { service.state.focusedSpace == nil }
        XCTAssertLessThan(renderedWidth(), 40)
        await stopAndWait()
    }

    @MainActor
    func testManualRefreshBeforeStartDoesNotReadOrRegisterSignals() async throws {
        service.refresh()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(calls.isEmpty)
        XCTAssertEqual(service.state, YabaiState())
        XCTAssertFalse(service.isConnected)
        XCTAssertFalse(service.signalsRegistered)
    }

    @MainActor
    func testQueriesRunConcurrentlyAndBurstPublishesOneCompleteSnapshot() async throws {
        try write("hold", "")
        var states: [YabaiState] = []
        service.$state.dropFirst().sink { states.append($0) }.store(in: &observations)
        startService()
        await waitFor { queries.count == 3 }
        // All three processes reached the gate before any one was allowed to finish.
        XCTAssertTrue(states.isEmpty)
        for _ in 0..<20 { service.refresh() }
        await Task.yield()
        try FileManager.default.removeItem(at: directory.appendingPathComponent("hold"))
        await waitFor { queries.count == 6 && service.isConnected }
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(queries.count, 6, "one active batch plus one latest follow-up")
        XCTAssertEqual(states.count, 1, "identical snapshots must not invalidate every widget")
        XCTAssertEqual(states.first?.spaces.count, 1)
        XCTAssertEqual(states.first?.windows.count, 1)
        XCTAssertEqual(states.first?.displays.count, 1)
    }

    @MainActor
    func testMoveBurstFetchesOneLatestSnapshotAfterDraggingStops() async throws {
        startService()
        await waitFor { service.isConnected && service.signalsRegistered }
        let notification = try registeredMoveNotification()
        try write("calls", "")
        var publications = 0
        service.$state.dropFirst().sink { _ in publications += 1 }.store(in: &observations)
        var windows = try readFixture("--windows.json")
        for step in 1...20 {
            windows[0]["frame"] = ["x": step * 10, "y": 0, "w": 100, "h": 100]
            try writeFixture("--windows.json", windows)
            postNotification(notification)
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let queriesDuringDrag = queries.count
        windows[0]["display"] = 2
        windows[0]["space"] = 2
        try writeFixture("--windows.json", windows)
        var spaces = try readFixture("--spaces.json")
        spaces[0]["id"] = 2
        spaces[0]["index"] = 2
        spaces[0]["display"] = 2
        try writeFixture("--spaces.json", spaces)
        var displays = try readFixture("--displays.json")
        displays[0]["id"] = 2
        displays[0]["index"] = 2
        displays[0]["spaces"] = [2]
        try writeFixture("--displays.json", displays)
        let stoppedAt = Date()
        postNotification(notification)
        await waitFor { service.state.focusedWindow?.display == 2 }
        try await Task.sleep(nanoseconds: 120_000_000)
        print("Move burst: during=\(queriesDuringDrag), total=\(queries.count), publications=\(publications), settled=\(Date().timeIntervalSince(stoppedAt))s")
        XCTAssertEqual(queriesDuringDrag, 0, "moving continuously must not run full queries for every frame")
        XCTAssertEqual(queries.count, 3, "one full snapshot after the burst, including Space/display changes")
        XCTAssertEqual(publications, 1, "do not invalidate the bar for each intermediate frame")
        XCTAssertEqual(service.state.spaces.first?.id, 2)
        XCTAssertEqual(service.state.displays.first?.index, 2)
        await stopAndWait()
    }

    @MainActor
    func testFocusRefreshSupersedesMoveDelayWithoutASecondQueryBatch() async throws {
        startService()
        await waitFor { service.isConnected && service.signalsRegistered }
        let move = try registeredMoveNotification()
        try write("calls", "")
        postNotification(move)
        try await Task.sleep(nanoseconds: 30_000_000)
        var windows = try readFixture("--windows.json")
        windows[0]["title"] = "Urgent focus"
        try writeFixture("--windows.json", windows)
        let requestedAt = Date()
        postNotification(notificationName)
        await waitFor { queries.count >= 3 }
        let elapsed = Date().timeIntervalSince(requestedAt)
        XCTAssertLessThan(elapsed, 0.09, "focus must bypass the 300ms movement delay")
        await waitFor { service.state.focusedWindow?.title == "Urgent focus" }
        try await Task.sleep(nanoseconds: 350_000_000)
        XCTAssertEqual(queries.count, 3, "the urgent full snapshot supersedes the deferred move")
        await stopAndWait()
    }

    @MainActor
    func testSparseMoveDeliveryStillCoalescesDuringContinuousDragging() async throws {
        startService()
        await waitFor { service.isConnected && service.signalsRegistered }
        let move = try registeredMoveNotification()
        try write("calls", "")
        var windows = try readFixture("--windows.json")
        // Real AX delivery was 140-290ms apart; a 100ms debounce fires between these events.
        for step in 1...6 {
            windows[0]["frame"] = ["x": step * 10, "y": 0, "w": 100, "h": 100]
            try writeFixture("--windows.json", windows)
            postNotification(move)
            try await Task.sleep(nanoseconds: 160_000_000)
        }
        XCTAssertTrue(queries.isEmpty, "coalesced AX delivery must not look like six separate completed drags")
        await waitFor { service.state.focusedWindow?.frame.x == 60 }
        XCTAssertEqual(queries.count, 3)
        await stopAndWait()
    }

    @MainActor
    func testPendingMoveStopsAndCannotRefreshANewGeneration() async throws {
        startService()
        await waitFor { service.isConnected && service.signalsRegistered }
        let move = try registeredMoveNotification()
        try write("calls", "")
        postNotification(move)
        try await Task.sleep(nanoseconds: 30_000_000)
        await stopAndWait()
        let stoppedState = service.state
        postNotification(move)
        try await Task.sleep(nanoseconds: 350_000_000)
        XCTAssertTrue(queries.isEmpty, "stopping cancels and unregisters delayed movement work")
        XCTAssertEqual(service.state, stoppedState)

        try write("calls", "")
        startService()
        await waitFor { service.isConnected && service.signalsRegistered }
        try await Task.sleep(nanoseconds: 350_000_000)
        XCTAssertEqual(queries.count, 3, "the old deferred callback cannot add a batch after restart")
        await stopAndWait()
    }

    @MainActor
    func testChangingPathWhileMoveIsPendingOnlyReadsTheNewSource() async throws {
        startService()
        await waitFor { service.isConnected && service.signalsRegistered }
        let move = try registeredMoveNotification()
        try write("calls", "")
        postNotification(move)
        try await Task.sleep(nanoseconds: 30_000_000)
        let other = directory.appendingPathComponent("new-move-source")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        for name in ["yabai", "--spaces.json", "--windows.json", "--displays.json"] {
            try FileManager.default.copyItem(at: directory.appendingPathComponent(name), to: other.appendingPathComponent(name))
        }
        manager.update { $0.global.yabaiPath = other.appendingPathComponent("yabai").path }
        startService()
        await waitFor { service.isConnected && service.signalsRegistered }
        try await Task.sleep(nanoseconds: 350_000_000)
        XCTAssertTrue(queries.isEmpty, "the old source's pending move must be cancelled")
        XCTAssertEqual(log("calls", at: other).filter { $0.hasPrefix("query ") }.count, 3)
        await stopAndWait()
    }

    @MainActor
    func testFailureKeepsCompleteStateAndEqualSuccessRestoresConnection() async throws {
        startService()
        await waitFor { service.isConnected }
        let original = service.state
        let windows = try String(contentsOf: directory.appendingPathComponent("--windows.json"), encoding: .utf8)
        try write("--windows.json", "invalid JSON")
        service.refresh()
        await waitFor { service.lastError != nil }
        XCTAssertFalse(service.isConnected)
        XCTAssertEqual(service.state, original)
        try write("--windows.json", windows)
        service.refresh()
        await waitFor { service.isConnected && service.lastError == nil }
        XCTAssertEqual(service.state, original)
    }

    @MainActor
    func testValidJSONPreservesCombiningMarksAndLiteralRepairPatterns() async throws {
        let title = "\u{301}[,] 00000 \"quoted\" \\path\nnext"
        let data = try Data(contentsOf: directory.appendingPathComponent("--windows.json"))
        var windows = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        windows[0]["title"] = title
        let output = try JSONSerialization.data(withJSONObject: windows)
        try write("--windows.json", String(decoding: output, as: UTF8.self))
        startService()
        await waitFor { service.isConnected }
        XCTAssertEqual(service.state.windows.first?.title, title)
    }

    @MainActor
    func testMalformedLegacyArraysStillUseTheSanitizer() async throws {
        let output = try String(contentsOf: directory.appendingPathComponent("--windows.json"), encoding: .utf8)
        try write("--windows.json", "[," + output.dropFirst().dropLast() + ",]")
        startService()
        await waitFor { service.isConnected }
        XCTAssertEqual(service.state.windows.count, 1)
        XCTAssertEqual(service.state.windows.first?.title, "Example")
    }

    @MainActor
    func testStoppedGenerationCannotPublishItsResult() async throws {
        try write("hold", "")
        startService()
        await waitFor { queries.count == 3 }
        stopService()
        try FileManager.default.removeItem(at: directory.appendingPathComponent("hold"))
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(service.state, YabaiState())
        XCTAssertFalse(service.isConnected)
        let stoppedQueryCount = queries.count
        service.refresh()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(queries.count, stoppedQueryCount, "manual refresh cannot reactivate a stopped service")
        startService()
        await waitFor { service.isConnected && service.signalsRegistered }
        await waitFor { signalCleanupComplete }
    }

    @MainActor
    func testRepeatedStartDoesNotDuplicateSpaceObserver() async throws {
        startService()
        startService()
        await waitFor { service.isConnected && service.signalsRegistered }
        XCTAssertEqual(queries.count, 3)
        try write("calls", "")
        notifications.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        await waitFor { queries.count >= 3 }
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(queries.count, 3)
        stopService()
        await waitFor { signalCleanupComplete }
    }

    @MainActor
    func testNativeNotificationRefreshesAndQuickRestartKeepsSignals() async throws {
        startService()
        await waitFor { service.isConnected && service.signalsRegistered }
        stopService()
        startService()
        await waitFor { service.signalsRegistered }
        let lastRemove = calls.lastIndex(of: "signal --remove")
        let lastAdd = calls.lastIndex(of: "signal --add")
        XCTAssertNotNil(lastRemove)
        XCTAssertNotNil(lastAdd)
        if let lastRemove, let lastAdd { XCTAssertLessThan(lastRemove, lastAdd) }
        try await Task.sleep(nanoseconds: 100_000_000)
        try write("calls", "")
        try await ShellExecutor.run("/usr/bin/notifyutil -p \(notificationName!)")
        await waitFor { queries.count >= 3 }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(queries.count, 3)
        stopService()
        await waitFor { signalCleanupComplete }
    }

    @MainActor
    func testNewYabaiPathDoesNotWaitForOrPublishOldInFlightQuery() async throws {
        startService()
        await waitFor { service.isConnected && service.signalsRegistered }
        let other = directory.appendingPathComponent("new")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        for name in ["yabai", "--spaces.json", "--windows.json", "--displays.json"] {
            try FileManager.default.copyItem(at: directory.appendingPathComponent(name), to: other.appendingPathComponent(name))
        }
        let windows = other.appendingPathComponent("--windows.json")
        try String(contentsOf: windows, encoding: .utf8).replacingOccurrences(of: "Example", with: "New source")
            .write(to: windows, atomically: true, encoding: .utf8)
        try write("calls", "")
        try write("hold", "")
        service.refresh()
        await waitFor { queries.count == 3 }
        manager.update { $0.global.yabaiPath = other.appendingPathComponent("yabai").path }
        startService()
        await waitFor { service.state.focusedWindow?.title == "New source" }
        try FileManager.default.removeItem(at: directory.appendingPathComponent("hold"))
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(service.state.focusedWindow?.title, "New source")
        stopService()
        await waitFor { signalCleanupComplete }
    }

    @MainActor
    func testTitleNotificationOnlyQueriesWindowsAndCollapsesBurst() async throws {
        try await startAndClearCalls()
        let original = service.state
        var windows = try readFixture("--windows.json")
        windows[0]["title"] = "Updated title"
        var dialog = windows[0]
        dialog["id"] = 11
        dialog["subrole"] = "AXDialog"
        try writeFixture("--windows.json", windows + [dialog])
        var states: [YabaiState] = []
        service.$state.dropFirst().sink { states.append($0) }.store(in: &observations)
        try write("hold", "")
        try await postRefresh(titleOnly: true)
        await waitFor { queries.count == 1 }
        for _ in 0..<5 { try await postRefresh(titleOnly: true) }
        // Let the posted notifications enqueue their follow-up while the first query is held.
        try await Task.sleep(nanoseconds: 50_000_000)
        try FileManager.default.removeItem(at: directory.appendingPathComponent("hold"))
        await waitFor { queries.count == 2 && service.state.focusedWindow?.title == "Updated title" }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(queries, ["query --windows", "query --windows"])
        XCTAssertEqual(service.state.spaces, original.spaces)
        XCTAssertEqual(service.state.displays, original.displays)
        XCTAssertEqual(service.state.windows.count, 1, "title reads must apply the existing dialog filter")
        XCTAssertEqual(states.count, 1, "an equal follow-up must not republish the state")
        await stopAndWait()
    }

    @MainActor
    func testPendingFullWinsOverLaterTitleAndSkipsPartialPublication() async throws {
        try await startAndClearCalls()
        var windows = try readFixture("--windows.json")
        windows[0]["title"] = "Latest title"
        try writeFixture("--windows.json", windows)
        var spaces = try readFixture("--spaces.json")
        spaces[0]["label"] = "Latest Space"
        try writeFixture("--spaces.json", spaces)
        var states: [YabaiState] = []
        service.$state.dropFirst().sink { states.append($0) }.store(in: &observations)
        try write("hold", "")
        try await postRefresh(titleOnly: true)
        await waitFor { queries.count == 1 }
        service.refresh()
        try await postRefresh(titleOnly: true)
        try await Task.sleep(nanoseconds: 50_000_000)
        try FileManager.default.removeItem(at: directory.appendingPathComponent("hold"))
        await waitFor { queries.count == 4 && service.state.spaces.first?.label == "Latest Space" }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(queries.filter { $0 == "query --windows" }.count, 2)
        XCTAssertEqual(queries.filter { $0 == "query --spaces" }.count, 1)
        XCTAssertEqual(queries.filter { $0 == "query --displays" }.count, 1)
        XCTAssertEqual(states.count, 1, "the pending full refresh must suppress the partial publication")
        XCTAssertEqual(states.first?.focusedWindow?.title, "Latest title")
        XCTAssertEqual(states.first?.spaces.first?.label, "Latest Space")
        await stopAndWait()
    }

    @MainActor
    func testTitleDuringFullReadQueuesWindowsFollowUp() async throws {
        try await startAndClearCalls()
        try write("hold", "")
        service.refresh()
        await waitFor { queries.count == 3 }
        try await postRefresh(titleOnly: true)
        try await Task.sleep(nanoseconds: 50_000_000)
        try FileManager.default.removeItem(at: directory.appendingPathComponent("hold"))
        await waitFor { queries.count == 4 }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(queries.count, 4)
        XCTAssertEqual(queries.filter { $0 == "query --windows" }.count, 2)
        XCTAssertEqual(queries.last, "query --windows")
        await stopAndWait()
    }

    @MainActor
    func testTitleUpdateFallsBackWhenWindowRelationshipsChange() async throws {
        var windows = try readFixture("--windows.json")
        var second = windows[0]
        second["id"] = 11
        second["has-focus"] = false
        windows.append(second)
        var spaces = try readFixture("--spaces.json")
        spaces[0]["windows"] = [10, 11]
        let displays = try readFixture("--displays.json")
        try writeFixture("--windows.json", windows)
        try writeFixture("--spaces.json", spaces)
        try await startAndClearCalls()
        let original = service.state
        var variants: [(String, [[String: Any]])] = [
            ("removed", [windows[0]]),
            ("duplicate", [windows[0], windows[0]])
        ]
        var extra = windows[0]
        extra["id"] = 12
        variants.append(("added", windows + [extra]))
        let changes: [(String, Any)] = [
            ("id", 12), ("pid", 456), ("space", 2), ("display", 2), ("has-focus", false),
            ("is-visible", true), ("is-minimized", true), ("is-hidden", true), ("is-sticky", true)
        ]
        for (field, value) in changes {
            var changed = windows
            changed[0][field] = value
            variants.append((field, changed))
        }
        var states: [YabaiState] = []
        service.$state.dropFirst().sink { states.append($0) }.store(in: &observations)
        for (name, changed) in variants {
            states.removeAll()
            var changedSpaces = spaces
            changedSpaces[0]["label"] = name
            var changedDisplays = displays
            changedDisplays[0]["label"] = name
            try writeFixture("--windows.json", changed)
            try writeFixture("--spaces.json", changedSpaces)
            try writeFixture("--displays.json", changedDisplays)
            try await postRefresh(titleOnly: true)
            await waitFor { queries.count == 4 && service.state.spaces.first?.label == name }
            XCTAssertEqual(queries.filter { $0 == "query --windows" }.count, 2, name)
            XCTAssertEqual(queries.filter { $0 == "query --spaces" }.count, 1, name)
            XCTAssertEqual(queries.filter { $0 == "query --displays" }.count, 1, name)
            XCTAssertEqual(states.count, 1, "\(name) must not publish windows with cached relationships")
            XCTAssertEqual(states.first?.displays.first?.label, name)
            try writeFixture("--windows.json", windows)
            try writeFixture("--spaces.json", spaces)
            try writeFixture("--displays.json", displays)
            service.refresh()
            await waitFor { service.state == original }
            try write("calls", "")
        }
        await stopAndWait()
    }

    @MainActor
    func testFailedTitleReadRetriesFullOnceAndRequiresFullRecovery() async throws {
        try await startAndClearCalls()
        let original = service.state
        let windows = try String(contentsOf: directory.appendingPathComponent("--windows.json"), encoding: .utf8)
        var failures = 0
        service.$lastError.dropFirst().sink { if $0 != nil { failures += 1 } }.store(in: &observations)
        try write("--windows.json", "invalid JSON")
        try await postRefresh(titleOnly: true)
        await waitFor { queries.count == 4 && failures == 2 }
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(queries.count, 4, "a failed full fallback must not retry itself")
        XCTAssertEqual(service.state, original)
        XCTAssertFalse(service.isConnected)
        try write("--windows.json", windows)
        try await postRefresh(titleOnly: true)
        await waitFor { queries.count == 7 && service.isConnected && service.lastError == nil }
        XCTAssertEqual(Array(queries.suffix(3)).sorted(), ["query --displays", "query --spaces", "query --windows"])
        XCTAssertEqual(service.state, original)
        await stopAndWait()
    }

    @MainActor
    func testTitleBeforeFirstSuccessfulSnapshotUsesFull() async throws {
        let spaces = try String(contentsOf: directory.appendingPathComponent("--spaces.json"), encoding: .utf8)
        try write("--spaces.json", "invalid JSON")
        startService()
        await waitFor { service.lastError != nil && service.signalsRegistered }
        XCTAssertEqual(service.state, YabaiState())
        try write("--spaces.json", spaces)
        try write("calls", "")
        try await postRefresh(titleOnly: true)
        await waitFor { queries.count == 3 && service.isConnected }
        XCTAssertEqual(queries.sorted(), ["query --displays", "query --spaces", "query --windows"])
        XCTAssertEqual(service.state.spaces.count, 1)
        XCTAssertEqual(service.state.displays.count, 1)
        await stopAndWait()
    }

    @MainActor
    func testFocusQueriesOneKnownWindowAndClearsPreviousFocus() async throws {
        var windows = try readFixture("--windows.json")
        var second = windows[0]
        second["id"] = 11
        second["has-focus"] = false
        windows.append(second)
        try writeFixture("--windows.json", windows)
        var spaces = try readFixture("--spaces.json")
        spaces[0]["windows"] = [10, 11]
        try writeFixture("--spaces.json", spaces)
        try await startAndClearCalls()
        second["has-focus"] = true
        try write("single-window.json", String(decoding: JSONSerialization.data(withJSONObject: second), as: UTF8.self))
        let name = notificationName! + ".window-focused"
        try await ShellExecutor.run(executable: "/usr/bin/notifyutil", arguments: ["-z", "0", "-s", name, "11", "-p", name])
        await waitFor { service.state.focusedWindow?.id == 11 }
        XCTAssertEqual(queries, ["query --windows"])
        XCTAssertTrue(arguments.contains { $0.hasSuffix("--window 11") })
        XCTAssertEqual(service.state.windows.filter(\.hasFocus).count, 1)
        await stopAndWait()
    }

    @MainActor
    func testProjectionRejectionFallsBackOncePerGeneration() async throws {
        try write("reject-projection", "")
        startService()
        await waitFor { service.isConnected && service.signalsRegistered }
        XCTAssertEqual(queries.filter { $0 == "query --windows" }.count, 2)
        try write("calls", "")
        try write("arguments", "")
        service.refresh()
        await waitFor { queries.count == 3 }
        XCTAssertTrue(arguments.contains("-m query --windows"))
        await stopAndWait()
    }

    private func writeSingleWindow(_ window: [String: Any]) throws {
        try write("single-window.json", String(decoding: JSONSerialization.data(withJSONObject: window), as: UTF8.self))
    }

    @MainActor
    private func postFocus(_ id: Int) async throws {
        let name = notificationName! + ".window-focused"
        try await ShellExecutor.run(executable: "/usr/bin/notifyutil",
            arguments: ["-z", "0", "-s", name, String(id), "-p", name])
    }

    @MainActor
    func testDuplicateActivationDoesNotQueryButDifferentAppDoes() async throws {
        var pid: pid_t = 123
        service = YabaiService(settingsManager: manager, refreshNotification: notificationName, windowEvents: nil, workspaceNotifications: notifications, screenNotifications: notifications, frontmostPID: { pid })
        var windows = try readFixture("--windows.json")
        var second = windows[0]
        second["id"] = 11
        second["pid"] = 456
        second["app"] = "Second"
        second["has-focus"] = false
        windows.append(second)
        try writeFixture("--windows.json", windows)
        var spaces = try readFixture("--spaces.json")
        spaces[0]["windows"] = [10, 11]
        try writeFixture("--spaces.json", spaces)
        try await startAndClearCalls()
        service.handleAppNotification(Notification(name: NSWorkspace.didActivateApplicationNotification))
        try await Task.sleep(nanoseconds: 70_000_000)
        XCTAssertTrue(queries.isEmpty)
        pid = 456
        second["has-focus"] = true
        try writeSingleWindow(second)
        service.handleAppNotification(Notification(name: NSWorkspace.didActivateApplicationNotification))
        await waitFor { service.state.focusedWindow?.id == 11 }
        XCTAssertEqual(queries, ["query --windows"])
        XCTAssertTrue(arguments.contains { $0.hasSuffix("--window") })
        service.handleAppNotification(Notification(name: NSWorkspace.didActivateApplicationNotification))
        try await Task.sleep(nanoseconds: 70_000_000)
        XCTAssertEqual(queries.count, 1)
    }

    @MainActor
    func testUncertainFocusFallsBackExactlyOnce() async throws {
        let original = try XCTUnwrap(readFixture("--windows.json").first)
        // Unknown identity, out-of-order nonfocused ID, wrong front PID, cross Space/display,
        // minimized and invalid native state must never patch the known stable snapshot.
        for (key, value) in [("id", 99 as Any), ("has-focus", false), ("pid", 456),
                             ("space", 2), ("display", 2), ("is-minimized", true)] {
            try await startAndClearCalls()
            var candidate = original
            candidate[key] = value
            try writeSingleWindow(candidate)
            try await postFocus(candidate["id"] as! Int)
            await waitFor { queries.count == 4 }
            try await Task.sleep(nanoseconds: 80_000_000)
            XCTAssertEqual(queries.filter { $0 == "query --spaces" }.count, 1, key)
            XCTAssertEqual(queries.filter { $0 == "query --displays" }.count, 1, key)
            XCTAssertEqual(service.state.focusedWindow?.id, 10, key)
            await stopAndWait()
        }
    }

    @MainActor
    func testStructuralEventSupersedesLateFocusAndRebuildsMembership() async throws {
        try await startAndClearCalls()
        let original = try XCTUnwrap(readFixture("--windows.json").first)
        var late = original
        late["title"] = "Late focus"
        try writeSingleWindow(late)
        try write("hold", "")
        try await postFocus(10)
        await waitFor { queries.count == 1 }
        var current = original
        current["title"] = "Structural result"
        try writeFixture("--windows.json", [current])
        service.refresh()
        try FileManager.default.removeItem(at: directory.appendingPathComponent("hold"))
        await waitFor { service.state.focusedWindow?.title == "Structural result" }
        XCTAssertEqual(queries.count, 4)
        XCTAssertEqual(queries.filter { $0 == "query --spaces" }.count, 1)
    }

    @MainActor
    func testLatestFocusWinsWhileFirstQueryIsHeld() async throws {
        var windows = try readFixture("--windows.json")
        var second = windows[0]
        second["id"] = 11
        second["has-focus"] = false
        windows.append(second)
        try writeFixture("--windows.json", windows)
        var spaces = try readFixture("--spaces.json")
        spaces[0]["windows"] = [10, 11]
        try writeFixture("--spaces.json", spaces)
        try await startAndClearCalls()
        try write("hold", "")
        try writeSingleWindow(windows[0])
        try await postFocus(10)
        await waitFor { queries.count == 1 }
        second["has-focus"] = true
        try writeSingleWindow(second)
        try await postFocus(11)
        try await Task.sleep(nanoseconds: 50_000_000)
        try FileManager.default.removeItem(at: directory.appendingPathComponent("hold"))
        await waitFor { service.state.focusedWindow?.id == 11 }
        XCTAssertEqual(queries, ["query --windows", "query --windows"])
    }

    @MainActor
    func testZeroTokenIsReadAndCancelledAndRegistrationFailureUsesFullChannel() async throws {
        var cancelled: [Int32] = []
        var reads: [Int32] = []
        service = YabaiService(settingsManager: manager, refreshNotification: notificationName, windowEvents: nil, workspaceNotifications: notifications, screenNotifications: notifications,
            frontmostPID: { 123 }, registerFocus: { _, token in token = 0; return 0 },
            readFocus: { token, value in reads.append(token); value = 10; return 0 },
            cancelFocus: { token in cancelled.append(token); return 0 })
        let window = try XCTUnwrap(readFixture("--windows.json").first)
        try writeSingleWindow(window)
        try await startAndClearCalls()
        postNotification(notificationName + ".window-focused")
        await waitFor { queries.count == 1 && reads == [0] }
        await stopAndWait()
        XCTAssertEqual(cancelled, [0])
        service = YabaiService(settingsManager: manager, refreshNotification: notificationName, windowEvents: nil, workspaceNotifications: notifications, screenNotifications: notifications,
            frontmostPID: { 123 }, registerFocus: { _, _ in 1 },
            cancelFocus: { token in cancelled.append(token); return 0 })
        try write("arguments", "")
        startService()
        await waitFor { service.signalsRegistered }
        XCTAssertTrue(arguments.contains("-m signal --add event=window_focused action=/usr/bin/notifyutil -p \(notificationName!) label=abar-window-focused"))
        await stopAndWait()
        XCTAssertEqual(cancelled, [0])
    }

    func testStickyFocusPreservesCurrentSpaceAndPresentationIgnoresGeometry() throws {
        var raw = try XCTUnwrap(readFixture("--windows.json").first)
        raw["is-sticky"] = true
        raw["space"] = 2
        let decode: ([String: Any]) throws -> YabaiWindow = {
            try JSONDecoder().decode(YabaiWindow.self, from: JSONSerialization.data(withJSONObject: $0))
        }
        let window = try decode(raw)
        let spaces = try JSONDecoder().decode([YabaiSpace].self, from: Data(#"[{"id":1,"index":1,"display":1,"type":"bsp","windows":[],"has-focus":true},{"id":2,"index":2,"display":1,"type":"bsp","windows":[10]}]"#.utf8))
        let displays = try JSONDecoder().decode([YabaiDisplay].self, from: Data(contentsOf: directory.appendingPathComponent("--displays.json")))
        let state = YabaiState(spaces: spaces, windows: [window], displays: displays)
        XCTAssertEqual(state.updatingFocus(window)?.focusedSpace?.index, 1)
        raw["frame"] = ["x": 500, "y": 400, "w": 200, "h": 200]
        let moved = try decode(raw)
        XCTAssertNotEqual(window, moved)
        XCTAssertEqual(YabaiWindowPresentation(window), YabaiWindowPresentation(moved))
        raw["title"] = "Changed"
        XCTAssertNotEqual(YabaiWindowPresentation(window), YabaiWindowPresentation(try decode(raw)))
        raw["has-focus"] = false
        raw["is-visible"] = true
        let unmanaged = try decode(raw)
        let fallback = YabaiState(spaces: spaces, windows: [unmanaged], displays: displays)
        XCTAssertEqual(fallback.selectingVisibleWindow(for: 123).focusedWindow?.id, 10)
        XCTAssertNil(fallback.selectingVisibleWindow(for: 999).focusedWindow)
    }

    private func stampNativeReadySnapshot(_ backend: YabaiWindowEventsTests.Backend) throws {
        var spaces = try readFixture("--spaces.json")
        spaces[0]["label"] = "Native observers ready"
        let data = try JSONSerialization.data(withJSONObject: spaces)
        let path = directory.appendingPathComponent("--spaces.json")
        // Stamp only after subscription, so the matching published snapshot proves startup recovery finished.
        backend.onFirstSubscription { try? data.write(to: path, options: .atomic) }
    }

    @MainActor
    func testNativeTitleWinsWhenYabaiCacheHasNotReceivedTheEventYet() async throws {
        let backend = YabaiWindowEventsTests.Backend(title: "Native title")
        try stampNativeReadySnapshot(backend)
        let native = YabaiWindowEvents(trusted: { true }, subscribe: backend.subscribe,
                                       titleReader: { _ in backend.title })
        service = YabaiService(settingsManager: manager, refreshNotification: notificationName,
                               windowEvents: native, workspaceNotifications: notifications, screenNotifications: notifications, frontmostPID: { 123 })
        startService()
        await waitFor { service.state.focusedSpace?.label == "Native observers ready" && service.signalsRegistered && backend.registered == [123] }
        backend.emit(.titleChanged(id: 10, pid: 123, element: AXUIElementCreateApplication(123), title: "Native title"))
        await waitFor { service.state.focusedWindow?.title == "Native title" }
        // The backend receives its own AX event later; it does not send another event to a-bar.
        var windows = try readFixture("--windows.json")
        windows[0]["title"] = "Native title"
        try writeFixture("--windows.json", windows)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(service.state.focusedWindow?.title, "Native title")
        await stopAndWait()
    }

    @MainActor
    func testNativePermissionRecoveryRebuildsTheMissedSnapshot() async throws {
        let backend = YabaiWindowEventsTests.Backend()
        try stampNativeReadySnapshot(backend)
        var trusted = true
        let native = YabaiWindowEvents(trusted: { trusted }, subscribe: backend.subscribe)
        service = YabaiService(settingsManager: manager, refreshNotification: notificationName,
                               windowEvents: native, workspaceNotifications: notifications, screenNotifications: notifications, frontmostPID: { 123 })
        startService()
        await waitFor { service.state.focusedSpace?.label == "Native observers ready" && service.signalsRegistered && backend.registered == [123] }
        try await Task.sleep(nanoseconds: 50_000_000)
        trusted = false
        native.update(service.state.windows)
        await waitFor { backend.cancelled == [123] }
        var spaces = try readFixture("--spaces.json")
        spaces[0]["label"] = "Changed during permission gap"
        try writeFixture("--spaces.json", spaces)
        trusted = true
        native.update(service.state.windows)
        await waitFor { service.state.focusedSpace?.label == "Changed during permission gap" }
        await stopAndWait()
    }

    @MainActor
    func testNativeTitleOnlyPatchesExactWindowAndCannotPinFailedReadOverNewBackendTitle() async throws {
        var windows = try readFixture("--windows.json")
        var second = windows[0]
        second["id"] = 11
        second["has-focus"] = false
        windows.append(second) // Same PID, title and geometry deliberately cannot identify the target.
        try writeFixture("--windows.json", windows)
        let backend = YabaiWindowEventsTests.Backend(title: "Native B")
        try stampNativeReadySnapshot(backend)
        let native = YabaiWindowEvents(trusted: { true }, subscribe: backend.subscribe,
                                       titleReader: { _ in backend.title })
        service = YabaiService(settingsManager: manager, refreshNotification: notificationName,
                               windowEvents: native, workspaceNotifications: notifications, screenNotifications: notifications, frontmostPID: { 123 })
        startService()
        await waitFor { service.state.focusedSpace?.label == "Native observers ready" && service.signalsRegistered && backend.registered == [123] }
        backend.emit(.titleChanged(id: 11, pid: 123, element: AXUIElementCreateApplication(123), title: "Native B"))
        await waitFor { service.state.windows.first(where: { $0.id == 11 })?.title == "Native B" }
        XCTAssertEqual(service.state.windows.first(where: { $0.id == 10 })?.title, "Example")
        var focused = windows[0]
        focused["title"] = "Focus read complete"
        try writeSingleWindow(focused)
        try await postFocus(10)
        await waitFor { service.state.focusedWindow?.title == "Focus read complete" }
        var spaces = try readFixture("--spaces.json")
        spaces[0]["label"] = "Stale backend confirmed"
        try writeFixture("--spaces.json", spaces)
        service.refresh()
        await waitFor { service.state.focusedSpace?.label == "Stale backend confirmed" }
        XCTAssertEqual(service.state.windows.first(where: { $0.id == 11 })?.title, "Native B")
        backend.title = nil
        windows[1]["title"] = "Backend C"
        try writeFixture("--windows.json", windows)
        service.refresh()
        await waitFor { service.state.windows.first(where: { $0.id == 11 })?.title == "Backend C" }
        await stopAndWait()
    }

    @MainActor
    func testLateTitleConfirmationCannotOverwriteNewNativeTitle() async throws {
        let backend = YabaiWindowEventsTests.Backend()
        try stampNativeReadySnapshot(backend)
        let element = AXUIElementCreateApplication(123)
        var sentNewer = false
        let native = YabaiWindowEvents(trusted: { true }, subscribe: backend.subscribe,
            titleReader: { _ in
                if !sentNewer {
                    sentNewer = true
                    backend.emitInline(.titleChanged(id: 10, pid: 123, element: element, title: "Native C"))
                    DispatchQueue.main.sync {} // Deliver C before the older read returns B.
                    return "Native B"
                }
                return "Native C"
            })
        service = YabaiService(settingsManager: manager, refreshNotification: notificationName,
                               windowEvents: native, workspaceNotifications: notifications, screenNotifications: notifications, frontmostPID: { 123 })
        startService()
        await waitFor { service.state.focusedSpace?.label == "Native observers ready" && service.signalsRegistered && backend.registered == [123] }
        backend.emit(.titleChanged(id: 10, pid: 123, element: element, title: "Native B"))
        await waitFor { service.state.focusedWindow?.title == "Native B" || service.state.focusedWindow?.title == "Native C" }
        var spaces = try readFixture("--spaces.json")
        spaces[0]["label"] = "Confirmation completed"
        try writeFixture("--spaces.json", spaces)
        service.refresh()
        await waitFor { service.state.focusedSpace?.label == "Confirmation completed" }
        XCTAssertEqual(service.state.focusedWindow?.title, "Native C")
        await stopAndWait()
    }

    @MainActor
    func testSuccessfulTitleConfirmationDoesNotSuppressReturnToPreviousTitle() async throws {
        let backend = YabaiWindowEventsTests.Backend(title: "Native B")
        try stampNativeReadySnapshot(backend)
        let native = YabaiWindowEvents(trusted: { true }, subscribe: backend.subscribe,
                                       titleReader: { _ in backend.title })
        service = YabaiService(settingsManager: manager, refreshNotification: notificationName,
                               windowEvents: native, workspaceNotifications: notifications, screenNotifications: notifications, frontmostPID: { 123 })
        startService()
        await waitFor { service.state.focusedSpace?.label == "Native observers ready" && service.signalsRegistered && backend.registered == [123] }
        let element = AXUIElementCreateApplication(123)
        backend.emit(.titleChanged(id: 10, pid: 123, element: element, title: "Native B"))
        await waitFor { service.state.focusedWindow?.title == "Native B" }
        backend.title = "Native C"
        service.refresh()
        await waitFor { service.state.focusedWindow?.title == "Native C" }
        backend.title = "Native B"
        backend.emit(.titleChanged(id: 10, pid: 123, element: element, title: "Native B"))
        await waitFor { service.state.focusedWindow?.title == "Native B" }
        await stopAndWait()
    }

    private var focusAction: String {
        let name = notificationName! + ".window-focused"
        return "/usr/bin/notifyutil -z 0 -s \(name) \"$YABAI_WINDOW_ID\" -p \(name)"
    }

    @MainActor
    func testSignalMigrationChecksEventAndActionAndKeepsLabels() async throws {
        let fullAction = "/usr/bin/notifyutil -p \(notificationName!)"
        try writeFixture("signals.json", [
            ["index": 0, "label": "abar-window-destroyed", "event": "window_destroyed", "app": "", "title": "", "action": fullAction],
            ["index": 1, "label": "abar-window-title-changed", "event": "window_title_changed", "app": "", "title": "", "action": fullAction],
            ["index": 2, "label": "abar-window-focused", "event": "window_created", "app": "", "title": "", "action": fullAction]
        ])
        startService()
        await waitFor { service.isConnected && service.signalsRegistered }
        let adds = arguments.filter { $0.hasPrefix("-m signal --add ") }
        XCTAssertEqual(adds.count, 4, "keep destroyed, migrate focus and add three structural signals")
        XCTAssertTrue(arguments.contains("-m signal --remove abar-window-title-changed"))
        XCTAssertTrue(adds.contains("-m signal --add event=window_focused action=\(focusAction) label=abar-window-focused"))
        XCTAssertFalse(adds.contains { $0.contains("event=window_moved ") || $0.contains("event=window_title_changed ") })
        await stopAndWait()
    }

    @MainActor
    func testCurrentSignalActionsAreNotRegisteredAgain() async throws {
        let fullAction = "/usr/bin/notifyutil -p \(notificationName!)"
        try writeFixture("signals.json", [
            ["index": 4, "label": "abar-window-created", "event": "window_created", "app": "", "title": "", "action": fullAction],
            ["index": 5, "label": "abar-window-minimized", "event": "window_minimized", "app": "", "title": "", "action": fullAction],
            ["index": 6, "label": "abar-window-deminimized", "event": "window_deminimized", "app": "", "title": "", "action": fullAction],
            ["index": 0, "label": "abar-window-destroyed", "event": "window_destroyed", "app": "", "title": "", "action": fullAction],
            ["index": 1, "label": "abar-window-title-changed", "event": "window_title_changed", "app": "", "title": "", "action": fullAction + ".window-title-changed"],
            ["index": 2, "label": "abar-window-focused", "event": "window_focused", "app": "", "title": "", "action": focusAction],
            ["index": 3, "label": "abar-window-moved", "event": "window_moved", "app": "", "title": "", "action": fullAction + ".window-moved"]
        ])
        startService()
        await waitFor { service.isConnected && service.signalsRegistered }
        XCTAssertFalse(calls.contains("signal --add"))
        await stopAndWait()
    }

    @MainActor
    func testLegacyMoveAndTitleSignalsAreRemovedWithoutReRegisteringOtherSignals() async throws {
        let action = "/usr/bin/notifyutil -p \(notificationName!)"
        try writeFixture("signals.json", [
            ["index": 4, "label": "abar-window-created", "event": "window_created", "app": "", "title": "", "action": action],
            ["index": 5, "label": "abar-window-minimized", "event": "window_minimized", "app": "", "title": "", "action": action],
            ["index": 6, "label": "abar-window-deminimized", "event": "window_deminimized", "app": "", "title": "", "action": action],
            ["index": 0, "label": "abar-window-destroyed", "event": "window_destroyed", "app": "", "title": "", "action": action],
            ["index": 1, "label": "abar-window-title-changed", "event": "window_title_changed", "app": "", "title": "", "action": action + ".window-title-changed"],
            ["index": 2, "label": "abar-window-focused", "event": "window_focused", "app": "", "title": "", "action": focusAction],
            ["index": 3, "label": "abar-window-moved", "event": "window_moved", "app": "", "title": "", "action": action]
        ])
        startService()
        await waitFor { service.isConnected && service.signalsRegistered }
        XCTAssertFalse(arguments.contains { $0.hasPrefix("-m signal --add ") })
        XCTAssertTrue(arguments.contains("-m signal --remove abar-window-moved"))
        XCTAssertTrue(arguments.contains("-m signal --remove abar-window-title-changed"))
        await stopAndWait()
    }

    @MainActor
    func testBothNotificationsRefreshAndStopTogether() async throws {
        try await startAndClearCalls()
        var windows = try readFixture("--windows.json")
        windows[0]["title"] = "Title notification"
        try writeFixture("--windows.json", windows)
        try await postRefresh(titleOnly: true)
        await waitFor { service.state.focusedWindow?.title == "Title notification" }
        XCTAssertEqual(queries, ["query --windows"])
        try await postRefresh(titleOnly: false)
        await waitFor { queries.count == 4 }
        try await Task.sleep(nanoseconds: 100_000_000)
        await stopAndWait()
        try write("calls", "")
        service.refresh()
        try await postRefresh(titleOnly: true)
        try await postRefresh(titleOnly: false)
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertTrue(queries.isEmpty)
    }

    @MainActor
    func testStoppedTitleReadCannotPublishOrQueueFull() async throws {
        try await startAndClearCalls()
        let original = service.state
        var windows = try readFixture("--windows.json")
        windows[0]["space"] = 2
        try writeFixture("--windows.json", windows)
        try write("hold", "")
        try await postRefresh(titleOnly: true)
        await waitFor { queries.count == 1 }
        await stopAndWait()
        try FileManager.default.removeItem(at: directory.appendingPathComponent("hold"))
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(service.state, original)
        XCTAssertEqual(queries.count, 1, "a stopped title query must not enqueue a structural fallback")
    }

}
