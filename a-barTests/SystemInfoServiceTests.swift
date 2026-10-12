import AppKit
import Carbon
import CoreAudio
import Combine
import XCTest

/// `SystemInfoService` is a wrapper around read-only system calls - IOKit power sources, mach
/// host statistics, CoreAudio device properties, the IORegistry, CoreFoundation's text input
/// sources. The arithmetic on top of them has been lifted into `Logic/` and is tested there
/// exhaustively; what is left here can only be checked by actually calling it.
///
/// So these tests run the real readings and assert the invariants that hold on any Mac,
/// including a headless CI runner with no battery, no GPU registry entry and no audio device:
/// the call returns, it does not trap, and the published value is inside its documented range.
/// That is worth having - most of what can go wrong in this file is a force-unwrap or a
/// misjudged buffer size on hardware the author did not have.
///
/// Nothing here mutates machine state. The volume, mute and caffeinate *setters* are
/// deliberately never called.
final class SystemInfoServiceTests: XCTestCase {
    private var directory: URL!
    private var manager: SettingsManager!
    private var service: SystemInfoService!
    private var observations = Set<AnyCancellable>()

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("abar-sysinfo-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let config = directory.appendingPathComponent("config.json")
        try SettingsCodec.encode(ABarSettings()).write(to: config)
        manager = SettingsManager(store: SettingsStore(fileURL: config))
        service = SystemInfoService(settingsManager: manager)
    }

    override func tearDownWithError() throws {
        observations.removeAll()
        service.stop()
        service = nil
        manager.flush()
        try? FileManager.default.removeItem(at: directory)
    }

    /// Give an asynchronous reading a chance to land, without requiring that it changed -
    /// on a machine where the value is already correct, nothing is published.
    private func settle(_ interval: TimeInterval = 0.6) {
        let done = expectation(description: "settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) { done.fulfill() }
        wait(for: [done], timeout: interval + 5)
    }

    // MARK: - Individual readings

    func testBatteryReadingStaysWithinItsRange() {
        service.start(widgets: [.battery])
        settle(0.1)
        service.refreshBattery()
        settle()

        XCTAssertTrue((0...100).contains(service.batteryInfo.percentage),
                      "a machine with no battery reports the default, not nonsense")
    }

    func testCpuReadingStaysWithinItsRange() {
        service.start(widgets: [.cpu])
        settle(0.1)
        // The first reading has nothing to diff against and is defined to be 0.
        service.refreshCPU()
        settle()
        service.refreshCPU()
        settle()

        XCTAssertTrue((0...100).contains(service.cpuUsage), "got \(service.cpuUsage)")
    }

    func testCpuHistoryGrowsAsReadingsArrive() {
        service.start(widgets: [.cpu])
        settle(0.1)
        let before = service.cpuHistory.values.count
        service.refreshCPU()
        settle()

        XCTAssertGreaterThan(service.cpuHistory.values.count, before)
    }

    func testMemoryReadingIsAPlausiblePercentage() {
        service.start(widgets: [.memory])
        settle(0.1)
        service.refreshMemory()
        settle()

        XCTAssertGreaterThan(service.memoryPressure, 0, "a running Mac is using some memory")
        XCTAssertLessThanOrEqual(service.memoryPressure, 100)
    }

    func testGpuReadingStaysWithinItsRange() {
        service.start(widgets: [.gpu])
        settle(0.1)
        service.refreshGPU()
        settle()

        XCTAssertTrue((0...100).contains(service.gpuUsage),
                      "a VM with no GPU registry entry reports 0, not a crash")
    }

    func testTheFirstNetworkReadingReportsNoTrafficRatherThanTheCounterSinceBoot() {
        service.start(widgets: [.netstats])
        // The counters are cumulative. Publishing the first one as a rate would show several
        // gigabytes per second on the bar for one tick after launch.
        settle()

        XCTAssertEqual(service.networkStats, NetworkStats())
        XCTAssertFalse(service.networkStats.formattedDownload.isEmpty)
    }

    func testASecondNetworkReadingProducesAPlausibleRate() {
        service.start(widgets: [.netstats])
        settle(0.1)
        service.refreshNetworkStats()
        settle()
        service.refreshNetworkStats()
        settle()

        // An idle machine may genuinely move nothing; a terabyte per second means the delta
        // maths wrapped.
        XCTAssertLessThan(service.networkStats.download, 1_000_000_000_000)
        XCTAssertLessThan(service.networkStats.upload, 1_000_000_000_000)
    }

    func testTheFirstDiskReadingReportsNoActivity() {
        service.start(widgets: [.diskActivity])
        settle()

        XCTAssertEqual(service.diskStats, DiskIOStats())
        XCTAssertFalse(service.diskStats.formattedRead.isEmpty)
    }

    func testASecondDiskReadingProducesAPlausibleRate() {
        service.start(widgets: [.diskActivity])
        settle(0.1)
        service.refreshDiskStats()
        settle()
        service.refreshDiskStats()
        settle()

        XCTAssertLessThan(service.diskStats.read, 1_000_000_000_000)
        XCTAssertLessThan(service.diskStats.write, 1_000_000_000_000)
    }

    func testVolumeReadingStaysWithinItsRange() {
        service.start(widgets: [.sound])
        settle(0.1)
        service.refreshVolume()
        settle()

        XCTAssertTrue((0...1).contains(service.volumeLevel), "got \(service.volumeLevel)")
    }

    func testMicReadingStaysWithinItsRange() {
        service.start(widgets: [.mic])
        settle(0.1)
        service.refreshMic()
        settle()

        XCTAssertTrue((0...1).contains(service.micLevel), "got \(service.micLevel)")
    }

    func testKeyboardLayoutIsRead() {
        service.start(widgets: [.keyboard])
        settle(0.1)
        service.refreshKeyboard()
        settle()

        // A headless runner can legitimately have no input source, so an empty string is a
        // valid answer; what matters is that reading it does not trap.
        XCTAssertNotNil(service.keyboardLayout)
    }

    func testCaffeinateStateIsReadFromTheWholeMachine() {
        service.start(widgets: [.battery])
        settle(0.1)
        // The reading is a `pgrep` for any `caffeinate` process, not only one this service
        // started - so whether it comes back true depends on what else is running, and the
        // assertion can only be that reading it works and settles on one answer.
        service.refreshCaffeinate()
        settle()
        let first = service.isCaffeinateActive

        service.refreshCaffeinate()
        settle()

        XCTAssertEqual(service.isCaffeinateActive, first, "the reading is stable")
    }

    func testMountedVolumesAreEnumerated() {
        service.start(widgets: [.storage])
        settle()
        service.stop()

        // The boot volume is always mounted, so there is at least one - but a sandboxed
        // runner may report none, and that is not a failure of this code.
        for volume in service.volumes {
            XCTAssertFalse(volume.name.isEmpty)
            XCTAssertGreaterThan(volume.totalBytes, 0)
            XCTAssertLessThanOrEqual(volume.usedBytes, volume.totalBytes)
        }
    }

    // MARK: - Lifecycle

    func testStartingCollectsForEveryActiveWidget() {
        service.start(widgets: [.cpu, .memory, .battery])
        settle()
        service.stop()

        XCTAssertGreaterThan(service.memoryPressure, 0, "the memory reading ran")
        XCTAssertFalse(service.cpuHistory.values.isEmpty, "the cpu reading ran")
    }

    func testStartingWithNoWidgetsDoesNothingAndDoesNotTrap() {
        service.start(widgets: [])
        settle(0.2)
        service.stop()
    }

    func testStartingWithOnlyNonSystemWidgetsSchedulesNothing() {
        // The clock and the window-manager widgets are driven elsewhere.
        service.start(widgets: [.time, .date, .spaces])
        settle(0.2)
        service.stop()
    }

    func testStoppingAndStartingAgainIsSafe() {
        service.start(widgets: [.cpu])
        service.stop()
        service.start(widgets: [.memory])
        settle()
        service.stop()

        XCTAssertGreaterThan(service.memoryPressure, 0)
    }

    func testStoppingTwiceIsSafe() {
        service.start(widgets: [.cpu])
        service.stop()
        service.stop()
    }

    func testAWidgetKeepsRefreshingRatherThanRunningOnce() {
        manager.update { $0.widgets.cpu.refreshInterval = 0.2 }
        service.start(widgets: [.cpu])
        settle(0.8)
        let afterFirstWindow = service.cpuHistory.values.count
        settle(0.8)
        let afterSecondWindow = service.cpuHistory.values.count
        service.stop()

        XCTAssertGreaterThan(afterFirstWindow, 0, "the initial collection ran")
        XCTAssertGreaterThan(afterSecondWindow, afterFirstWindow,
                             "a bar that stops updating after launch is the bug here")
    }

    func testStoppingHaltsTheTimers() {
        manager.update { $0.widgets.cpu.refreshInterval = 0.2 }
        service.start(widgets: [.cpu])
        settle(0.5)

        service.stop()
        // Both queued reads and publication are generation-bound. A stopped consumer
        // must not receive an in-flight result or another timer tick.
        settle(0.5)
        let afterInFlightWorkLanded = service.cpuHistory.values.count
        settle(0.8)

        XCTAssertEqual(service.cpuHistory.values.count, afterInFlightWorkLanded,
                       "a timer surviving stop() keeps forking work for a hidden bar")
    }

    private final class ReadCounts {
        private let lock = NSLock()
        private var values: [WidgetRefreshSchedule.Reading: Int] = [:]
        func add(_ reading: WidgetRefreshSchedule.Reading) {
            lock.lock(); defer { lock.unlock() }
            values[reading, default: 0] += 1
        }
        func count(_ reading: WidgetRefreshSchedule.Reading) -> Int {
            lock.lock(); defer { lock.unlock() }
            return values[reading, default: 0]
        }
    }

    private final class AudioFixture {
        struct Token {
            let object: AudioObjectID
            let address: AudioObjectPropertyAddress
            let callback: AudioObjectPropertyListenerBlock
            func fire() {
                var address = address
                withUnsafePointer(to: &address) { callback(1, $0) }
            }
        }
        var device: AudioObjectID = 100
        var failDeviceListeners = false
        var omitMaster = false
        var tokens: [Token] = []
        var removed: [Token] = []
        var backend: AudioPropertyEvents {
            AudioPropertyEvents(
                hasProperty: { [weak self] _, address in
                    !(self?.omitMaster == true && address.mSelector == kAudioDevicePropertyVolumeScalar
                      && address.mElement == kAudioObjectPropertyElementMain)
                },
                add: { [weak self] object, address, callback in
                    guard let self else { return -50 }
                    if self.failDeviceListeners && object != AudioObjectID(kAudioObjectSystemObject) { return -50 }
                    self.tokens.append(Token(object: object, address: address, callback: callback))
                    return noErr
                },
                remove: { [weak self] object, address, _ in
                    guard let self else { return }
                    if let token = self.tokens.first(where: {
                        $0.object == object && $0.address.mSelector == address.mSelector
                        && $0.address.mScope == address.mScope && $0.address.mElement == address.mElement
                    }) { self.removed.append(token) }
                })
        }
    }

    func testHiddenConsumersDoNotReadAndQueuedStopCannotPublish() {
        let queue = DispatchQueue(label: "a-bar-paused-readings")
        let counts = ReadCounts()
        service = SystemInfoService(settingsManager: manager, readingQueue: queue, onRead: counts.add)
        queue.suspend()
        service.start(widgets: [.cpu, .memory, .storage])
        service.stop()
        queue.resume()
        settle(0.2)
        service.refresh()
        service.refreshCPU()
        service.refreshMemory()
        settle(0.2)
        XCTAssertEqual(counts.count(.cpu), 0)
        XCTAssertEqual(counts.count(.memory), 0)
        XCTAssertEqual(counts.count(.storageVolumes), 0)
        XCTAssertTrue(service.cpuHistory.values.isEmpty)
        XCTAssertEqual(service.memoryPressure, 0)
        XCTAssertTrue(service.volumes.isEmpty)
    }

    func testAudioEventsReplacePollingAndRebindWithoutAcceptingOldCallbacks() throws {
        let audio = AudioFixture()
        let counts = ReadCounts()
        manager.update { $0.widgets.sound.refreshInterval = 0.5 }
        service = SystemInfoService(settingsManager: manager, audioEvents: audio.backend,
            eventAudioDevice: { _ in audio.device }, onRead: counts.add)
        service.start(widgets: [.sound])
        settle(0.15)
        let firstTokens = audio.tokens
        let firstReads = counts.count(.volume)
        XCTAssertEqual(firstReads, 1)
        // Observe channels even when master is advertised: reading it can still fail.
        let channels = firstTokens.filter { $0.object == 100 && $0.address.mSelector == kAudioDevicePropertyVolumeScalar }
        XCTAssertEqual(Set(channels.map { $0.address.mElement }), [0, 1, 2])
        service.start(widgets: [.sound])
        settle(0.65)
        XCTAssertEqual(audio.tokens.count, firstTokens.count)
        XCTAssertEqual(counts.count(.volume), firstReads, "successful listeners replace the 0.5s timer")
        try XCTUnwrap(channels.first { $0.address.mElement == 1 }).fire()
        settle(0.15)
        XCTAssertEqual(counts.count(.volume), firstReads + 1)
        audio.device = 101
        try XCTUnwrap(firstTokens.first { $0.object == AudioObjectID(kAudioObjectSystemObject) }).fire()
        settle(0.15)
        XCTAssertEqual(audio.removed.count, firstTokens.count)
        XCTAssertTrue(audio.tokens.contains { $0.object == 101 })
        let afterRebind = counts.count(.volume)
        channels.forEach { $0.fire() }
        settle(0.15)
        XCTAssertEqual(counts.count(.volume), afterRebind)
        service.stop()
        audio.tokens.forEach { $0.fire() }
        settle(0.65)
        XCTAssertEqual(counts.count(.volume), afterRebind)
    }

    func testUnavailableAudioListenersUseOnlyVisibleFallbackTimers() {
        let audio = AudioFixture()
        audio.failDeviceListeners = true
        audio.omitMaster = true
        let counts = ReadCounts()
        manager.update { $0.widgets.sound.refreshInterval = 0.5 }
        service = SystemInfoService(settingsManager: manager, audioEvents: audio.backend,
            eventAudioDevice: { _ in audio.device }, onRead: counts.add)
        service.start(widgets: [.sound])
        settle(0.7)
        XCTAssertGreaterThanOrEqual(counts.count(.volume), 2)
        XCTAssertEqual(counts.count(.mic), 0)
        service.stop()
        let stopped = counts.count(.volume)
        settle(0.65)
        XCTAssertEqual(counts.count(.volume), stopped)
    }

    func testAnAudioEventRacingPublicationRunsOneLatestFollowUp() throws {
        let audio = AudioFixture()
        let counts = ReadCounts()
        let started = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let latest = expectation(description: "latest event reading")
        service = SystemInfoService(settingsManager: manager, audioEvents: audio.backend,
            eventAudioDevice: { _ in audio.device }, onRead: { reading in
                counts.add(reading)
                if reading == .volume {
                    if counts.count(.volume) == 1 {
                        started.signal()
                        _ = release.wait(timeout: .now() + 5)
                    } else if counts.count(.volume) == 2 { latest.fulfill() }
                }
            })
        service.start(widgets: [.sound])
        XCTAssertEqual(started.wait(timeout: .now() + 2), .success)
        let event = try XCTUnwrap(audio.tokens.first { $0.object == 100 && $0.address.mSelector == kAudioDevicePropertyMute })
        for _ in 0..<5 { event.fire() }
        release.signal()
        wait(for: [latest], timeout: 5)
        XCTAssertEqual(counts.count(.volume), 2, "an event burst coalesces into one latest follow-up")
    }

    func testStoppingAnInFlightReadDropsPublicationAndItsQueuedFollowUp() {
        let counts = ReadCounts()
        let started = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        service = SystemInfoService(settingsManager: manager, onRead: { reading in
            counts.add(reading)
            if reading == .cpu {
                started.signal()
                _ = release.wait(timeout: .now() + 5)
            }
        })
        service.start(widgets: [.cpu])
        XCTAssertEqual(started.wait(timeout: .now() + 2), .success)
        service.refreshCPU()
        service.stop()
        release.signal()
        settle(0.3)
        XCTAssertEqual(counts.count(.cpu), 1)
        XCTAssertTrue(service.cpuHistory.values.isEmpty)
        XCTAssertEqual(service.cpuUsage, 0)
    }

    func testKeyboardAndMountObserversFollowDemandAndNoKeyboardTimerRemains() {
        let counts = ReadCounts()
        // 私有通知中心隔离桌面事件，避免读次数受真实输入源切换干扰。
        let keyboardNotifications = NotificationCenter()
        let workspaceNotifications = NotificationCenter()
        manager.update { $0.widgets.keyboard.refreshInterval = 1 }
        service = SystemInfoService(settingsManager: manager, onRead: counts.add,
            keyboardNotifications: keyboardNotifications, workspaceNotifications: workspaceNotifications)
        service.start(widgets: [.keyboard, .storage])
        settle(0.15)
        let firstKeyboard = counts.count(.keyboard)
        let firstStorage = counts.count(.storageVolumes)
        service.start(widgets: [.keyboard, .storage])
        keyboardNotifications.post(name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil)
        workspaceNotifications.post(name: NSWorkspace.didMountNotification, object: nil)
        settle(0.2)
        XCTAssertEqual(counts.count(.keyboard), firstKeyboard + 1)
        XCTAssertEqual(counts.count(.storageVolumes), firstStorage + 1)
        let observed = counts.count(.keyboard)
        settle(1.05)
        XCTAssertEqual(counts.count(.keyboard), observed)
        service.stop()
        let stoppedStorage = counts.count(.storageVolumes)
        keyboardNotifications.post(name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil)
        workspaceNotifications.post(name: NSWorkspace.didMountNotification, object: nil)
        settle(0.2)
        XCTAssertEqual(counts.count(.keyboard), observed)
        XCTAssertEqual(counts.count(.storageVolumes), stoppedStorage)
    }

    func testPowerListenerFailureKeepsBatteryAndCaffeinateFallbackUntilHidden() {
        let counts = ReadCounts()
        manager.update { $0.widgets.battery.refreshInterval = 1 }
        service = SystemInfoService(settingsManager: manager, onRead: counts.add,
            makePowerSource: { _, _ in nil })
        service.start(widgets: [.battery])
        settle(1.2)
        XCTAssertGreaterThanOrEqual(counts.count(.battery), 2)
        XCTAssertGreaterThanOrEqual(counts.count(.caffeinate), 2)
        NotificationCenter.default.post(name: .NSProcessInfoPowerStateDidChange, object: nil)
        settle(0.15)
        let stopped = counts.count(.battery)
        service.stop()
        NotificationCenter.default.post(name: .NSProcessInfoPowerStateDidChange, object: nil)
        settle(1.05)
        XCTAssertEqual(counts.count(.battery), stopped)
    }

    // MARK: - Reading settings

    func testTheIntervalComesFromSettingsAtStart() {
        manager.update { $0.widgets.memory.refreshInterval = 0.25 }
        service.start(widgets: [.memory])
        settle(0.9)
        service.stop()

        XCTAssertGreaterThan(service.memoryPressure, 0)
    }
}
