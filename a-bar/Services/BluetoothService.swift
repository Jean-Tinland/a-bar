import Combine
import Foundation
import IOBluetooth

/// Bluetooth power state, paired devices, connection state and battery levels.
///
/// Two sources are merged:
/// - IOBluetooth (in-process, free): power state, paired list, connection
///   state. Polled on a short timer and refreshed instantly through
///   IOBluetooth connect/disconnect notifications.
/// - `system_profiler SPBluetoothDataType -json` (~0.1s, forks a process):
///   the only source of battery levels. IOBluetooth does not expose battery at
///   all. Polled lazily — while the popover is open, or shortly after a
///   connection change — so an idle bar never forks a process.
///
/// Threading: snapshots and notifications stay on the main thread.
/// `IOBluetoothUserNotification` callbacks are delivered on the run loop of the
/// registering thread, and a GCD worker queue has no run loop, so registering
/// off-main means callbacks silently never fire. Controller initialization and
/// blocking `openConnection()` / `closeConnection()` calls run on `workQueue`.
final class BluetoothService: ObservableObject {
  static let shared = BluetoothService()

  @Published private(set) var info = BluetoothInfo()
  /// Normalized addresses with a connect/disconnect request in flight.
  @Published private(set) var pendingAddresses: Set<String> = []

  private var refreshTimer: Timer?
  private var batteryTimer: Timer?
  private var batteryTask: Task<Void, Never>?
  private var batteryRefreshWorkItem: DispatchWorkItem?
  private var powerRefreshWorkItem: DispatchWorkItem?
  private var pendingWatchdogs: [String: DispatchWorkItem] = [:]
  private var connectNotification: IOBluetoothUserNotification?
  private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]
  private var batteryCache: [String: BluetoothBatteryLevels] = [:]
  /// Device kind fallback from system_profiler's `device_minorType`, for
  /// devices whose Class of Device reads as 0.
  private var minorTypeCache: [String: String] = [:]
  private var isPopoverOpen = false
  private var isFetchingBattery = false
  private var isStarted = false
  private(set) var isControllerInitialized = false
  private var isInitializingController = false
  private var refreshGeneration = 0

  private let settingsManager: SettingsManager
  private let initializeController: () -> Void
  private let workQueue = DispatchQueue(label: "com.a-bar.bluetooth", qos: .userInitiated)

  private var observer: BluetoothNotificationObserver?

  private var settings: BluetoothWidgetSettings {
    settingsManager.settings.widgets.bluetooth
  }

  init(
    settingsManager: SettingsManager = .shared,
    initializeController: @escaping () -> Void = { _ = IOBluetoothHostController.default() }
  ) {
    self.settingsManager = settingsManager
    self.initializeController = initializeController
  }

  // MARK: - Lifecycle

  func start() {
    isStarted = true
    guard isControllerInitialized else {
      guard !isInitializingController else { return }
      isInitializingController = true
      let initialize = initializeController
      // The first call can wait for CoreBluetooth indefinitely. Never hold the UI
      // run loop while it initializes; every hardware entry point waits for completion.
      workQueue.async { [weak self] in
        initialize()
        DispatchQueue.main.async {
          guard let self else { return }
          self.isInitializingController = false
          self.isControllerInitialized = true
          if self.isStarted { self.start() }
        }
      }
      return
    }
    if observer == nil {
      let generation = refreshGeneration
      observer = BluetoothNotificationObserver { [weak self] in
        guard let self, self.isStarted, generation == self.refreshGeneration else { return }
        self.handleConnectionNotification()
      }
    }
    refreshDevices()
    if connectNotification == nil { registerConnectNotification() }
    startTimers()
  }

  func stop() {
    isStarted = false
    refreshGeneration += 1
    isPopoverOpen = false
    isFetchingBattery = false
    batteryTask?.cancel()
    batteryTask = nil
    batteryRefreshWorkItem?.cancel()
    batteryRefreshWorkItem = nil
    powerRefreshWorkItem?.cancel()
    powerRefreshWorkItem = nil
    pendingWatchdogs.values.forEach { $0.cancel() }
    pendingWatchdogs.removeAll()
    pendingAddresses.removeAll()
    refreshTimer?.invalidate()
    refreshTimer = nil
    batteryTimer?.invalidate()
    batteryTimer = nil
    connectNotification?.unregister()
    connectNotification = nil
    for (_, notification) in disconnectNotifications {
      notification.unregister()
    }
    disconnectNotifications.removeAll()
    observer = nil
  }

  func refresh() {
    refreshDevices()
    refreshBatteryLevels(force: true)
  }

  private func startTimers() {
    let generation = refreshGeneration
    refreshTimer?.invalidate()
    refreshTimer = Timer.scheduledTimer(
      withTimeInterval: settings.refreshInterval, repeats: true
    ) { [weak self] _ in
      guard let self, self.isStarted, generation == self.refreshGeneration else { return }
      self.refreshDevices()
    }

    batteryTimer?.invalidate()
    batteryTimer = Timer.scheduledTimer(
      withTimeInterval: settings.batteryRefreshInterval, repeats: true
    ) { [weak self] _ in
      guard let self, self.isStarted, generation == self.refreshGeneration else { return }
      self.refreshBatteryLevels()
    }
  }

  // MARK: - IOBluetooth snapshot (main thread)

  /// Read power state and the paired device list straight from IOBluetooth.
  /// Cheap enough to run on the main thread; `system_profiler` is not.
  func refreshDevices() {
    guard isStarted, isControllerInitialized else { return }
    var next = BluetoothInfo()
    next.canTogglePower = BluetoothService.setPowerState != nil

    if let controller = IOBluetoothHostController.default() {
      next.hasController = true
      next.isPoweredOn = controller.powerState == kBluetoothHCIPowerStateON
    }

    if next.isPoweredOn, let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] {
      next.devices =
        paired
        .compactMap { device -> BluetoothPairedDevice? in
          guard let address = device.addressString else { return nil }
          let id = BluetoothProfileParser.normalizedAddress(address)
          let isConnected = device.isConnected()
          let name = device.name ?? device.nameOrAddress ?? address
          return BluetoothPairedDevice(
            id: id,
            address: address,
            name: name,
            isConnected: isConnected,
            kind: BluetoothService.kind(
              major: Int(device.deviceClassMajor),
              minor: Int(device.deviceClassMinor),
              minorTypeHint: minorTypeCache[id]
            ),
            battery: isConnected ? batteryCache[id] : nil
          )
        }
        .sorted {
          $0.isConnected == $1.isConnected
            ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            : $0.isConnected
        }
    }

    if !next.isPoweredOn {
      batteryCache.removeAll()
    }

    // Avoid republishing identical state: the timer would otherwise re-render
    // every bar on every display on each tick.
    if info != next {
      info = next
    }
    registerDisconnectNotifications()
  }

  // MARK: - system_profiler (battery)

  /// Battery levels are only available through `system_profiler`, which forks a
  /// process, so this is demand-driven rather than timer-driven: it runs while
  /// the popover is open, when the user opted into showing battery in the bar,
  /// or shortly after a connection change.
  func refreshBatteryLevels(force: Bool = false) {
    guard isStarted else { return }
    guard info.isPoweredOn, !info.connectedDevices.isEmpty else { return }
    guard force || isPopoverOpen || settings.showBatteryInBar else { return }
    guard !isFetchingBattery else { return }
    isFetchingBattery = true
    let generation = refreshGeneration

    batteryTask = Task { @MainActor in
      guard isStarted, generation == refreshGeneration, !Task.isCancelled else { return }
      let parsed = await BluetoothService.fetchBatteryLevels()
      guard isStarted, generation == refreshGeneration, !Task.isCancelled else { return }
      batteryTask = nil
      isFetchingBattery = false
      guard let parsed else { return }
      batteryCache = parsed.battery
      minorTypeCache = parsed.minorTypes
      refreshDevices()
    }
  }

  /// Re-read battery a beat after a connection change. Deliberately NOT forced:
  /// if the popover is closed and the user has not opted into battery in the
  /// bar, nobody is looking, so an idle bar still never forks a process.
  private func scheduleBatteryRefresh(after delay: TimeInterval) {
    guard isStarted else { return }
    let generation = refreshGeneration
    batteryRefreshWorkItem?.cancel()
    let work = DispatchWorkItem { [weak self] in
      guard let self, self.isStarted, generation == self.refreshGeneration else { return }
      self.batteryRefreshWorkItem = nil
      self.refreshBatteryLevels()
    }
    batteryRefreshWorkItem = work
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
  }

  /// Fork `system_profiler` and hand what it prints to `BluetoothProfileParser`.
  private static func fetchBatteryLevels() async -> BluetoothProfileParser.ParsedProfile? {
    let output: String
    do {
      output = try await ShellExecutor.run(
        "system_profiler SPBluetoothDataType -json", timeout: 5)
    } catch {
      print("Bluetooth: system_profiler failed: \(error)")
      return nil
    }

    guard let data = output.data(using: .utf8),
      let profile = BluetoothProfileParser.parse(data)
    else {
      print("Bluetooth: could not parse system_profiler output")
      return nil
    }

    return profile
  }

  // MARK: - Popover-driven cadence

  func setPopoverOpen(_ open: Bool) {
    isPopoverOpen = open && isStarted
    if isPopoverOpen {
      refreshDevices()
      refreshBatteryLevels(force: true)
    }
  }

  // MARK: - Actions

  /// `IOBluetoothPreferenceSetControllerPowerState` is private: it is exported
  /// by IOBluetooth but declared in no public header, so it is resolved at
  /// runtime. If it ever disappears, the widget opens the Bluetooth settings
  /// pane instead of crashing. Note this would block App Store distribution —
  /// irrelevant here, since a-bar is ad-hoc signed and shipped via GitHub.
  private typealias SetControllerPowerState = @convention(c) (Int32) -> Void

  private static let setPowerState: SetControllerPowerState? = {
    // RTLD_DEFAULT — IOBluetooth is already loaded via `import IOBluetooth`.
    guard
      let symbol = dlsym(
        UnsafeMutableRawPointer(bitPattern: -2),
        "IOBluetoothPreferenceSetControllerPowerState")
    else {
      print("Bluetooth: power toggle unavailable (symbol not found)")
      return nil
    }
    return unsafeBitCast(symbol, to: SetControllerPowerState.self)
  }()

  func togglePower() {
    guard isStarted, isControllerInitialized else { return }
    guard let setPowerState = BluetoothService.setPowerState else {
      openBluetoothSettings()
      return
    }
    setPowerState(info.isPoweredOn ? 0 : 1)
    let generation = refreshGeneration
    // The daemon applies the change asynchronously; re-read shortly after.
    powerRefreshWorkItem?.cancel()
    let work = DispatchWorkItem { [weak self] in
      guard let self, self.isStarted, generation == self.refreshGeneration else { return }
      self.powerRefreshWorkItem = nil
      self.refreshDevices()
    }
    powerRefreshWorkItem = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
  }

  /// Connect or disconnect a paired device.
  ///
  /// `openConnection()` / `closeConnection()` are synchronous IOBluetooth calls
  /// that can block for several seconds on a device that has to be paged, so
  /// they run off the main thread — otherwise the whole bar freezes. The device
  /// is re-resolved by address on the worker queue (IOBluetooth vends a single
  /// instance per address) so main-thread objects are never touched off-main.
  func toggleConnection(for device: BluetoothPairedDevice) {
    guard isStarted, isControllerInitialized else { return }
    guard !pendingAddresses.contains(device.id) else { return }
    let address = device.address
    let id = device.id
    let shouldConnect = !device.isConnected
    let generation = refreshGeneration
    pendingAddresses.insert(id)

    // Watchdog: never let a row's spinner stick forever.
    let watchdog = DispatchWorkItem { [weak self] in
      guard let self, self.isStarted, generation == self.refreshGeneration else { return }
      self.pendingWatchdogs.removeValue(forKey: id)
      self.pendingAddresses.remove(id)
    }
    pendingWatchdogs[id] = watchdog
    DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: watchdog)

    workQueue.async { [weak self] in
      var status: IOReturn = kIOReturnError
      if let target = IOBluetoothDevice(addressString: address) {
        status = shouldConnect ? target.openConnection() : target.closeConnection()
      }
      DispatchQueue.main.async {
        guard let self, self.isStarted, generation == self.refreshGeneration else { return }
        self.pendingWatchdogs.removeValue(forKey: id)?.cancel()
        self.pendingAddresses.remove(id)
        if status != kIOReturnSuccess {
          print(
            "Bluetooth: \(shouldConnect ? "connect" : "disconnect") failed for \(address) (\(status))"
          )
        }
        self.refreshDevices()
        // AirPods and friends publish battery a beat after the link comes up.
        self.scheduleBatteryRefresh(after: 2.5)
      }
    }
  }

  func openBluetoothSettings() {
    Task {
      _ = try? await ShellExecutor.run("open /System/Library/PreferencePanes/Bluetooth.prefPane/")
    }
  }

  // MARK: - Connect / disconnect notifications

  private func registerConnectNotification() {
    guard let observer else { return }
    connectNotification?.unregister()
    connectNotification = IOBluetoothDevice.register(
      forConnectNotifications: observer,
      selector: #selector(BluetoothNotificationObserver.deviceConnected(_:device:))
    )
  }

  /// Disconnect notifications are per device instance, so they are refreshed to
  /// match the currently connected set after every snapshot.
  private func registerDisconnectNotifications() {
    guard let observer else { return }
    let connected = Set(info.connectedDevices.map { $0.id })

    for (id, notification) in disconnectNotifications where !connected.contains(id) {
      notification.unregister()
      disconnectNotifications.removeValue(forKey: id)
    }

    for device in info.connectedDevices where disconnectNotifications[device.id] == nil {
      guard let target = IOBluetoothDevice(addressString: device.address) else { continue }
      disconnectNotifications[device.id] = target.register(
        forDisconnectNotification: observer,
        selector: #selector(BluetoothNotificationObserver.deviceDisconnected(_:device:))
      )
    }
  }

  private func handleConnectionNotification() {
    guard isStarted else { return }
    refreshDevices()
    scheduleBatteryRefresh(after: 2.5)
  }
}

/// Obj-C shim for IOBluetooth's notification API, which requires a real
/// NSObject target and a two-argument selector — passing nil returns nil, so a
/// Swift closure or struct will not do.
private final class BluetoothNotificationObserver: NSObject {
  private let onChange: () -> Void

  init(onChange: @escaping () -> Void) {
    self.onChange = onChange
    super.init()
  }

  @objc func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice)
  {
    onChange()
  }

  @objc func deviceDisconnected(
    _ notification: IOBluetoothUserNotification, device: IOBluetoothDevice
  ) {
    onChange()
  }
}

extension BluetoothService {
  /// Classify from the Class of Device. Several paired devices report a class
  /// of 0, so system_profiler's `device_minorType` string is used as a fallback.
  static func kind(major: Int, minor: Int, minorTypeHint: String?) -> BluetoothDeviceKind {
    switch major {
    case Int(kBluetoothDeviceClassMajorAudio):
      switch minor {
      case Int(kBluetoothDeviceClassMinorAudioLoudspeaker),
        Int(kBluetoothDeviceClassMinorAudioPortable),
        Int(kBluetoothDeviceClassMinorAudioHiFi):
        return .speaker
      default:
        return .headphones
      }
    case Int(kBluetoothDeviceClassMajorPeripheral):
      // The peripheral minor class is a bitfield: keyboard / pointing live in
      // the high bits, the device kind in the low nibble.
      if minor & Int(kBluetoothDeviceClassMinorPeripheral1Keyboard) != 0 { return .keyboard }
      if minor & Int(kBluetoothDeviceClassMinorPeripheral1Pointing) != 0 { return .mouse }
      if minor & 0x0F == Int(kBluetoothDeviceClassMinorPeripheral2Gamepad) { return .gamepad }
      return .other
    case Int(kBluetoothDeviceClassMajorPhone):
      return .phone
    case Int(kBluetoothDeviceClassMajorWearable):
      return .watch
    case Int(kBluetoothDeviceClassMajorComputer):
      return .computer
    default:
      return kindFromMinorType(minorTypeHint)
    }
  }

  private static func kindFromMinorType(_ hint: String?) -> BluetoothDeviceKind {
    guard let hint = hint?.lowercased() else { return .other }
    if hint.contains("headphone") || hint.contains("headset") { return .headphones }
    if hint.contains("speaker") { return .speaker }
    if hint.contains("keyboard") { return .keyboard }
    if hint.contains("mouse") || hint.contains("trackpad") { return .mouse }
    if hint.contains("gamepad") || hint.contains("controller") { return .gamepad }
    if hint.contains("phone") { return .phone }
    if hint.contains("watch") { return .watch }
    return .other
  }
}
