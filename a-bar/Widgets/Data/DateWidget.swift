import SwiftUI

/// Date display widget
struct DateWidget: View {
  @EnvironmentObject var settings: SettingsManager

  @State private var currentDate = Date()
  @State private var refreshTimer: Timer?

  private var globalSettings: GlobalSettings {
    settings.settings.global
  }

  private var dateSettings: DateWidgetSettings {
    settings.settings.widgets.date
  }

  private var theme: ABarTheme {
    ThemeManager.currentTheme(for: settings.settings.theme)
  }

  var body: some View {
    let bgColor = dateSettings.backgroundColor.color(from: theme)
    let fgColor =
      globalSettings.noColorInDataWidgets
      ? theme.foreground : bgColor.contrastingForeground(from: theme)

    BaseWidgetView(
      backgroundColor: globalSettings.noColorInDataWidgets
        ? theme.minor.opacity(0.95) : bgColor.opacity(0.95),
      onClick: openCalendar
    ) {
      HStack(spacing: 4) {
        if dateSettings.showIcon {
          Image(systemName: "calendar")
            .font(.system(size: 10))
            .foregroundColor(fgColor)
        }

        Text(formattedDate)
          .foregroundColor(fgColor)
      }
    }
    .onAppear {
      startTimer()
    }
    .onDisappear {
      refreshTimer?.invalidate()
      refreshTimer = nil
    }
  }

  private var formattedDate: String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: dateSettings.locale)

    if dateSettings.shortFormat {
      formatter.dateFormat = "EE, MMM d"
    } else {
      formatter.dateFormat = "EEEE, MMM d"
    }

    return formatter.string(from: currentDate)
  }

  private func openCalendar() {
    Task {
      _ = try? await ShellExecutor.run("open -a \"\(dateSettings.calendarApp)\"")
    }
  }

  private func startTimer() {
    refreshTimer?.invalidate()
    refreshTimer = Timer.scheduledTimer(withTimeInterval: dateSettings.refreshInterval, repeats: true) { _ in
      currentDate = Date()
    }
  }
}
