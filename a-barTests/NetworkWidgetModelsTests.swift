// Purpose: Verify network widget caching, request ordering, and result invalidation after stopping.
//
// Logic:
// 1. Control when asynchronous requests succeed or fail using continuations.
// 2. Check caching, empty results, latest inputs, and serial execution of requests that ignore cancellation.
// 3. Test loaders with a local URLProtocol and temporary scripts without real network requests.
//
// Required input:
// - PollingModel as GitHubModel, WeatherModel and HackerNewsModel, and their loaders.
//
// Expected output:
// - XCTest assertion results; temporary scripts are removed when tests finish.
import Combine
import Foundation
import XCTest

@MainActor
final class NetworkWidgetModelsTests: XCTestCase {
  func testUnchangedSuccessDoesNotPublishValueButStillFinishesAndRecovers() async throws {
    let request = ControlledNetworkRequest<Int>()
    let model = GitHubModel(load: request.load)
    defer { model.stop(); request.cancelRemaining() }

    await start(request) { model.refresh(input: "gh") }
    await complete(.success(3), request, model.$isRefreshing)
    let firstSuccess = try XCTUnwrap(model.lastSuccess)
    var values: [Int?] = []
    var refreshing: [Bool] = []
    var successes: [Date?] = []
    let observations = [
      model.$value.dropFirst().sink { values.append($0) },
      model.$isRefreshing.dropFirst().sink { refreshing.append($0) },
      model.$lastSuccess.dropFirst().sink { successes.append($0) },
    ]
    defer { withExtendedLifetime(observations) {} }

    await start(request) { model.refresh(input: "gh") }
    await complete(.success(3), request, model.$isRefreshing)
    XCTAssertTrue(values.isEmpty)
    XCTAssertGreaterThan(try XCTUnwrap(model.lastSuccess), firstSuccess)

    await start(request) { model.refresh(input: "gh") }
    await complete(.failure(NetworkFixtureError.offline), request, model.$isRefreshing)
    XCTAssertNotNil(model.errorMessage)
    let beforeRecovery = model.lastSuccess
    await start(request) { model.refresh(input: "gh") }
    await complete(.success(3), request, model.$isRefreshing)
    XCTAssertNil(model.errorMessage)
    XCTAssertTrue(values.isEmpty, "recovery must not republish an unchanged cached value")
    XCTAssertNotEqual(model.lastSuccess, beforeRecovery)

    await start(request) { model.refresh(input: "gh") }
    await complete(.success(4), request, model.$isRefreshing)
    XCTAssertEqual(values, [4])
    XCTAssertEqual(refreshing, [true, false, true, false, true, false, true, false])
    XCTAssertEqual(successes.count, 3, "every successful request updates lastSuccess")
  }

  func testGitHubStartIsIdempotentAndChangesOnlyThePollingSchedule() async {
    let request = ControlledNetworkRequest<Int>()
    let model = GitHubModel(load: request.load)
    defer { model.stop(); request.cancelRemaining() }

    await start(request) { model.start(input: " gh ", refreshInterval: 60) }
    await complete(.success(3), request, model.$isRefreshing)
    let lastSuccess = model.lastSuccess
    model.start(input: "gh", refreshInterval: 60)
    model.start(input: "gh", refreshInterval: 30)
    XCTAssertFalse(model.isRefreshing, "repeated starts and interval edits must not request again")
    XCTAssertEqual(request.inputs, ["gh"])
    XCTAssertEqual(model.value, 3)
    XCTAssertEqual(model.lastSuccess, lastSuccess)

    await start(request) {
      model.start(input: "gh", refreshInterval: 0.05)
      XCTAssertFalse(model.isRefreshing, "the next request must come from the new timer")
    }
    XCTAssertEqual(request.inputs, ["gh", "gh"])
    model.stop()
    await complete(.success(99), request, model.$isRefreshing)
    XCTAssertEqual(model.value, 3, "stopping must invalidate an in-flight timer request")
    XCTAssertEqual(model.lastSuccess, lastSuccess)
    await assertNoStarts(request)

    await start(request) { model.start(input: "gh", refreshInterval: 60) }
    XCTAssertEqual(model.value, 3, "resuming keeps the cache while refreshing")
    XCTAssertFalse(model.isLoading)
    await complete(.failure(NetworkFixtureError.offline), request, model.$isRefreshing)
    let error = model.errorMessage
    XCTAssertNotNil(error)
    model.start(input: "gh", refreshInterval: 60)
    XCTAssertFalse(model.isRefreshing, "an unchanged start must also preserve a failed cache")

    model.stop()
    await start(request) { model.start(input: "gh", refreshInterval: 60) }
    XCTAssertEqual(model.value, 3)
    XCTAssertEqual(model.errorMessage, error)
    XCTAssertEqual(model.lastSuccess, lastSuccess)
    await complete(.success(4), request, model.$isRefreshing)
    XCTAssertEqual(model.value, 4)
    XCTAssertNil(model.errorMessage)
    XCTAssertEqual(request.maximumActiveCount, 1)
  }

  func testWeatherStartUsesLatestInputAcrossTimerTicksAndPreservesCacheOnResume() async {
    let request = ControlledNetworkRequest<WeatherSnapshot>()
    let model = WeatherModel(load: request.load)
    defer { model.stop(); request.cancelRemaining() }

    await start(request) { model.start(input: " Lyon ", refreshInterval: 0.05) }
    model.start(input: "Lyon", refreshInterval: 0.05)
    model.start(input: "Paris", refreshInterval: 0.05)
    model.start(input: "Tokyo", refreshInterval: 0.05)
    // Let the existing timer tick while its old request ignores cancellation. It must read
    // the latest input instead of restoring the location captured when the timer was made.
    await assertNoStarts(request)
    await start(request) { request.complete(.success(weather("Lyon", celsius: 20))) }
    XCTAssertEqual(request.inputs, ["Lyon", "Tokyo"])
    XCTAssertNil(model.value)
    model.start(input: "Tokyo", refreshInterval: 60)
    let cached = weather("Tokyo", celsius: 25)
    await complete(.success(cached), request, model.$isRefreshing)
    let lastSuccess = model.lastSuccess

    model.start(input: "Tokyo", refreshInterval: 60)
    model.start(input: "Tokyo", refreshInterval: 30)
    XCTAssertFalse(model.isRefreshing)
    XCTAssertEqual(request.inputs, ["Lyon", "Tokyo"])
    XCTAssertEqual(model.value, cached)
    await start(request) {
      model.start(input: "Tokyo", refreshInterval: 0.05)
      XCTAssertFalse(model.isRefreshing)
    }
    model.stop()
    await complete(.success(weather("Old result", celsius: 1)), request, model.$isRefreshing)
    XCTAssertEqual(model.value, cached)
    XCTAssertEqual(model.lastSuccess, lastSuccess)
    await assertNoStarts(request)

    await start(request) { model.start(input: "Tokyo", refreshInterval: 60) }
    XCTAssertEqual(model.value, cached)
    XCTAssertFalse(model.isLoading)
    await complete(.failure(NetworkFixtureError.offline), request, model.$isRefreshing)
    XCTAssertEqual(model.value, cached)
    XCTAssertEqual(model.lastSuccess, lastSuccess)
    XCTAssertNotNil(model.errorMessage)
    XCTAssertEqual(request.maximumActiveCount, 1)
  }

  func testWeatherKeepsItsSnapshotOnFailureAndIgnoresCompletionAfterStop() async {
    let request = ControlledNetworkRequest<WeatherSnapshot>()
    let model = WeatherModel(load: request.load)
    defer { model.stop(); request.cancelRemaining() }

    await start(request) { model.refresh(input: "") }
    XCTAssertTrue(model.isLoading)
    await complete(.failure(NetworkFixtureError.offline), request, model.$isRefreshing)
    XCTAssertNil(model.value, "an initial failure is not a default city's weather")
    XCTAssertNil(model.lastSuccess)
    XCTAssertNotNil(model.errorMessage)
    XCTAssertFalse(model.isLoading)

    let cached = weather("Lyon", celsius: 20)
    await start(request) { model.refresh(input: "") }
    await complete(.success(cached), request, model.$isRefreshing)
    XCTAssertEqual(model.value, cached)
    XCTAssertNil(model.errorMessage)
    let lastSuccess = model.lastSuccess
    XCTAssertNotNil(lastSuccess)

    await start(request) { model.refresh(input: "") }
    XCTAssertTrue(model.isRefreshing)
    XCTAssertFalse(model.isLoading, "refreshing a cache must not replace it with a spinner")
    XCTAssertEqual(model.value, cached)
    await complete(.failure(NetworkFixtureError.offline), request, model.$isRefreshing)
    XCTAssertEqual(model.value, cached, "location and weather stay together on failure")
    XCTAssertEqual(model.lastSuccess, lastSuccess)
    let error = model.errorMessage
    XCTAssertNotNil(error)

    await start(request) { model.refresh(input: "") }
    model.stop()
    XCTAssertFalse(model.isRefreshing)
    await complete(.success(weather("London", celsius: 5)), request, model.$isRefreshing)
    XCTAssertEqual(model.value, cached)
    XCTAssertEqual(model.lastSuccess, lastSuccess)
    XCTAssertEqual(model.errorMessage, error)
    XCTAssertEqual(request.maximumActiveCount, 1)
  }

  func testWeatherCoalescesSameLocationAndWaitsBeforeLoadingOnlyTheLatestLocation() async {
    let request = ControlledNetworkRequest<WeatherSnapshot>()
    let model = WeatherModel(load: request.load)
    defer { model.stop(); request.cancelRemaining() }

    await start(request) { model.refresh(input: " Lyon ") }
    for _ in 0..<10 { model.refresh(input: "Lyon") }
    model.refresh(input: "Paris")
    model.refresh(input: "Tokyo")
    XCTAssertEqual(request.inputs, ["Lyon"])

    await start(request) { request.complete(.success(weather("Lyon", celsius: 20))) }
    XCTAssertEqual(request.inputs, ["Lyon", "Tokyo"], "intermediate inputs must not start")
    XCTAssertNil(model.value, "the old city's completion cannot publish for the new input")
    XCTAssertNil(model.lastSuccess)
    XCTAssertNil(model.errorMessage)
    XCTAssertEqual(request.maximumActiveCount, 1)
    await complete(.success(weather("Tokyo", celsius: 25)), request, model.$isRefreshing)
    XCTAssertEqual(model.value, weather("Tokyo", celsius: 25))
    XCTAssertEqual(request.inputs.count, 2, "same-input refreshes must not queue another request")
  }

  func testGitHubPreservesCountOnFailureAndOnlySuccessfulEmptyResponseClearsIt() async {
    let request = ControlledNetworkRequest<Int>()
    let model = GitHubModel(load: request.load)
    defer { model.stop(); request.cancelRemaining() }

    await start(request) { model.refresh(input: "gh") }
    XCTAssertTrue(model.isLoading)
    await complete(.failure(NetworkFixtureError.offline), request, model.$isRefreshing)
    XCTAssertNil(model.value, "failure must not look like zero notifications")
    XCTAssertNil(model.lastSuccess)
    XCTAssertNotNil(model.errorMessage)

    await start(request) { model.refresh(input: "gh") }
    await complete(.success(3), request, model.$isRefreshing)
    let lastSuccess = model.lastSuccess
    XCTAssertEqual(model.value, 3)
    XCTAssertNotNil(lastSuccess)
    XCTAssertNil(model.errorMessage)

    await start(request) { model.refresh(input: "gh") }
    let startedCount = request.inputs.count
    for _ in 0..<10 { model.refresh(input: " gh ") }
    XCTAssertEqual(request.inputs.count, startedCount)
    XCTAssertFalse(model.isLoading)
    XCTAssertEqual(model.value, 3)
    await complete(.failure(NetworkFixtureError.offline), request, model.$isRefreshing)
    XCTAssertEqual(model.value, 3)
    XCTAssertEqual(model.lastSuccess, lastSuccess)
    XCTAssertNotNil(model.errorMessage)

    await start(request) { model.refresh(input: "gh") }
    await complete(.success(0), request, model.$isRefreshing)
    XCTAssertEqual(model.value, 0)
    XCTAssertNil(model.errorMessage)
    let emptySuccess = model.lastSuccess
    XCTAssertNotNil(emptySuccess)

    await start(request) { model.refresh(input: "gh") }
    model.stop()
    await complete(.failure(NetworkFixtureError.offline), request, model.$isRefreshing)
    XCTAssertEqual(model.value, 0)
    XCTAssertEqual(model.lastSuccess, emptySuccess)
    XCTAssertNil(model.errorMessage, "a stopped request must not publish an error either")
    XCTAssertEqual(request.maximumActiveCount, 1)
  }

  func testGitHubWaitsForCancelledCLIAndDoesNotOverlapAfterStopAndRestart() async {
    let request = ControlledNetworkRequest<Int>()
    let model = GitHubModel(load: request.load)
    defer { model.stop(); request.cancelRemaining() }

    await start(request) { model.start(input: "/old/gh", refreshInterval: 60) }
    model.start(input: "/middle/gh", refreshInterval: 60)
    model.start(input: "/new/gh", refreshInterval: 60)
    XCTAssertEqual(request.inputs, ["/old/gh"])
    await start(request) { request.complete(.failure(NetworkFixtureError.offline)) }
    XCTAssertEqual(request.inputs, ["/old/gh", "/new/gh"])
    XCTAssertNil(model.value)
    XCTAssertNil(model.errorMessage, "an obsolete executable's error must be discarded")
    XCTAssertNil(model.lastSuccess)
    await complete(.success(6), request, model.$isRefreshing)
    let lastSuccess = model.lastSuccess

    await start(request) { model.refresh(input: "/new/gh") }
    model.stop()
    model.start(input: "/new/gh", refreshInterval: 60)
    XCTAssertEqual(request.inputs.count, 3, "restart must still wait for the old CLI to finish")
    await start(request) { request.complete(.success(99)) }
    XCTAssertEqual(request.inputs.count, 4)
    XCTAssertEqual(model.value, 6, "the stopped request cannot replace the cached count")
    XCTAssertEqual(model.lastSuccess, lastSuccess)
    XCTAssertNil(model.errorMessage)
    await complete(.success(7), request, model.$isRefreshing)
    XCTAssertEqual(model.value, 7)
    XCTAssertEqual(request.maximumActiveCount, 1)
  }

  func testHackerNewsKeepsCacheUntilSuccessfulEmptyResponse() async {
    let request = ControlledNetworkRequest<[HNStory]>()
    let model = HackerNewsModel(load: request.load)
    defer { model.stop(); request.cancelRemaining() }
    let first = story("1"), second = story("2")

    await start(request) { model.refresh(input: "") }
    XCTAssertTrue(model.isLoading)
    await complete(.failure(NetworkFixtureError.offline), request, model.$isRefreshing)
    XCTAssertNil(model.value, "an initial failure is not a successful empty front page")
    XCTAssertNil(model.lastSuccess)
    XCTAssertNotNil(model.errorMessage)

    await start(request) { model.refresh(input: "") }
    await complete(.success([first, second]), request, model.$isRefreshing)
    let lastSuccess = model.lastSuccess
    XCTAssertNotNil(lastSuccess)

    await start(request) { model.refresh(input: "") }
    let startedCount = request.inputs.count
    for _ in 0..<10 { model.refresh(input: "") }
    XCTAssertEqual(request.inputs.count, startedCount)
    XCTAssertFalse(model.isLoading)
    await complete(.failure(NetworkFixtureError.offline), request, model.$isRefreshing)
    XCTAssertEqual(model.value, [first, second])
    XCTAssertEqual(model.lastSuccess, lastSuccess)
    XCTAssertNotNil(model.errorMessage)

    await start(request) { model.refresh(input: "") }
    await complete(.success([]), request, model.$isRefreshing)
    XCTAssertEqual(model.value, [])
    XCTAssertNil(model.errorMessage)
    let emptySuccess = model.lastSuccess

    await start(request) { model.refresh(input: "") }
    model.stop()
    await complete(.success([first]), request, model.$isRefreshing)
    XCTAssertEqual(model.value, [])
    XCTAssertEqual(model.lastSuccess, emptySuccess)
    XCTAssertNil(model.errorMessage)
    XCTAssertEqual(request.maximumActiveCount, 1)
  }

  func testHackerNewsRefreshesOnItsOwnTimer() async {
    let request = ControlledNetworkRequest<[HNStory]>()
    let model = HackerNewsModel(load: request.load)
    defer { model.stop(); request.cancelRemaining() }

    await start(request) { model.start(input: "", refreshInterval: 0.05) }
    await complete(.success([story("1")]), request, model.$isRefreshing)
    // No caller acts here: the next request must come from the model's own timer.
    await start(request) {}
    XCTAssertEqual(request.inputs, ["", ""])
  }

  func testHackerNewsRotationKeepsTheSelectedStoryById() {
    let first = story("1"), second = story("2"), third = story("3")
    XCTAssertNil(HackerNewsRotation.current(nil, in: []))
    XCTAssertNil(HackerNewsRotation.next(after: nil, in: []))
    XCTAssertEqual(HackerNewsRotation.current(nil, in: [first, second]), first)
    XCTAssertEqual(HackerNewsRotation.next(after: nil, in: [first, second]), second)
    XCTAssertEqual(HackerNewsRotation.next(after: "2", in: [first, second]), first, "rotation wraps")
    XCTAssertEqual(HackerNewsRotation.current("2", in: [second, third, first]), second,
                   "reordering must preserve the story by id")
    XCTAssertEqual(HackerNewsRotation.next(after: "2", in: [second, third, first]), third)
    XCTAssertEqual(HackerNewsRotation.current("gone", in: [third, first]), third,
                   "a story that left the front page falls back to the first")
    XCTAssertEqual(HackerNewsRotation.next(after: "gone", in: [third, first]), first)
  }

  func testHackerNewsStopAndRestartWaitsForUncancellableRequest() async {
    let request = ControlledNetworkRequest<[HNStory]>()
    let model = HackerNewsModel(load: request.load)
    defer { model.stop(); request.cancelRemaining() }

    await start(request) { model.refresh(input: "") }
    model.stop()
    model.refresh(input: "")
    for _ in 0..<10 { model.refresh(input: "") }
    XCTAssertEqual(request.inputs.count, 1)
    await start(request) { request.complete(.failure(NetworkFixtureError.offline)) }
    XCTAssertEqual(request.inputs.count, 2)
    XCTAssertNil(model.value)
    XCTAssertNil(model.errorMessage)
    XCTAssertNil(model.lastSuccess)
    let fresh = story("fresh")
    await complete(.success([fresh]), request, model.$isRefreshing)
    XCTAssertEqual(model.value, [fresh])
    XCTAssertEqual(request.inputs.count, 2)
    XCTAssertEqual(request.maximumActiveCount, 1)
  }

  func testWeatherLoaderUsesCelsiusAndDoesNotInventALocationAfterLookupFailure() async throws {
    let session = makeSession { request in
      if request.url?.host == "geocoding-api.open-meteo.com" {
        return (200, Data(#"{"results":[{"latitude":45.75,"longitude":4.85}]}"#.utf8))
      }
      XCTAssertEqual(request.url?.host, "api.open-meteo.com")
      let unit = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
        .queryItems?.first { $0.name == "temperature_unit" }?.value
      XCTAssertEqual(unit, "celsius")
      return (200, Data(#"{"current_weather":{"temperature":20,"weathercode":0,"is_day":1}}"#.utf8))
    }
    defer { session.invalidateAndCancel(); NetworkWidgetURLProtocol.handler = nil }
    let snapshot = try await WeatherForecast.load("Lyon", session: session, resolveLocation: {
      XCTFail("a configured city must not start IP lookup")
      throw NetworkFixtureError.offline
    })
    XCTAssertEqual(snapshot.location, "Lyon")
    XCTAssertEqual(snapshot.data.temperatureC, 20)
    XCTAssertEqual(snapshot.data.temperatureF, 68)
    XCTAssertFalse(snapshot.data.isNight)

    NetworkWidgetURLProtocol.handler = { _ in
      XCTFail("failed IP lookup must not request weather for London or another guessed city")
      throw NetworkFixtureError.offline
    }
    do {
      _ = try await WeatherForecast.load("", session: session, resolveLocation: {
        throw NetworkFixtureError.offline
      })
      XCTFail("location lookup failure must propagate")
    } catch {
      XCTAssertTrue(error is NetworkFixtureError)
    }
  }

  func testWeatherLoaderRejectsHTTPFailureEvenWhenTheBodyLooksLikeWeather() async {
    let session = makeSession { request in
      if request.url?.host == "geocoding-api.open-meteo.com" {
        return (200, Data(#"{"results":[{"latitude":45.75,"longitude":4.85}]}"#.utf8))
      }
      return (503, Data(#"{"current_weather":{"temperature":20,"weathercode":0,"is_day":1}}"#.utf8))
    }
    defer { session.invalidateAndCancel(); NetworkWidgetURLProtocol.handler = nil }
    do {
      _ = try await WeatherForecast.load("Lyon", session: session)
      XCTFail("a failed HTTP response must not replace the cached weather")
    } catch {
      XCTAssertEqual((error as? URLError)?.code, .badServerResponse)
    }
  }

  func testHackerNewsLoaderDistinguishesHTTPFailureMalformedDataAndSuccessfulEmpty() async throws {
    let session = makeSession { _ in (200, Data(#"{"hits":[]}"#.utf8)) }
    defer { session.invalidateAndCancel(); NetworkWidgetURLProtocol.handler = nil }
    let empty = try await HackerNewsFeed.load(session: session)
    XCTAssertTrue(empty.isEmpty)

    NetworkWidgetURLProtocol.handler = { _ in (503, Data(#"{"hits":[]}"#.utf8)) }
    do {
      _ = try await HackerNewsFeed.load(session: session)
      XCTFail("a failed HTTP response is not an empty front page")
    } catch {
      XCTAssertEqual((error as? URLError)?.code, .badServerResponse)
    }

    NetworkWidgetURLProtocol.handler = { _ in (200, Data(#"{"message":"not a front page"}"#.utf8)) }
    do {
      _ = try await HackerNewsFeed.load(session: session)
      XCTFail("malformed data must remain an error")
    } catch {
      XCTAssertTrue(error is DecodingError)
    }

    let valid = story("1")
    let data = try JSONEncoder().encode(HNResponse(hits: [valid, story("2", title: "")]))
    NetworkWidgetURLProtocol.handler = { _ in (200, data) }
    let stories = try await HackerNewsFeed.load(session: session)
    XCTAssertEqual(stories, [valid])
  }

  func testGitHubLoaderDistinguishesNonZeroExitInvalidOutputAndSuccessfulEmpty() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("a-bar-network-loader-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let executable = directory.appendingPathComponent("fake gh")
    func script(_ body: String) throws {
      try ("#!/bin/sh\n# Local test stub: return fixed responses without network access.\n" + body + "\n")
        .write(to: executable, atomically: true, encoding: .utf8)
      try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    }

    try script("[ \"$1\" = api ] && [ \"$2\" = notifications ] || exit 9\nprintf '%s' '[]'")
    let empty = try await GitHubNotifications.load(executable.path)
    XCTAssertEqual(empty, 0)
    try script("printf '%s' '[{\"id\":\"1\"},{\"id\":\"2\"}]'\nprintf '%s' 'fixture diagnostic' >&2")
    let count = try await GitHubNotifications.load(executable.path)
    XCTAssertEqual(count, 2)

    try script("printf '%s' '[]'\nexit 7")
    do {
      _ = try await GitHubNotifications.load(executable.path)
      XCTFail("valid-looking stdout must not hide a failed command")
    } catch {
      XCTAssertEqual((error as NSError).domain, "ShellExecutor")
      XCTAssertEqual((error as NSError).code, 7)
    }
    try script("printf '%s' '{\"message\":\"not a notifications array\"}'")
    do {
      _ = try await GitHubNotifications.load(executable.path)
      XCTFail("invalid notification output is not zero unread notifications")
    } catch {
      XCTAssertEqual((error as NSError).domain, "GitHub")
    }
  }

  private func assertNoStarts<Value>(_ request: ControlledNetworkRequest<Value>) async {
    let unexpected = expectation(description: "no additional loader starts")
    unexpected.isInverted = true
    request.onStart = { unexpected.fulfill() }
    await fulfillment(of: [unexpected], timeout: 0.12)
    request.onStart = nil
  }

  // Wait for the injected loader to enter, not an arbitrary delay or a network timeout.
  private func start<Value>(
    _ request: ControlledNetworkRequest<Value>, action: () -> Void
  ) async {
    let started = expectation(description: "loader entered")
    request.onStart = { started.fulfill() }
    action()
    await fulfillment(of: [started], timeout: 2)
    request.onStart = nil
  }

  // @Published emits before assigning its property. The test resumes on MainActor after
  // finish() returns, so assertions observe the complete snapshot, error and timestamp update.
  private func complete<Value>(
    _ result: Result<Value, Error>, _ request: ControlledNetworkRequest<Value>,
    _ refreshing: Published<Bool>.Publisher
  ) async {
    let finished = expectation(description: "model finished request")
    let observation = refreshing.dropFirst().filter { !$0 }.prefix(1)
      .sink { _ in finished.fulfill() }
    request.complete(result)
    await fulfillment(of: [finished], timeout: 2)
    withExtendedLifetime(observation) {}
  }

  private func weather(_ location: String, celsius: Int) -> WeatherSnapshot {
    WeatherSnapshot(location: location, data: WeatherData(
      temperatureC: celsius, temperatureF: celsius * 9 / 5 + 32,
      description: "Clear sky", isNight: false))
  }

  private func story(_ id: String, title: String? = "Story") -> HNStory {
    HNStory(objectID: id, title: title, urlString: "https://example.invalid/\(id)",
            points: 1, author: "fixture", numComments: 0, createdAt: "2026-10-01T00:00:00Z")
  }

  private func makeSession(
    _ handler: @escaping (URLRequest) throws -> (Int, Data)
  ) -> URLSession {
    NetworkWidgetURLProtocol.handler = handler
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [NetworkWidgetURLProtocol.self]
    return URLSession(configuration: configuration)
  }
}

private enum NetworkFixtureError: Error {
  case offline
}

// Intentionally ignores Task cancellation, matching a CLI that must finish before replacement.
@MainActor
final class ControlledNetworkRequest<Value> {
  private(set) var inputs: [String] = []
  private(set) var maximumActiveCount = 0
  private var activeCount = 0
  private var pending: [CheckedContinuation<Value, Error>] = []
  var onStart: (() -> Void)?

  func load(_ input: String) async throws -> Value {
    inputs.append(input)
    activeCount += 1
    maximumActiveCount = max(maximumActiveCount, activeCount)
    defer { activeCount -= 1 }
    return try await withCheckedThrowingContinuation { continuation in
      pending.append(continuation)
      onStart?()
    }
  }

  func complete(_ result: Result<Value, Error>) {
    guard !pending.isEmpty else {
      XCTFail("no pending request to complete")
      return
    }
    pending.removeFirst().resume(with: result)
  }

  func cancelRemaining() {
    let continuations = pending
    pending.removeAll()
    continuations.forEach { $0.resume(throwing: CancellationError()) }
  }
}

private final class NetworkWidgetURLProtocol: URLProtocol {
  // XCTest runs this test case's methods serially; no other tests use this protocol class.
  static var handler: ((URLRequest) throws -> (Int, Data))?

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    do {
      guard let handler = Self.handler, let url = request.url else {
        throw NetworkFixtureError.offline
      }
      let (status, data) = try handler(request)
      let response = HTTPURLResponse(
        url: url, statusCode: status, httpVersion: nil,
        headerFields: ["Content-Type": "application/json"])!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}
}
