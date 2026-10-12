import Combine
import XCTest

/// The four things AppleScript can ask of a custom widget. Visibility changes have to persist
/// immediately: a `hide` sent from a script must survive a restart, and must not be undone by
/// the next save from the Preferences window. Each of hide/show also has to distinguish "I
/// changed it" from "it was already like that", because that is what the reply says.
final class UserWidgetManagerTests: XCTestCase {
    private var directory: URL!
    private var settings: SettingsManager!
    private var center: NotificationCenter!
    private var manager: UserWidgetManager!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("abar-userwidgets-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var seed = ABarSettings()
        seed.userWidgets = [
            UserWidgetDefinition(name: "Disk", command: "df -h", refreshInterval: 30),
            UserWidgetDefinition(name: "Quiet", command: "true", refreshInterval: 30),
        ]
        seed.userWidgets[1].isActive = false
        let config = directory.appendingPathComponent("config.json")
        try SettingsCodec.encode(seed).write(to: config)
        settings = SettingsManager(store: SettingsStore(fileURL: config))
        center = NotificationCenter()
        manager = UserWidgetManager(settingsManager: settings, notificationCenter: center)
    }

    override func tearDownWithError() throws {
        settings.flush()
        try? FileManager.default.removeItem(at: directory)
    }

    private func widget(_ name: String) -> UserWidgetDefinition? {
        manager.widgets.first { $0.name == name }
    }

    private func persisted() throws -> ABarSettings {
        settings.flush()
        let data = try Data(contentsOf: directory.appendingPathComponent("config.json"))
        guard case .ok(let stored, _) = SettingsCodec.decode(data) else {
            XCTFail("the config on disk did not parse")
            return ABarSettings()
        }
        return stored
    }

    // MARK: - Reading the list

    func testWidgetsComeFromSettings() {
        XCTAssertEqual(manager.widgets.map(\.name), ["Disk", "Quiet"])
    }

    // MARK: - Refresh

    func testRefreshingPostsTheWidgetsOwnId() throws {
        var posted: UUID?
        let token = center.addObserver(forName: .refreshUserWidget, object: nil, queue: nil) {
            posted = $0.userInfo?["widgetId"] as? UUID
        }
        defer { center.removeObserver(token) }

        XCTAssertTrue(manager.refreshWidget(named: "Disk"))
        XCTAssertEqual(posted, widget("Disk")?.id,
                       "every widget on every bar hears this; only the id tells them apart")
    }

    func testRefreshingAnUnknownWidgetFailsAndPostsNothing() {
        var posts = 0
        let token = center.addObserver(forName: .refreshUserWidget, object: nil, queue: nil) { _ in
            posts += 1
        }
        defer { center.removeObserver(token) }

        XCTAssertFalse(manager.refreshWidget(named: "Nope"))
        XCTAssertEqual(posts, 0)
    }

    func testRefreshMatchingIsExactRatherThanCaseInsensitive() {
        XCTAssertFalse(manager.refreshWidget(named: "disk"),
                       "widget names are matched as written")
    }

    // MARK: - Toggle

    func testTogglingAnActiveWidgetHidesIt() throws {
        let result = manager.toggleWidget(named: "Disk")

        XCTAssertEqual(try result.get(), false, "the state it ended up in")
        XCTAssertEqual(widget("Disk")?.isActive, false)
        XCTAssertEqual(try persisted().userWidgets.first(where: { $0.name == "Disk" })?.isActive, false)
    }

    func testTogglingAHiddenWidgetShowsIt() throws {
        XCTAssertEqual(try manager.toggleWidget(named: "Quiet").get(), true)
        XCTAssertEqual(widget("Quiet")?.isActive, true)
    }

    func testTogglingAnUnknownWidgetReportsItByName() {
        guard case .failure(let error) = manager.toggleWidget(named: "Nope") else {
            return XCTFail("expected a failure")
        }
        XCTAssertEqual(error, .widgetNotFound("Nope"))
    }

    // MARK: - Hide and show report whether anything changed

    func testHidingAVisibleWidgetChangesIt() throws {
        XCTAssertEqual(try manager.hideWidget(named: "Disk").get(), true)
        XCTAssertEqual(widget("Disk")?.isActive, false)
    }

    func testHidingAnAlreadyHiddenWidgetChangesNothing() throws {
        XCTAssertEqual(try manager.hideWidget(named: "Quiet").get(), false,
                       "the reply says 'was already hidden', so this has to be distinguishable")
        XCTAssertEqual(widget("Quiet")?.isActive, false)
    }

    func testShowingAHiddenWidgetChangesIt() throws {
        XCTAssertEqual(try manager.showWidget(named: "Quiet").get(), true)
        XCTAssertEqual(widget("Quiet")?.isActive, true)
    }

    func testShowingAnAlreadyVisibleWidgetChangesNothing() throws {
        XCTAssertEqual(try manager.showWidget(named: "Disk").get(), false)
        XCTAssertEqual(widget("Disk")?.isActive, true)
    }

    func testHidingAndShowingAnUnknownWidgetBothFail() {
        for result in [manager.hideWidget(named: "Nope"), manager.showWidget(named: "Nope")] {
            guard case .failure(let error) = result else {
                return XCTFail("expected a failure")
            }
            XCTAssertEqual(error, .widgetNotFound("Nope"))
        }
    }

    // MARK: - Persistence

    func testAVisibilityChangeSurvivesARelaunch() throws {
        _ = manager.hideWidget(named: "Disk")
        settings.flush()

        let reloaded = SettingsManager(
            store: SettingsStore(fileURL: directory.appendingPathComponent("config.json")))
        let after = UserWidgetManager(settingsManager: reloaded, notificationCenter: center)

        XCTAssertEqual(after.widgets.first(where: { $0.name == "Disk" })?.isActive, false)
    }

    func testANoOpHideDoesNotRewriteTheOtherWidgets() throws {
        let before = try persisted().userWidgets

        _ = manager.hideWidget(named: "Quiet")

        XCTAssertEqual(try persisted().userWidgets, before,
                       "nothing changed, so nothing should have been written")
    }

    // MARK: - Removal

    func testRemovingAWidgetTakesItOutOfSettings() throws {
        let id = try XCTUnwrap(widget("Disk")?.id)

        manager.removeWidget(id: id)

        XCTAssertEqual(manager.widgets.map(\.name), ["Quiet"])
        XCTAssertEqual(try persisted().userWidgets.map(\.name), ["Quiet"])
    }

    func testRemovingAnUnknownIdLeavesTheListAlone() {
        manager.removeWidget(id: UUID())

        XCTAssertEqual(manager.widgets.map(\.name), ["Disk", "Quiet"])
    }

    // MARK: - Errors

    func testEveryErrorNamesTheWidgetItIsAbout() {
        XCTAssertTrue(
            UserWidgetError.widgetNotFound("Disk").errorDescription?.contains("Disk") ?? false)
        XCTAssertTrue(
            UserWidgetError.duplicateName("Disk").errorDescription?.contains("Disk") ?? false)
    }
}

@MainActor
final class UserWidgetRunnerTests: XCTestCase {
    func testRepeatedOutputAndErrorsPublishOnlyChangesAndRecoverTheSameOutput() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let marker = directory.appendingPathComponent("runs")
        let command = """
        printf x >> '\(marker.path)'
        count=$(wc -c < '\(marker.path)' | tr -d ' ')
        case "$count" in
          1|2) printf 'First\\nSecond\\n---\\nMenu\\n' ;;
          4|5) printf 'fixture failure\\n' >&2; exit 7 ;;
          *) printf 'Changed\\nSecond\\n---\\nMenu\\n' ;;
        esac
        """
        let runner = UserWidgetRunner(config: UserWidgetDefinition(
            command: command, refreshInterval: 60, cycleDuration: 60))
        var outputs: [XBarParsedOutput] = []
        var errors: [String?] = []
        var loading: [Bool] = []
        var indices: [Int] = []
        let observations = [
            runner.$parsedOutput.dropFirst().sink { outputs.append($0) },
            runner.$errorMessage.dropFirst().sink { errors.append($0) },
            runner.$isLoading.dropFirst().sink { loading.append($0) },
            runner.$currentHeaderIndex.dropFirst().sink { indices.append($0) },
        ]
        var lifecycle: AnyCancellable?
        defer { lifecycle?.cancel(); withExtendedLifetime(observations) {} }

        await waitForOutput("First", runner) {
            lifecycle = runner.refreshNotifications.sink { _ in }
        }
        await waitForOutput("Changed", runner) {
            runner.refresh()
            runner.refresh() // Queue one follow-up while the identical output is in flight.
        }
        XCTAssertEqual(outputs.count, 2)
        XCTAssertEqual(try Data(contentsOf: marker).count, 3)
        XCTAssertTrue(errors.isEmpty)

        let failed = expectation(description: "first failure published")
        let errorObservation = runner.$errorMessage.dropFirst().compactMap { $0 }.prefix(1)
            .sink { _ in failed.fulfill() }
        runner.refresh()
        await fulfillment(of: [failed], timeout: 2)
        withExtendedLifetime(errorObservation) {}
        XCTAssertEqual(runner.parsedOutput, .empty)
        await waitForOutput("Changed", runner) {
            runner.refresh()
            runner.refresh() // The same error is followed by the last successful stdout.
        }
        XCTAssertEqual(try Data(contentsOf: marker).count, 6)
        XCTAssertEqual(outputs.count, 4, "only first output, change, failure clear and recovery publish")
        XCTAssertEqual(errors, ["Exit code: 7\nfixture failure", nil])
        XCTAssertEqual(loading, [false])
        XCTAssertTrue(indices.isEmpty, "resetting an already-zero header index must not publish")
        XCTAssertEqual(runner.parsedOutput.menuItems.first?.title, "Menu")
    }

    private func waitForOutput(_ title: String, _ runner: UserWidgetRunner, action: () -> Void) async {
        let finished = expectation(description: "output \(title) published")
        let observation = runner.$parsedOutput.dropFirst()
            .filter { $0.headerLines.first?.title == title }.prefix(1)
            .sink { _ in finished.fulfill() }
        action()
        await fulfillment(of: [finished], timeout: 2)
        withExtendedLifetime(observation) {}
    }
}
