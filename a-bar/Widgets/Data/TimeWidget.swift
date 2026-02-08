import SwiftUI

/// Time widget
struct TimeWidget: View {
  @EnvironmentObject var settings: SettingsManager
  @Environment(\.widgetOrientation) var orientation

  @State private var currentTime = Date()

  private var globalSettings: GlobalSettings {
    settings.settings.global
  }

  private var timeSettings: TimeWidgetSettings {
    settings.settings.widgets.time
  }

  private var theme: ABarTheme {
    ThemeManager.currentTheme(for: settings.settings.theme)
  }

  private var isVertical: Bool {
    orientation == .vertical
  }

  var body: some View {
    let bgColor = timeSettings.backgroundColor.color(from: theme)
    let fgColor =
      globalSettings.noColorInDataWidgets
      ? theme.foreground : bgColor.contrastingForeground(from: theme)

    BaseWidgetView(
      backgroundColor: globalSettings.noColorInDataWidgets
        ? theme.minor.opacity(0.95) : bgColor.opacity(0.95),
      noPadding: true
    ) {
      ZStack {
        if timeSettings.showDayProgress && !isVertical {
          DayProgressView(progress: currentTime.dayProgress, backgroundColor: fgColor)
            .ignoresSafeArea()
        }
        AdaptiveStack(hSpacing: 4, vSpacing: 2) {
          if timeSettings.showIcon {
            TimeIconView(time: currentTime, iconColor: fgColor)
          }
          Text(formattedTime)
            .foregroundColor(fgColor)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
      }
    }
    .onAppear {
      startTimer()
    }
  }

  private var formattedTime: String {
    let formatter = DateFormatter()

    if isVertical {
      // Compact format for vertical bars: no seconds, no AM/PM
      formatter.dateFormat = "HH:mm"
    } else if timeSettings.hour12 {
      formatter.dateFormat = timeSettings.showSeconds ? "h:mm:ss a" : "h:mm a"
    } else {
      formatter.dateFormat = timeSettings.showSeconds ? "HH:mm:ss" : "HH:mm"
    }

    return formatter.string(from: currentTime)
  }

  private func startTimer() {
    Timer.scheduledTimer(withTimeInterval: timeSettings.refreshInterval, repeats: true) { _ in
      currentTime = Date()
    }
  }
}

struct TimeIconView: View {
  let time: Date
  let iconColor: Color

  @EnvironmentObject var settings: SettingsManager

  private var theme: ABarTheme {
    ThemeManager.currentTheme(for: settings.settings.theme)
  }

  var body: some View {
    let calendar = Calendar.current
    let hour = calendar.component(.hour, from: time)
    let minute = calendar.component(.minute, from: time)

    ZStack {
      Circle()
        .stroke(iconColor, lineWidth: 1)
        .frame(width: 16, height: 16)

      // Hour hand
      Rectangle()
        .fill(iconColor)
        .frame(width: 1, height: 5)
        .offset(y: -1.5)
        .rotationEffect(.degrees(Double(hour % 12) * 30 + Double(minute) * 0.5))

      // Minute hand
      Rectangle()
        .fill(iconColor)
        .frame(width: 0.5, height: 6)
        .offset(y: -2)
        .rotationEffect(.degrees(Double(minute) * 6))

      // Center dot
      Circle()
        .fill(iconColor)
        .frame(width: 2, height: 2)
    }
    .frame(width: 18, height: 18)
  }
}

struct DayProgressView: View {
  let progress: Double
  let backgroundColor: Color

  @EnvironmentObject var settings: SettingsManager

  private var theme: ABarTheme {
    ThemeManager.currentTheme(for: settings.settings.theme)
  }

  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .leading) {
        RoundedRectangle(cornerRadius: 4)
          .fill(theme.minor.opacity(0.05))
        RoundedRectangle(cornerRadius: 4)
          .fill(backgroundColor.opacity(0.15))
          .frame(width: geometry.size.width * progress)
      }
      .frame(width: geometry.size.width, height: geometry.size.height)
    }
    .ignoresSafeArea()
    .allowsHitTesting(false)
  }
}
