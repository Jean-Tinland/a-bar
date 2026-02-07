import SwiftUI

/// Memory usage widget with pie chart
struct MemoryWidget: View {
  @EnvironmentObject var settings: SettingsManager
  @EnvironmentObject var systemInfo: SystemInfoService

  private var memorySettings: MemoryWidgetSettings {
    settings.settings.widgets.memory
  }

  private var theme: ABarTheme {
    ThemeManager.currentTheme(for: settings.settings.theme)
  }

  private var memoryColor: Color {
    let usage = systemInfo.memoryPressure
    if usage > 80 {
      return theme.red
    } else if usage > 60 {
      return theme.yellow
    }
    return theme.green
  }

  var body: some View {
    BaseWidgetView(onClick: openActivityMonitor) {
      AdaptiveStack(hSpacing: 4, vSpacing: 2) {
        PieChartView(
          usedPercentage: systemInfo.memoryPressure,
          usedColor: memoryColor,
          freeColor: theme.mainAlt
        )
        .frame(width: 18, height: 18)

        Text("\(Int(systemInfo.memoryPressure))%")
          .foregroundColor(theme.foreground)
      }
    }
  }

  private func openActivityMonitor() {
    Task {
      _ = try? await ShellExecutor.run("open -a 'Activity Monitor'")
    }
  }
}
