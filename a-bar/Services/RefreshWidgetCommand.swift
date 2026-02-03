import Cocoa

/// AppleScript command handler for refreshing custom widgets
@objc(RefreshWidgetCommand)
class RefreshWidgetCommand: NSScriptCommand {

  override func performDefaultImplementation() -> Any? {
    // Get the direct parameter (widget name)
    guard let widgetName = directParameter as? String else {
      return "error: missing widget name"
    }

    // Get the UserWidgetManager and refresh the widget
    let userWidgetManager = UserWidgetManager.shared
    let success = userWidgetManager.refreshWidget(named: widgetName)

    if success {
      return "ok: refreshed widget '\(widgetName)'"
    } else {
      return "error: widget '\(widgetName)' not found"
    }
  }
}
