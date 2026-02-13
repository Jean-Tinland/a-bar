import SwiftUI

/// Keyboard layout widget
struct KeyboardWidget: View {
  @EnvironmentObject var settings: SettingsManager
  @EnvironmentObject var systemInfo: SystemInfoService

  private var globalSettings: GlobalSettings {
    settings.settings.global
  }

  private var keyboardSettings: KeyboardWidgetSettings {
    settings.settings.widgets.keyboard
  }

  private var theme: ABarTheme {
    ThemeManager.currentTheme(for: settings.settings.theme)
  }

  var body: some View {
    let bgColor = keyboardSettings.backgroundColor.color(from: theme)
    let fgColor =
      globalSettings.noColorInDataWidgets ? 
        theme.foreground : 
        bgColor.contrastingForeground(from: theme, opacity: globalSettings.barElementsBackgroundOpacity, barBackground: theme.background)

    BaseWidgetView(
      backgroundColor: globalSettings.noColorInDataWidgets ? theme.minor : bgColor,
      onRightClick: openKeyboardPreferences
    ) {
      HStack(spacing: 4) {
        if keyboardSettings.showIcon {
          Image(systemName: "keyboard")
            .font(.system(size: 10))
            .foregroundColor(fgColor)
        }

        Text(formattedLayout)
          .foregroundColor(fgColor)
      }
    }
  }

  private var formattedLayout: String {
    // Show abbreviated version if too long
    let layout = systemInfo.keyboardLayout
    if layout.count > 10 {
      // Try to get first word or abbreviation
      if let firstWord = layout.split(separator: " ").first {
        return String(firstWord)
      }
      return layout.truncated(to: 8)
    }
    return layout
  }

  private func openKeyboardPreferences() {
    Task {
      _ = try? await ShellExecutor.run("open /System/Library/PreferencePanes/Keyboard.prefPane/")
    }
  }
}
