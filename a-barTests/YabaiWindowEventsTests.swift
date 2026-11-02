import ApplicationServices
import XCTest

final class YabaiWindowEventsTests: XCTestCase {
    final class Backend {
        struct Callback {
            let loop: CFRunLoop
            let receive: (YabaiWindowEvents.Event) -> Void
        }
        private let lock = NSLock()
        private var callbacks: [pid_t: Callback] = [:]
        private var registrations: [pid_t] = []
        private var cancellations: [pid_t] = []
        private var remainingFailures: Int
        private var titleValue: String?
        private var firstSubscription: (() -> Void)?

        func onFirstSubscription(_ action: @escaping () -> Void) {
            lock.lock(); firstSubscription = action; lock.unlock()
        }

        init(failures: Int = 0, title: String? = nil) {
            remainingFailures = failures
            titleValue = title
        }
        var title: String? {
            get { lock.lock(); defer { lock.unlock() }; return titleValue }
            set { lock.lock(); titleValue = newValue; lock.unlock() }
        }

        var registered: [pid_t] { lock.lock(); defer { lock.unlock() }; return registrations }
        var cancelled: [pid_t] { lock.lock(); defer { lock.unlock() }; return cancellations }

        func subscribe(_ pid: pid_t, _ receive: @escaping (YabaiWindowEvents.Event) -> Void) -> (() -> Void)? {
            lock.lock()
            registrations.append(pid)
            if remainingFailures > 0 {
                remainingFailures -= 1
                lock.unlock()
                return nil
            }
            callbacks[pid] = Callback(loop: CFRunLoopGetCurrent(), receive: receive)
            let ready = firstSubscription
            firstSubscription = nil
            lock.unlock()
            ready?()
            return { [self] in
                lock.lock(); cancellations.append(pid); lock.unlock()
            }
        }

        func emitInline(_ event: YabaiWindowEvents.Event, pid: pid_t = 123) {
            lock.lock(); let callback = callbacks[pid]!; lock.unlock()
            callback.receive(event)
        }

        func emit(_ event: YabaiWindowEvents.Event, pid: pid_t = 123) {
            lock.lock(); let callback = callbacks[pid]!; lock.unlock()
            CFRunLoopPerformBlock(callback.loop, CFRunLoopMode.defaultMode.rawValue) { callback.receive(event) }
            CFRunLoopWakeUp(callback.loop)
        }
    }

    private func windows(_ ids: [Int], pid: Int = 123) throws -> [YabaiWindow] {
        try ids.map { id in
            let json = """
            {"id":\(id),"pid":\(pid),"app":"Fixture","title":"A","space":1,"display":1,"frame":{"x":0,"y":0,"w":100,"h":100}}
            """
            return try JSONDecoder().decode(YabaiWindow.self, from: Data(json.utf8))
        }
    }

    @MainActor
    private func waitFor(_ predicate: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(2)
        while !predicate() && Date() < deadline { try? await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertTrue(predicate(), file: file, line: line)
    }

    @MainActor
    func testOneSubscriptionPerAppTracksNewWindowsAndStopsRemovedApps() async throws {
        let backend = Backend()
        let events = YabaiWindowEvents(trusted: { true }, subscribe: backend.subscribe)
        events.start { _ in }
        events.update(try windows([10]))
        await waitFor { backend.registered == [123] }
        events.update(try windows([10, 11]))
        events.update(try windows([10, 11]) + windows([20], pid: 456))
        await waitFor { backend.registered.count == 2 }
        XCTAssertEqual(Set(backend.registered), [123, 456])
        events.update(try windows([20], pid: 456))
        await waitFor { backend.cancelled == [123] }
        events.stop()
        await waitFor { backend.cancelled.count == 2 }
        XCTAssertEqual(Set(backend.cancelled), [123, 456])
    }

    @MainActor
    func testRepeatedTitlesAreIgnoredAndMovesDoNotReadTitles() async throws {
        let backend = Backend()
        let events = YabaiWindowEvents(trusted: { true }, subscribe: backend.subscribe)
        var moves = 0, titles = 0
        events.start {
            switch $0 {
            case .moved: moves += 1
            case .titleChanged: titles += 1
            default: break
            }
        }
        events.update(try windows([10]))
        await waitFor { backend.registered.count == 1 }
        let element = AXUIElementCreateApplication(123)
        backend.emit(.titleChanged(id: 10, pid: 123, element: element, title: "A"))
        backend.emit(.titleChanged(id: 10, pid: 123, element: element, title: "A"))
        backend.emit(.titleChanged(id: 10, pid: 123, element: element, title: "B"))
        backend.emit(.titleChanged(id: 10, pid: 123, element: element, title: nil))
        backend.emit(.titleChanged(id: 10, pid: 123, element: element, title: nil))
        backend.emit(.moved)
        await waitFor { moves == 1 }
        XCTAssertEqual(titles, 4, "failed reads must not be treated as an acknowledged title")
        events.stop()
        await waitFor { backend.cancelled.count == 1 }
    }

    @MainActor
    func testPermissionChangesAndLateCallbacksCannotRestartStoppedObserver() async throws {
        let backend = Backend()
        var trusted = false, delivered = 0
        let events = YabaiWindowEvents(trusted: { trusted }, subscribe: backend.subscribe)
        events.start { if case .moved = $0 { delivered += 1 } }
        events.update(try windows([10]))
        XCTAssertTrue(backend.registered.isEmpty)
        trusted = true
        events.update(try windows([10]))
        await waitFor { backend.registered.count == 1 }
        backend.emit(.moved)
        events.stop()
        await waitFor { backend.cancelled.count == 1 }
        XCTAssertEqual(delivered, 0)
        events.update(try windows([10]))
        XCTAssertEqual(backend.registered.count, 1)
        events.start { if case .moved = $0 { delivered += 1 } }
        events.update(try windows([10]))
        await waitFor { backend.registered.count == 2 }
        trusted = false
        events.update(try windows([10]))
        await waitFor { backend.cancelled.count == 2 }
        events.stop()
    }
    @MainActor
    func testFailedSubscriptionRetriesAndResynchronizesAfterSuccess() async throws {
        let backend = Backend(failures: 1)
        let events = YabaiWindowEvents(trusted: { true }, subscribe: backend.subscribe)
        var recovered = 0
        events.start { if case .resynchronized = $0 { recovered += 1 } }
        events.update(try windows([10]))
        await waitFor { backend.registered.count == 1 }
        XCTAssertEqual(recovered, 0)
        events.update(try windows([10]))
        await waitFor { recovered == 1 }
        XCTAssertEqual(backend.registered.count, 2)
        events.stop()
        await waitFor { backend.cancelled.count == 1 }
    }

    @MainActor
    func testSuccessfulBackgroundReadInvalidatesEventDeduplication() async throws {
        let backend = Backend(title: "C")
        let events = YabaiWindowEvents(trusted: { true }, subscribe: backend.subscribe,
                                       titleReader: { _ in backend.title })
        var titles: [String] = []
        events.start {
            if case .titleChanged(_, _, _, let title) = $0, let title { titles.append(title) }
        }
        events.update(try windows([10]))
        await waitFor { backend.registered.count == 1 }
        let element = AXUIElementCreateApplication(123)
        backend.emit(.titleChanged(id: 10, pid: 123, element: element, title: "B"))
        await waitFor { titles == ["B"] }
        let confirmed = await events.readTitle(element)
        XCTAssertEqual(confirmed, "C")
        backend.emit(.titleChanged(id: 10, pid: 123, element: element, title: "B"))
        await waitFor { titles == ["B", "B"] }
        events.stop()
        await waitFor { backend.cancelled.count == 1 }
    }

    func testMissingOrInvalidWindowIDBridgeCannotGuessAnIdentity() {
        let element = AXUIElementCreateApplication(123)
        XCTAssertNil(YabaiWindowEvents.windowID(for: element, using: nil))
        XCTAssertNil(YabaiWindowEvents.windowID(for: element, using: { _, id in
            id.pointee = 0
            return AXError.success.rawValue
        }))
        XCTAssertNil(YabaiWindowEvents.windowID(for: element, using: { _, id in
            id.pointee = 10
            return AXError.cannotComplete.rawValue
        }))
        XCTAssertEqual(YabaiWindowEvents.windowID(for: element, using: { _, id in
            id.pointee = 10
            return AXError.success.rawValue
        }), 10)
    }

}
