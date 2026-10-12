// 代码目的：
// 验证 Wi-Fi 数据刷新及定位授权监听随可见需求启停。
//
// 代码逻辑：
// 1. 用临时配置检查停用服务不发布 Wi-Fi 数据。
// 2. 使用定位替身验证延迟创建、重复启动及停止解除 delegate。
// 3. 模拟旧实例迟到回调，确认新实例的授权状态保持正确。
//
// 必需输入：
// - 测试 target 中的 WifiService 与其现有依赖。
//
// 预期输出：
// - 不请求定位、不扫描或切换真实网络的 XCTest 结果。
import Combine
import CoreLocation
import XCTest

final class WifiServiceTests: XCTestCase {
    private final class LocationManager: CLLocationManager {
        var status: CLAuthorizationStatus = .authorizedAlways
        private var observer: CLLocationManagerDelegate?
        override var authorizationStatus: CLAuthorizationStatus { status }
        override var delegate: CLLocationManagerDelegate? {
            get { observer }
            set { observer = newValue }
        }
    }

    @MainActor
    func testLocationObserverIsLazyAndReleasesItsDelegateWhenHidden() throws {
        var managers: [LocationManager] = []
        let authorization = WifiLocationAuthorization(makeManager: {
            let manager = LocationManager()
            managers.append(manager)
            return manager
        })
        XCTAssertTrue(managers.isEmpty)
        authorization.start()
        XCTAssertEqual(managers.count, 1)
        XCTAssertTrue(managers[0].delegate === authorization)
        authorization.start()
        XCTAssertEqual(managers.count, 1)
        authorization.stop()
        XCTAssertNil(managers[0].delegate)
        authorization.stop()
        XCTAssertNil(managers[0].delegate)
    }

    @MainActor
    func testOldLocationCallbacksCannotChangeTheRestartedAuthorization() throws {
        var managers: [LocationManager] = []
        let authorization = WifiLocationAuthorization(makeManager: {
            let manager = LocationManager()
            manager.status = managers.isEmpty ? .authorizedAlways : .denied
            managers.append(manager)
            return manager
        })
        authorization.start()
        XCTAssertTrue(authorization.isAuthorized)
        let old = managers[0]
        authorization.stop()
        authorization.start()
        XCTAssertFalse(authorization.isAuthorized)
        authorization.locationManagerDidChangeAuthorization(old)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        XCTAssertFalse(authorization.isAuthorized)
        XCTAssertTrue(managers[1].delegate === authorization)
        authorization.stop()
    }

    @MainActor
    func testInactiveWifiRefreshDoesNotPublishOrInitializeAConnection() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = SettingsManager(store: SettingsStore(fileURL: directory.appendingPathComponent("config.json")))
        defer { settings.flush() }
        let service = WifiService(settingsManager: settings)
        var changes = 0
        let observation = service.$info.dropFirst().sink { _ in changes += 1 }
        defer { observation.cancel(); service.stop() }
        service.refresh()
        service.stop()
        service.refresh()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        XCTAssertEqual(changes, 0)
        XCTAssertEqual(service.info, WifiInfo())
        XCTAssertTrue(service.pendingSSIDs.isEmpty)
    }
}
