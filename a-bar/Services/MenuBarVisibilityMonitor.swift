import AppKit
import CoreGraphics

/// Watches the macOS menu bar so a top bar can get out of its way, and back in front of it.
///
/// Everything here goes through SkyLight, the private framework behind the window server. None of
/// it is declared in a public header, so each symbol is resolved at runtime and a missing one
/// falls back to the bar's usual level rather than crashing - the same arrangement as
/// `BluetoothService.setPowerState`. `BarWindowLevel` decides what to do with the answers.
final class MenuBarVisibilityMonitor {
  static let shared = MenuBarVisibilityMonitor()

  /// Called on the main queue whenever the bar levels may need re-applying.
  var onChange: (() -> Void)?

  private var isStarted = false
  private var observers: [(NotificationCenter, NSObjectProtocol)] = []

  private init() {}

  // MARK: - SkyLight

  private typealias MainConnectionID = @convention(c) () -> Int32
  private typealias NotifyHandler =
    @convention(c) (UInt32, UnsafeMutableRawPointer?, Int, UnsafeMutableRawPointer?) -> Void
  private typealias RegisterNotifyProc =
    @convention(c) (Int32, NotifyHandler, UInt32, UnsafeMutableRawPointer?) -> Int32
  private typealias IsMenuBarVisibleOnSpace = @convention(c) (Int32, UInt64) -> Bool
  private typealias GetMenuBarAutohideEnabled =
    @convention(c) (Int32, UnsafeMutablePointer<Int32>) -> Int32
  private typealias ManagedDisplayGetCurrentSpace = @convention(c) (Int32, CFString) -> UInt64
  private typealias SpaceGetType = @convention(c) (Int32, UInt64) -> Int32

  /// Posted by the window server when the menu bar is hidden and revealed.
  private static let menuBarHiddenEvent: UInt32 = 1301
  private static let menuBarRevealedEvent: UInt32 = 1302

  /// `SLSSpaceGetType` reports a fullscreen app's space as 4.
  private static let fullscreenSpaceType: Int32 = 4

  /// SkyLight is not linked, so it has to be opened before its symbols can be looked up.
  private static let skyLight = dlopen(
    "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

  private static func resolve<T>(_ name: String, as type: T.Type) -> T? {
    guard let skyLight, let symbol = dlsym(skyLight, name) else {
      print("MenuBar: \(name) unavailable (symbol not found)")
      return nil
    }
    return unsafeBitCast(symbol, to: type)
  }

  private static let mainConnectionID = resolve("SLSMainConnectionID", as: MainConnectionID.self)
  private static let registerNotifyProc = resolve(
    "SLSRegisterConnectionNotifyProc", as: RegisterNotifyProc.self)
  private static let isMenuBarVisibleOnSpace = resolve(
    "SLSIsMenuBarVisibleOnSpace", as: IsMenuBarVisibleOnSpace.self)
  private static let getMenuBarAutohideEnabled = resolve(
    "SLSGetMenuBarAutohideEnabled", as: GetMenuBarAutohideEnabled.self)
  private static let managedDisplayGetCurrentSpace = resolve(
    "SLSManagedDisplayGetCurrentSpace", as: ManagedDisplayGetCurrentSpace.self)
  private static let spaceGetType = resolve("SLSSpaceGetType", as: SpaceGetType.self)

  private static let connection: Int32? = mainConnectionID?()

  // MARK: - Lifecycle

  func start() {
    guard !isStarted else { return }
    isStarted = true

    // Registration cannot be undone, so it happens once for the life of the process; `stop()`
    // only silences it. The handler is a C function pointer and captures nothing, which is why
    // it reaches the monitor through `shared`.
    _ = Self.registerWindowServerEvents

    let workspace = NSWorkspace.shared.notificationCenter
    // A fullscreen space hides the menu bar too, and the bar must not cover the app there.
    observers.append((workspace, workspace.addObserver(
      forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
    ) { [weak self] _ in self?.notify() }))

    // "Automatically hide and show the menu bar" changed in System Settings.
    let distributed = DistributedNotificationCenter.default()
    observers.append((distributed, distributed.addObserver(
      forName: NSNotification.Name("AppleInterfaceMenuBarHidingChangedNotification"),
      object: nil, queue: .main
    ) { [weak self] _ in self?.notify() }))
  }

  func stop() {
    guard isStarted else { return }
    isStarted = false
    observers.forEach { center, token in center.removeObserver(token) }
    observers.removeAll()
  }

  private static let registerWindowServerEvents: Void = {
    guard let connection, let registerNotifyProc else { return }
    let handler: NotifyHandler = { _, _, _, _ in
      DispatchQueue.main.async { MenuBarVisibilityMonitor.shared.notify() }
    }
    for event in [menuBarHiddenEvent, menuBarRevealedEvent] {
      _ = registerNotifyProc(connection, handler, event, nil)
    }
  }()

  private func notify() {
    guard isStarted else { return }
    onChange?()
  }

  // MARK: - State

  struct State: Equatable {
    var menuBarAutohides: Bool
    var menuBarVisible: Bool
    var isFullscreenSpace: Bool
  }

  /// What the menu bar is doing on the space currently shown on `screen`.
  ///
  /// When the visibility query is unavailable the menu bar is reported as visible: the bar then
  /// stays at its usual level, which is what it did before macOS 27.
  func state(for screen: NSScreen) -> State {
    let autohides = Self.menuBarAutohides()
    guard
      let connection = Self.connection,
      let isMenuBarVisibleOnSpace = Self.isMenuBarVisibleOnSpace,
      let space = Self.currentSpace(on: screen, connection: connection)
    else {
      return State(menuBarAutohides: autohides, menuBarVisible: true, isFullscreenSpace: false)
    }

    let fullscreen = Self.spaceGetType.map { $0(connection, space) == Self.fullscreenSpaceType }
    return State(
      menuBarAutohides: autohides,
      menuBarVisible: isMenuBarVisibleOnSpace(connection, space),
      isFullscreenSpace: fullscreen ?? false)
  }

  /// The highest layer of any `MenuBarAgent` window, or `nil` when there is none (before
  /// macOS 27). Read on demand rather than cached: the agent recreates its windows, and the layer
  /// it uses has already changed once between 27.0 and 27.2.
  func agentLayer() -> Int? {
    guard
      let windows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]]
    else { return nil }
    return windows
      .filter { $0[kCGWindowOwnerName as String] as? String == "MenuBarAgent" }
      .compactMap { $0[kCGWindowLayer as String] as? Int }
      .max()
  }

  private static func menuBarAutohides() -> Bool {
    if let connection, let getMenuBarAutohideEnabled {
      var enabled: Int32 = 0
      if getMenuBarAutohideEnabled(connection, &enabled) == 0 {
        return enabled != 0
      }
    }
    return UserDefaults(suiteName: UserDefaults.globalDomain)?.bool(forKey: "_HIHideMenuBar")
      ?? false
  }

  private static func currentSpace(on screen: NSScreen, connection: Int32) -> UInt64? {
    guard
      let managedDisplayGetCurrentSpace,
      let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
      let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue(),
      let uuidString = CFUUIDCreateString(nil, uuid)
    else { return nil }
    let space = managedDisplayGetCurrentSpace(connection, uuidString)
    return space == 0 ? nil : space
  }
}
