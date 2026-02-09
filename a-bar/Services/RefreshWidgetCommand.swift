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

    // Check if refreshing aerospace widgets
    if widgetName.lowercased() == "aerospace" {
      AerospaceService.shared.refresh()
      return "ok: refreshed aerospace widgets"
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

/// AppleScript command handler for setting the active profile
/// Usage: osascript -e 'tell application "a-bar" to set profile "Profile Name"'
@objc(SetProfileCommand)
class SetProfileCommand: NSScriptCommand {

  override func performDefaultImplementation() -> Any? {
    guard let profileName = directParameter as? String else {
      return "error: missing profile name"
    }

    let profileManager = ProfileManager.shared
    let success = profileManager.switchToProfile(named: profileName)

    if success {
      return "ok: switched to profile '\(profileName)'"
    } else {
      let availableProfiles = profileManager.profileNames.joined(separator: ", ")
      return "error: profile '\(profileName)' not found. Available profiles: \(availableProfiles)"
    }
  }
}

/// AppleScript command handler for getting the current profile
/// Usage: osascript -e 'tell application "a-bar" to get profile'
@objc(GetProfileCommand)
class GetProfileCommand: NSScriptCommand {

  override func performDefaultImplementation() -> Any? {
    let profileManager = ProfileManager.shared

    if let activeProfile = profileManager.activeProfile {
      return activeProfile.name
    } else {
      return "error: no active profile"
    }
  }
}

/// AppleScript command handler for listing all profiles
/// Usage: osascript -e 'tell application "a-bar" to list profiles'
@objc(ListProfilesCommand)
class ListProfilesCommand: NSScriptCommand {

  override func performDefaultImplementation() -> Any? {
    let profileManager = ProfileManager.shared
    return profileManager.profileNames.joined(separator: ", ")
  }
}
