import CoreWLAN
import Foundation
import SwiftUI

// Returns the current WiFi SSID using a shell command (networksetup/ipconfig)
func getSSIDFromShell() -> String? {
  let script =
    "en=\"$(networksetup -listallhardwareports | awk '/Wi-Fi|AirPort/{getline; print $NF}')\"; ipconfig getsummary \"$en\" | grep -Fxq '  Active : FALSE' || networksetup -listpreferredwirelessnetworks \"$en\" | sed -n '2s/^\\t//p'"
  let task = Process()
  let pipe = Pipe()
  task.launchPath = "/bin/zsh"
  task.arguments = ["-c", script]
  task.standardOutput = pipe
  do {
    try task.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8)?.trimmingCharacters(
      in: .whitespacesAndNewlines)
    if let ssid = output, !ssid.isEmpty, !ssid.hasPrefix("zsh:") {
      return ssid
    }
  } catch {
    print("getSSIDFromShell error: \(error)")
  }
  return nil
}

// Utility to get current WiFi SSID on macOS
@discardableResult
func getCurrentSSID() -> String? {
  if let interface = CWWiFiClient.shared().interface(),
    let ssid = interface.ssid()
  {
    return ssid
  }
  return nil
}

/// WiFi status widget
struct WifiWidget: View {
  @EnvironmentObject var settings: SettingsManager
  @EnvironmentObject var systemInfo: SystemInfoService
  @Environment(\.widgetOrientation) var orientation

  private var wifiSettings: WifiWidgetSettings {
    settings.settings.widgets.wifi
  }

  private var globalSettings: GlobalSettings {
    settings.settings.global
  }

  private var theme: ABarTheme {
    ThemeManager.currentTheme(for: settings.settings.theme)
  }

  private var wifiInfo: WifiInfo {
    systemInfo.wifiInfo
  }

  private var isVertical: Bool {
    orientation == .vertical
  }

  var body: some View {
    let bgColor = wifiSettings.backgroundColor.color(from: theme)
    let fgColor =
      globalSettings.noColorInDataWidgets
      ? theme.foreground : bgColor.contrastingForeground(from: theme)

    // Hide if disabled and setting is enabled
    if wifiSettings.hideWhenDisabled && !wifiInfo.isActive {
      EmptyView()
    } else {
      BaseWidgetView(
        backgroundColor: globalSettings.noColorInDataWidgets
          ? theme.minor.opacity(0.95) : bgColor.opacity(0.95),
        onClick: wifiSettings.toggleOnClick ? toggleWifi : nil,
        onRightClick: openWifiPreferences
      ) {
        AdaptiveStack(hSpacing: 4, vSpacing: 2) {
          if wifiSettings.showIcon {
            Image(systemName: wifiInfo.isActive ? "wifi" : "wifi.slash")
              .font(.system(size: 11))
              .foregroundColor(wifiInfo.isActive ? fgColor : theme.red)
          }

          // In vertical mode, only show icon (hide network name)
          if !wifiSettings.hideNetworkName && !isVertical {
            Text(displayName)
              .foregroundColor(wifiInfo.isActive ? fgColor : theme.minor)
          }
        }
      }
    }
  }

  private var displayName: String {
    if !wifiInfo.isActive {
      return "Disabled"
    }
    if let ssid = getSSIDFromShell(), !ssid.isEmpty {
      return ssid.truncated(to: 15)
    }
    if wifiInfo.ssid.isEmpty {
      return "Searching..."
    }
    return wifiInfo.ssid.truncated(to: 15)
  }

  private func toggleWifi() {
    Task {
      let device = wifiSettings.networkDevice
      if wifiInfo.isActive {
        _ = try? await ShellExecutor.run("networksetup -setairportpower \(device) off")
      } else {
        _ = try? await ShellExecutor.run("networksetup -setairportpower \(device) on")
      }
      systemInfo.refreshWifi()
    }
  }

  private func openWifiPreferences() {
    Task {
      _ = try? await ShellExecutor.run("open /System/Library/PreferencePanes/Network.prefPane/")
    }
  }
}
