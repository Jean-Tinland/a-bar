import SwiftUI

/// Microphone status widget
struct MicWidget: View {
  @EnvironmentObject var settings: SettingsManager
  @EnvironmentObject var systemInfo: SystemInfoService

  private var globalSettings: GlobalSettings {
    settings.settings.global
  }

  private var micSettings: MicWidgetSettings {
    settings.settings.widgets.mic
  }

  private var theme: ABarTheme {
    ThemeManager.currentTheme(for: settings.settings.theme)
  }

  var body: some View {
    let bgColor = micSettings.backgroundColor.color(from: theme)
    let fgColor =
      globalSettings.noColorInDataWidgets
      ? theme.foreground : bgColor.contrastingForeground(from: theme)

    BaseWidgetView(
      backgroundColor: globalSettings.noColorInDataWidgets
        ? theme.minor.opacity(0.95) : bgColor.opacity(0.95),
      onRightClick: openSoundPreferences
    ) {
      AdaptiveStack(hSpacing: 4, vSpacing: 2) {
        if micSettings.showIcon {
          Image(systemName: micIcon)
            .font(.system(size: 11))
            .foregroundColor(getMicColor(defaultColor: fgColor))
        }

        Text(micText)
          .foregroundColor(getMicColor(defaultColor: fgColor))
      }
    }
  }

  private var micIcon: String {
    if systemInfo.isMicMuted || systemInfo.micLevel == 0 {
      return "mic.slash.fill"
    }
    return "mic.fill"
  }

  private func getMicColor(defaultColor: Color) -> Color {
    if systemInfo.isMicMuted {
      return theme.red
    }
    if systemInfo.micLevel > 0.5 {
      return theme.green
    }
    return defaultColor
  }

  private var micText: String {
    if systemInfo.isMicMuted {
      return "-%"
    }
    return "\(Int(systemInfo.micLevel * 100))%"
  }

  private func openSoundPreferences() {
    Task {
      _ = try? await ShellExecutor.run("open /System/Library/PreferencePanes/Sound.prefPane/")
    }
  }
}
