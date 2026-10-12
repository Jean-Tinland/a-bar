import Foundation

/// Which window-manager service feeds the bar.
enum WindowManagerServices {

  /// The service to start, and the one that has to be stopped to make room for it.
  struct Transition: Equatable {
    let start: WindowManager?
    /// The service that was running and must be stopped first, or `nil` at launch when
    /// nothing was running yet.
    let stop: WindowManager?
  }

  /// Only visible consumers of the selected manager can keep its data service running.
  static func requiredService(
    for windowManager: WindowManager, widgets: Set<WidgetIdentifier>
  ) -> WindowManager? {
    switch windowManager {
    case .yabai:
      return widgets.contains(.spaces) || widgets.contains(.process) ? windowManager : nil
    case .aerospace:
      return widgets.contains(.aerospaceSpaces) || widgets.contains(.aerospaceProcess)
        ? windowManager : nil
    }
  }

  /// Change service demand without changing the user's selected window manager.
  static func transition(
    to windowManager: WindowManager?, from running: WindowManager?,
    executablePath: String? = nil, runningExecutablePath: String? = nil
  )
    -> Transition?
  {
    guard running != windowManager
      || (windowManager != nil && executablePath != runningExecutablePath) else { return nil }
    return Transition(start: windowManager, stop: running)
  }
}
