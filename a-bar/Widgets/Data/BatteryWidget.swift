import SwiftUI

struct BatteryWidget: View {
  @EnvironmentObject var settings: SettingsManager
  @EnvironmentObject var systemInfo: SystemInfoService

  private var globalSettings: GlobalSettings {
    settings.settings.global
  }

  private var batterySettings: BatteryWidgetSettings {
    settings.settings.widgets.battery
  }

  private var theme: ABarTheme {
    ThemeManager.currentTheme(for: settings.settings.theme)
  }

  private var battery: BatteryInfo {
    systemInfo.batteryInfo
  }

  var body: some View {
    let bgColor = batterySettings.backgroundColor.color(from: theme)
    let fgColor =
      globalSettings.noColorInDataWidgets
      ? theme.foreground : bgColor.contrastingForeground(from: theme)

    BaseWidgetView(
      isHighlighted: systemInfo.isCaffeinateActive,
      highlightColor: globalSettings.noColorInDataWidgets ? theme.minor : bgColor,
      backgroundColor: globalSettings.noColorInDataWidgets
        ? theme.minor.opacity(0.95) : bgColor.opacity(0.95),
      onClick: batterySettings.toggleCaffeinateOnClick ? toggleCaffeinate : nil
    ) {
      ZStack(alignment: .leading) {
        HStack(spacing: 4) {
          if batterySettings.showIcon {
            BatteryIconView(
              percentage: battery.percentage,
              isCharging: battery.isCharging,
              fgColor: fgColor
            )
          }
          Text("\(battery.percentage)%")
            .foregroundColor(fgColor)
        }
        if systemInfo.isCaffeinateActive {
          Image(systemName: "cup.and.saucer.fill")
            .font(.system(size: 16))
            .foregroundColor(fgColor.opacity(0.3))
            .offset(x: 22, y: -1)
            .zIndex(1)
        }
      }
    }
  }

  private func toggleCaffeinate() {
    systemInfo.toggleCaffeinate(option: batterySettings.caffeinateOption)
  }
}

struct BatteryIconView: View {
  let percentage: Int
  let isCharging: Bool
  let fgColor: Color

  @EnvironmentObject var settings: SettingsManager

  private var globalSettings: GlobalSettings {
    settings.settings.global
  }

  private var theme: ABarTheme {
    ThemeManager.currentTheme(for: settings.settings.theme)
  }

  var body: some View {
    ZStack {
      // Battery outline
      RoundedRectangle(cornerRadius: 2)
        .stroke(fgColor, lineWidth: 1)
        .frame(width: 18, height: 9)

      // Battery fill
      GeometryReader { geometry in
        RoundedRectangle(cornerRadius: 1)
          .fill(fillColor)
          .frame(width: max(0, (geometry.size.width - 4) * CGFloat(percentage) / 100), height: 5)
          .offset(x: 2, y: 2)
      }
      .frame(width: 18, height: 9)

      // Battery tip
      Rectangle()
        .fill(fgColor)
        .frame(width: 2, height: 4)
        .offset(x: 10)

      // Charging indicator
      if isCharging {
        Image(systemName: "bolt.fill")
          .font(.system(size: 6))
          .foregroundColor(fgColor)
      }
    }
    .frame(width: 22, height: 11)
  }

  private var fillColor: Color {
    if isCharging {
      return theme.green
    } else if percentage < 50 {
      return theme.orange
    } else if percentage < 20 {
      return theme.red
    }
    return fgColor
  }
}
