import Cocoa

/// AppleScript command handler for refreshing widgets
@objc(RefreshWidgetCommand)
class RefreshWidgetCommand: NSScriptCommand {

  override func performDefaultImplementation() -> Any? {
    // Get the direct parameter (widget name)
    guard let widgetName = directParameter as? String else {
      return "error: missing widget name"
    }

    // Check if refreshing yabai widgets
    if widgetName.lowercased() == "yabai" {
      YabaiService.shared.refresh()
      return "ok: refreshed yabai widgets"
    }

    // Otherwise, refresh a custom user widget
    let userWidgetManager = UserWidgetManager.shared
    let success = userWidgetManager.refreshWidget(named: widgetName)

    if success {
      return "ok: refreshed widget '\(widgetName)'"
    } else {
      return "error: widget '\(widgetName)' not found"
    }
  }
}

/// AppleScript command handler for toggling custom widget visibility
@objc(ToggleWidgetCommand)
class ToggleWidgetCommand: NSScriptCommand {

  override func performDefaultImplementation() -> Any? {
    guard let widgetName = directParameter as? String else {
      return "error: missing widget name"
    }

    let userWidgetManager = UserWidgetManager.shared
    let result = userWidgetManager.toggleWidget(named: widgetName)

    switch result {
    case .success(let isNowActive):
      let state = isNowActive ? "shown" : "hidden"
      return "ok: widget '\(widgetName)' is now \(state)"
    case .failure(let error):
      return "error: \(error.localizedDescription)"
    }
  }
}

/// AppleScript command handler for hiding a custom widget
@objc(HideWidgetCommand)
class HideWidgetCommand: NSScriptCommand {

  override func performDefaultImplementation() -> Any? {
    guard let widgetName = directParameter as? String else {
      return "error: missing widget name"
    }

    let userWidgetManager = UserWidgetManager.shared
    let result = userWidgetManager.hideWidget(named: widgetName)

    switch result {
    case .success(let wasHidden):
      if wasHidden {
        return "ok: widget '\(widgetName)' is now hidden"
      } else {
        return "ok: widget '\(widgetName)' was already hidden"
      }
    case .failure(let error):
      return "error: \(error.localizedDescription)"
    }
  }
}

/// AppleScript command handler for showing a custom widget
@objc(ShowWidgetCommand)
class ShowWidgetCommand: NSScriptCommand {

  override func performDefaultImplementation() -> Any? {
    guard let widgetName = directParameter as? String else {
      return "error: missing widget name"
    }

    let userWidgetManager = UserWidgetManager.shared
    let result = userWidgetManager.showWidget(named: widgetName)

    switch result {
    case .success(let wasShown):
      if wasShown {
        return "ok: widget '\(widgetName)' is now shown"
      } else {
        return "ok: widget '\(widgetName)' was already shown"
      }
    case .failure(let error):
      return "error: \(error.localizedDescription)"
    }
  }
}
