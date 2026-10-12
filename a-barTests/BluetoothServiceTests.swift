import IOBluetooth
import XCTest

/// Two halves worth separating. The Class of Device classifier is pure arithmetic over
/// IOBluetooth's constants and is tested exhaustively - it decides which SF Symbol every row
/// in the popover gets, and the peripheral case is a bitfield, not an enum, which is easy to
/// read wrong.
///
/// The rest is a wrapper around IOBluetooth, and it is deliberately NOT driven here. Reading
/// the paired list from a process whose Info.plist has no `NSBluetoothAlwaysUsageDescription`
/// does not fail, it aborts: TCC kills the process outright. Giving the test bundle that key
/// would make the suite ask a developer for Bluetooth access on first run and still answer
/// nothing useful on a runner, so what is checked instead is the guard - a service that was
/// never started must not reach the framework at all.
final class BluetoothServiceTests: XCTestCase {
    private var directory: URL!
    private var manager: SettingsManager!
    private var service: BluetoothService!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("abar-bluetooth-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let config = directory.appendingPathComponent("config.json")
        try SettingsCodec.encode(ABarSettings()).write(to: config)
        manager = SettingsManager(store: SettingsStore(fileURL: config))
        service = BluetoothService(settingsManager: manager)
    }

    override func tearDownWithError() throws {
        service.stop()
        service = nil
        manager.flush()
        try? FileManager.default.removeItem(at: directory)
    }


    // MARK: - Class of Device: audio

    func testLoudspeakerClassesAreSpeakers() {
        let speakerMinors = [
            Int(kBluetoothDeviceClassMinorAudioLoudspeaker),
            Int(kBluetoothDeviceClassMinorAudioPortable),
            Int(kBluetoothDeviceClassMinorAudioHiFi),
        ]
        for minor in speakerMinors {
            XCTAssertEqual(
                BluetoothService.kind(
                    major: Int(kBluetoothDeviceClassMajorAudio), minor: minor,
                    minorTypeHint: nil),
                .speaker, "audio minor \(minor)")
        }
    }

    func testAnyOtherAudioDeviceIsHeadphones() {
        XCTAssertEqual(
            BluetoothService.kind(
                major: Int(kBluetoothDeviceClassMajorAudio),
                minor: Int(kBluetoothDeviceClassMinorAudioHeadset), minorTypeHint: nil),
            .headphones)
    }

    // MARK: - Class of Device: peripherals are a bitfield

    func testTheKeyboardBitIsRecognized() {
        XCTAssertEqual(
            BluetoothService.kind(
                major: Int(kBluetoothDeviceClassMajorPeripheral),
                minor: Int(kBluetoothDeviceClassMinorPeripheral1Keyboard), minorTypeHint: nil),
            .keyboard)
    }

    func testThePointingBitIsRecognized() {
        XCTAssertEqual(
            BluetoothService.kind(
                major: Int(kBluetoothDeviceClassMajorPeripheral),
                minor: Int(kBluetoothDeviceClassMinorPeripheral1Pointing), minorTypeHint: nil),
            .mouse)
    }

    func testADeviceThatIsBothKeyboardAndPointingReadsAsAKeyboard() {
        // A keyboard with a trackpad sets both bits; the order of the checks decides.
        let both = Int(kBluetoothDeviceClassMinorPeripheral1Keyboard)
            | Int(kBluetoothDeviceClassMinorPeripheral1Pointing)

        XCTAssertEqual(
            BluetoothService.kind(
                major: Int(kBluetoothDeviceClassMajorPeripheral), minor: both,
                minorTypeHint: nil),
            .keyboard)
    }

    func testTheGamepadKindLivesInTheLowNibble() {
        XCTAssertEqual(
            BluetoothService.kind(
                major: Int(kBluetoothDeviceClassMajorPeripheral),
                minor: Int(kBluetoothDeviceClassMinorPeripheral2Gamepad), minorTypeHint: nil),
            .gamepad)
    }

    func testAnUnrecognizedPeripheralIsOther() {
        XCTAssertEqual(
            BluetoothService.kind(
                major: Int(kBluetoothDeviceClassMajorPeripheral), minor: 0, minorTypeHint: nil),
            .other)
    }

    func testAPeripheralIgnoresTheMinorTypeHint() {
        // The class was readable, so the hint is not consulted.
        XCTAssertEqual(
            BluetoothService.kind(
                major: Int(kBluetoothDeviceClassMajorPeripheral), minor: 0,
                minorTypeHint: "Headphones"),
            .other)
    }

    // MARK: - Class of Device: the remaining majors

    func testTheRemainingMajorClassesMapDirectly() {
        let cases: [(Int, BluetoothDeviceKind)] = [
            (Int(kBluetoothDeviceClassMajorPhone), .phone),
            (Int(kBluetoothDeviceClassMajorWearable), .watch),
            (Int(kBluetoothDeviceClassMajorComputer), .computer),
        ]
        for (major, expected) in cases {
            XCTAssertEqual(
                BluetoothService.kind(major: major, minor: 0, minorTypeHint: nil), expected)
        }
    }

    // MARK: - Falling back to system_profiler's string

    func testAClassOfZeroFallsBackToTheMinorTypeHint() {
        // Several paired devices report a Class of Device of 0, which is the reason the
        // fallback exists at all.
        let cases: [(String, BluetoothDeviceKind)] = [
            ("Headphones", .headphones), ("Headset", .headphones),
            ("Speaker", .speaker), ("Keyboard", .keyboard),
            ("Mouse", .mouse), ("Trackpad", .mouse),
            ("Gamepad", .gamepad), ("Game Controller", .gamepad),
            ("Phone", .phone), ("Watch", .watch),
        ]
        for (hint, expected) in cases {
            XCTAssertEqual(
                BluetoothService.kind(major: 0, minor: 0, minorTypeHint: hint), expected,
                "hint '\(hint)'")
        }
    }

    func testTheHintIsMatchedRegardlessOfCase() {
        XCTAssertEqual(
            BluetoothService.kind(major: 0, minor: 0, minorTypeHint: "HEADPHONES"), .headphones)
    }

    func testAnAbsentOrUnrecognizedHintIsOther() {
        XCTAssertEqual(BluetoothService.kind(major: 0, minor: 0, minorTypeHint: nil), .other)
        XCTAssertEqual(
            BluetoothService.kind(major: 0, minor: 0, minorTypeHint: "Thermostat"), .other)
    }

    // MARK: - The guard in front of the framework

    func testSlowControllerInitializationDoesNotBlockOrRestartAfterStop() {
        let entered = expectation(description: "controller initialization runs off main")
        let completed = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in self.service.isControllerInitialized }, object: nil)
        let release = DispatchSemaphore(value: 0)
        var initializationCount = 0
        service = BluetoothService(settingsManager: manager, initializeController: {
            XCTAssertFalse(Thread.isMainThread)
            initializationCount += 1
            entered.fulfill()
            XCTAssertEqual(release.wait(timeout: .now() + 3), .success)
        })
        defer { release.signal() }

        service.start()
        service.start()
        service.refreshDevices()
        service.setPopoverOpen(true)
        service.togglePower()
        wait(for: [entered], timeout: 1)
        service.stop()
        release.signal()
        // Predicate expectations poll periodically; allow more than one poll interval.
        wait(for: [completed], timeout: 3)

        XCTAssertTrue(service.isControllerInitialized)
        XCTAssertEqual(initializationCount, 1)
        XCTAssertEqual(service.info, BluetoothInfo())
        service.refresh()
        service.setPopoverOpen(true)
        XCTAssertEqual(service.info, BluetoothInfo(), "completion must not restart a stopped service")
        XCTAssertTrue(service.pendingAddresses.isEmpty)
    }

    func testRefreshingBeforeStartPublishesNothing() {
        service.refreshDevices()

        XCTAssertEqual(service.info, BluetoothInfo(),
                       "a stopped service must not read hardware or publish")
    }






    func testStoppingWithoutStartingIsSafe() {
        service.stop()
    }

    func testThePopoverFlagIsIgnoredWhileStopped() {
        service.setPopoverOpen(true)

        XCTAssertEqual(service.info, BluetoothInfo(),
                       "opening a popover on a stopped service must not start reading hardware")
    }
}
