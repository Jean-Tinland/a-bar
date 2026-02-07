import SwiftUI

/// Keyboard layout widget
struct KeyboardWidget: View {
  @EnvironmentObject var settings: SettingsManager
  @EnvironmentObject var systemInfo: SystemInfoService
  @Environment(\.widgetOrientation) var orientation

  private var globalSettings: GlobalSettings {
    settings.settings.global
  }

  private var keyboardSettings: KeyboardWidgetSettings {
    settings.settings.widgets.keyboard
  }

  private var theme: ABarTheme {
    ThemeManager.currentTheme(for: settings.settings.theme)
  }

  private var isVertical: Bool {
    orientation == .vertical
  }

  var body: some View {
    let bgColor = keyboardSettings.backgroundColor.color(from: theme)
    let fgColor =
      globalSettings.noColorInDataWidgets
      ? theme.foreground : bgColor.contrastingForeground(from: theme)

    BaseWidgetView(
      backgroundColor: globalSettings.noColorInDataWidgets
        ? theme.minor.opacity(0.95) : bgColor.opacity(0.95),
      onRightClick: openKeyboardPreferences
    ) {
      AdaptiveStack(hSpacing: 4, vSpacing: 2) {
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
    let layout = systemInfo.keyboardLayout

    if isVertical {
      // Very short format for vertical: first 2-3 chars
      return layout.prefix(3).uppercased()
    }

    // Show abbreviated version if too long
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
