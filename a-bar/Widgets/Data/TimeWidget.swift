import SwiftUI

/// Time widget
struct TimeWidget: View {
  @EnvironmentObject var settings: SettingsManager

  @State private var currentTime = Date()
  @State private var refreshTimer: Timer?

  private var globalSettings: GlobalSettings {
    settings.settings.global
  }

  private var timeSettings: TimeWidgetSettings {
    settings.settings.widgets.time
  }

  private var theme: ABarTheme {
    ThemeManager.currentTheme(for: settings.settings.theme)
  }

  var body: some View {
    let bgColor = timeSettings.backgroundColor.color(from: theme)
    let fgColor =
      globalSettings.noColorInDataWidgets ? 
        theme.foreground : 
        bgColor.contrastingForeground(from: theme, opacity: globalSettings.barElementsBackgroundOpacity, barBackground: theme.background)

    BaseWidgetView(
      backgroundColor: globalSettings.noColorInDataWidgets
        ? theme.minor.opacity(0.95) : bgColor.opacity(0.95),
      noPadding: true,
      onClick: openClock
    ) {
      ZStack {
        if timeSettings.showDayProgress {
          DayProgressView(progress: currentTime.dayProgress, backgroundColor: fgColor)
        }
        HStack(spacing: 4) {
          if timeSettings.showIcon {
            TimeIconView(time: currentTime, iconColor: fgColor)
          }
          Text(formattedTime)
            .foregroundColor(fgColor)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
      }
      .clipped()
    }
    .help("Open Clock: \(timeSettings.clockDestination.rawValue.capitalized)")
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isButton)
    .accessibilityHint("Open Clock: \(timeSettings.clockDestination.rawValue.capitalized)")
    .accessibilityAction { openClock() }
    .onAppear {
      startTimer()
    }
    .onDisappear {
      refreshTimer?.invalidate()
      refreshTimer = nil
    }
    .onChange(of: timeSettings.refreshInterval) { _ in
      startTimer()
    }
    .onChange(of: timeSettings) { _ in
      currentTime = Date()
    }
    .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
      currentTime = Date()
    }
    .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)) { _ in
      currentTime = Date()
    }
  }

  private var formattedTime: String {
    WidgetLabels.time(
      currentTime, hour12: timeSettings.hour12, showSeconds: timeSettings.showSeconds)
  }

  private func openClock() {
    // Clock's section URLs are not registered with Launch Services; deliver them to Clock directly.
    NSWorkspace.shared.open(
      [timeSettings.clockDestination.url],
      withApplicationAt: URL(fileURLWithPath: "/System/Applications/Clock.app"),
      configuration: NSWorkspace.OpenConfiguration()
    ) { _, error in
      if let error {
        DispatchQueue.main.async { NSApp.presentError(error) }
      }
    }
  }

  private func startTimer() {
    refreshTimer?.invalidate()
    currentTime = Date()
    refreshTimer = Timer.scheduledTimer(withTimeInterval: timeSettings.refreshInterval, repeats: true) { _ in
      let now = Date()
      if Self.shouldUpdateTime(from: currentTime, to: now, settings: timeSettings) {
        currentTime = now
      }
    }
  }

  /// Preserve the configured timer cadence, but do not invalidate an unchanged minute-only face.
  static func shouldUpdateTime(
    from current: Date, to next: Date, settings: TimeWidgetSettings, calendar: Calendar = .current
  ) -> Bool {
    settings.showSeconds || settings.showDayProgress
      || !calendar.isDate(current, equalTo: next, toGranularity: .minute)
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
  
  private var globalSettings: GlobalSettings {
    settings.settings.global
  }

  private var theme: ABarTheme {
    ThemeManager.currentTheme(for: settings.settings.theme)
  }

  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .leading) {
        Rectangle()
          .fill(theme.minor.opacity(0.05))
        Rectangle()
          .fill(backgroundColor.opacity(0.15))
          .frame(width: geometry.size.width * progress)
      }
      .frame(width: geometry.size.width, height: geometry.size.height)
    }
    .ignoresSafeArea()
    .allowsHitTesting(false)
    .clipShape(
      RoundedRectangle(cornerRadius: globalSettings.barElementsCornerRadius)
    )
  }
}
