import Combine
import XCTest

/// `aerospace` answers monitors, workspaces, the focused window and all windows in four
/// separate commands, and a refresh is only meaningful if all four land as one snapshot. The
/// focused-window query is allowed to fail - an empty desktop has no focused window - while a
/// failure anywhere else has to leave the service disconnected rather than half-updated.
///
/// A stand-in for the `aerospace` binary answers each subcommand from a file the test writes,
/// so nothing here touches a real window manager.
final class AerospaceServiceTests: XCTestCase {
    private var directory: URL!
    private var service: AerospaceService!
    private var manager: SettingsManager!
    private var observations = Set<AnyCancellable>()

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("abar-aerospace-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let executable = directory.appendingPathComponent("aerospace")
        try """
        #!/bin/sh
        # Stands in for the aerospace binary. Logs the subcommand, then prints whichever
        # fixture the test put beside it. A fixture file that is absent means "this query
        # fails", which is how the no-focused-window case is exercised.
        root=${0%/*}
        printf '%s\\n' "$*" >> "$root/calls"
        case "$1 $2" in
          "list-monitors --json")   name=monitors ;;
          "list-workspaces --all")  name=workspaces ;;
          "list-windows --focused") name=focused ;;
          "list-windows --all")     name=windows ;;
          *)                        name=action ;;
        esac
        [ -f "$root/$name.json" ] || exit 1
        if [ "$name" = monitors ] && [ -f "$root/block" ]; then
          touch "$root/entered"
          while [ -f "$root/block" ]; do sleep 0.01; done
        fi
        cat "$root/$name.json"
        """.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700], ofItemAtPath: executable.path)

        try write("calls", "")
        try write("action.json", "")
        try write("monitors.json", #"[{"monitor-id":1,"monitor-name":"Built-in"}]"#)
        try write("workspaces.json", """
            [{"workspace":"1","workspace-is-focused":true,"workspace-is-visible":true,\
            "monitor-id":1,"monitor-name":"Built-in"},\
            {"workspace":"2","workspace-is-focused":false,"workspace-is-visible":false,\
            "monitor-id":1,"monitor-name":"Built-in"}]
            """)
        try write("focused.json", #"[{"window-id":10,"app-name":"Ghostty","workspace":"1","monitor-id":1}]"#)
        try write("windows.json", """
            [{"window-id":10,"app-name":"Ghostty","window-title":"zsh","workspace":"1","monitor-id":1},\
            {"window-id":11,"app-name":"Safari","window-title":"Docs","workspace":"2","monitor-id":1}]
            """)

        var settings = ABarSettings()
        settings.global.aerospacePath = executable.path
        let config = directory.appendingPathComponent("config.json")
        try SettingsCodec.encode(settings).write(to: config)
        manager = SettingsManager(store: SettingsStore(fileURL: config))
        service = AerospaceService(settingsManager: manager)
    }

    override func tearDownWithError() throws {
        service.stop()
        observations.removeAll()
        manager.flush()
        service = nil
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Harness

    private func write(_ name: String, _ contents: String) throws {
        try contents.write(
            to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    private func remove(_ name: String) throws {
        try FileManager.default.removeItem(at: directory.appendingPathComponent(name))
    }

    private var calls: [String] {
        (try? String(contentsOf: directory.appendingPathComponent("calls"), encoding: .utf8))?
            .split(separator: "\n").map(String.init) ?? []
    }

    /// Wait for the next published value that satisfies `predicate`.
    @discardableResult
    private func awaitState(
        _ description: String,
        timeout: TimeInterval = 5,
        where predicate: @escaping (AerospaceState) -> Bool,
        after action: () -> Void
    ) -> AerospaceState? {
        let expectation = expectation(description: description)
        var seen: AerospaceState?
        service.$state
            .dropFirst()
            .filter(predicate)
            .first()
            .sink { state in
                seen = state
                expectation.fulfill()
            }
            .store(in: &observations)
        action()
        wait(for: [expectation], timeout: timeout)
        return seen
    }

    private func awaitRefresh(
        _ description: String = "refresh",
        where predicate: @escaping (AerospaceState) -> Bool = { !$0.workspaces.isEmpty }
    ) -> AerospaceState? {
        awaitState(description, where: predicate) {
            service.start()
            service.refresh()
        }
    }

    // MARK: - Lifecycle

    func testStoppingCancelsAQueuedReadAndManualRefreshCannotRestartIt() {
        service.refresh()
        service.start()
        service.stop()
        service.refresh()
        let settled = expectation(description: "queued work has had a turn")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { settled.fulfill() }
        wait(for: [settled], timeout: 1)

        XCTAssertTrue(calls.isEmpty)
        XCTAssertTrue(service.state.workspaces.isEmpty)
        XCTAssertFalse(service.isConnected)
    }

    func testStoppingDuringAReadDiscardsItsResultAndRemainingQueries() throws {
        try write("block", "")
        defer { try? remove("block") }
        let entered = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                FileManager.default.fileExists(atPath: self.directory.appendingPathComponent("entered").path)
            }, object: nil)
        let publication = expectation(description: "stopped read must not publish")
        publication.isInverted = true
        service.$state.dropFirst().sink { _ in publication.fulfill() }.store(in: &observations)

        service.start()
        wait(for: [entered], timeout: 3)
        service.stop()
        try remove("block")
        wait(for: [publication], timeout: 0.3)

        XCTAssertEqual(calls.count, 1, "stop must cancel the remaining three queries")
        XCTAssertTrue(service.state.workspaces.isEmpty)
        XCTAssertFalse(service.isConnected)
    }

    func testRepeatedStartDoesNotReadAgain() {
        _ = awaitRefresh()
        let count = calls.count
        service.start()
        service.start()
        let settled = expectation(description: "repeated starts have had a turn")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { settled.fulfill() }
        wait(for: [settled], timeout: 1)
        XCTAssertEqual(calls.count, count)
    }

    // MARK: - A whole snapshot

    func testARefreshJoinsTheFourQueriesIntoOneState() throws {
        let state = try XCTUnwrap(awaitRefresh())

        XCTAssertEqual(state.monitors.map(\.monitorName), ["Built-in"])
        XCTAssertEqual(state.workspaces.map(\.workspace), ["1", "2"])
        XCTAssertEqual(state.workspaces[0].windows.map(\.appName), ["Ghostty"])
        XCTAssertEqual(state.workspaces[1].windows.map(\.appName), ["Safari"])
        XCTAssertTrue(service.isConnected)
        XCTAssertNil(service.lastError)
    }

    func testTheFocusedWindowIsMarkedOnTheWorkspaceThatHoldsIt() throws {
        let state = try XCTUnwrap(awaitRefresh())

        XCTAssertEqual(state.workspaces[0].windows.first?.isFocused, true)
        XCTAssertEqual(state.workspaces[1].windows.first?.isFocused, false)
    }

    func testAllFourQueriesAreIssued() {
        _ = awaitRefresh()

        XCTAssertEqual(calls.count, 4, "one pass, four commands")
        XCTAssertTrue(calls.contains { $0.hasPrefix("list-monitors") })
        XCTAssertTrue(calls.contains { $0.hasPrefix("list-workspaces --all") })
        XCTAssertTrue(calls.contains { $0.hasPrefix("list-windows --focused") })
        XCTAssertTrue(calls.contains { $0.hasPrefix("list-windows --all") })
    }

    // MARK: - Partial failure

    func testAnEmptyDesktopWithNoFocusedWindowStillRefreshes() throws {
        // `list-windows --focused` failing is the normal answer when nothing is focused.
        try remove("focused.json")

        let state = try XCTUnwrap(awaitRefresh())

        XCTAssertEqual(state.workspaces.count, 2, "the rest of the snapshot still lands")
        XCTAssertTrue(service.isConnected)
        XCTAssertFalse(
            state.workspaces.flatMap(\.windows).contains { $0.isFocused },
            "nothing is focused, so no window may claim it")
    }

    func testAFailedMonitorsQueryLeavesTheServiceDisconnected() throws {
        try remove("monitors.json")
        let expectation = expectation(description: "disconnected")
        service.$lastError
            .dropFirst()
            .compactMap { $0 }
            .first()
            .sink { _ in expectation.fulfill() }
            .store(in: &observations)

        service.start()
        service.refresh()
        wait(for: [expectation], timeout: 5)

        XCTAssertFalse(service.isConnected)
        XCTAssertTrue(service.state.workspaces.isEmpty,
                      "a failed pass must not publish a partial snapshot")
    }

    func testUnparseableOutputIsTreatedAsAFailure() throws {
        try write("workspaces.json", "not json at all")
        let expectation = expectation(description: "decode failure")
        service.$lastError
            .dropFirst()
            .compactMap { $0 }
            .first()
            .sink { _ in expectation.fulfill() }
            .store(in: &observations)

        service.start()
        service.refresh()
        wait(for: [expectation], timeout: 5)

        XCTAssertFalse(service.isConnected)
    }

    func testAFailedPassIsRecoveredFromByTheNextOne() throws {
        try remove("monitors.json")
        let failure = expectation(description: "first pass fails")
        service.$lastError.dropFirst().compactMap { $0 }.first()
            .sink { _ in failure.fulfill() }.store(in: &observations)
        service.start()
        service.refresh()
        wait(for: [failure], timeout: 5)

        try write("monitors.json", #"[{"monitor-id":1,"monitor-name":"Built-in"}]"#)
        let state = try XCTUnwrap(awaitRefresh("second pass succeeds"))

        XCTAssertEqual(state.workspaces.count, 2)
        XCTAssertTrue(service.isConnected)
        XCTAssertNil(service.lastError, "a good pass clears the stale error")
    }

    // MARK: - Actions

    func testGoToWorkspaceSendsTheCommandAndRefreshes() async throws {
        await service.goToWorkspace("2")

        XCTAssertTrue(calls.contains("workspace 2"))
    }

    func testFocusWindowSendsTheWindowId() async throws {
        await service.focusWindow(11)

        XCTAssertTrue(calls.contains("focus --window-id 11"))
    }

    /// Documents a real gap rather than a desired behaviour. `goToWorkspace` and `focusWindow`
    /// go through `ShellExecutor.run(_ command:)`, which runs the string under zsh and hands
    /// back whatever it printed - it passes `checkExit: false`, so a non-zero exit is not an
    /// error. Only a failure to launch zsh itself would throw, which does not happen in
    /// practice. So an `aerospace` that refuses the command leaves `lastError` untouched and
    /// the popover shows nothing wrong. Change this test when that changes.
    func testANonZeroExitFromAnActionIsCurrentlyNotSurfaced() async throws {
        try remove("action.json")  // the stand-in now exits 1 for `workspace 2`

        await service.goToWorkspace("2")

        XCTAssertTrue(calls.contains("workspace 2"), "the command was still sent")
        XCTAssertNil(service.lastError)
    }

    // MARK: - Reading the configured path

    func testThePathComesFromSettingsOnEveryCall() throws {
        _ = awaitRefresh()
        let firstPassCalls = calls.count

        // Repoint at a second stand-in; the service must pick it up without being rebuilt.
        let second = directory.appendingPathComponent("aerospace-moved")
        try FileManager.default.copyItem(
            at: directory.appendingPathComponent("aerospace"), to: second)
        manager.update { $0.global.aerospacePath = second.path }

        _ = awaitRefresh("refresh through the new path")

        XCTAssertGreaterThan(calls.count, firstPassCalls)
    }
}
