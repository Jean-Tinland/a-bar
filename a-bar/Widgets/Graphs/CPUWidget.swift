import SwiftUI

struct CPUWidget: View {
  @EnvironmentObject var settings: SettingsManager
  @EnvironmentObject var systemInfo: SystemInfoService

  private var cpuSettings: CPUWidgetSettings {
    settings.settings.widgets.cpu
  }

  private var theme: ABarTheme {
    ThemeManager.currentTheme(for: settings.settings.theme)
  }

  var body: some View {
    let graphColor = cpuSettings.graphColor.color(from: theme)
    
    BaseWidgetView(noPadding: true, onClick: openActivityMonitor) {
      ZStack {
        HStack {
          GeometryReader { geometry in
            GraphView(
              values: systemInfo.cpuHistory.values,
              maxValue: 100.0,
              fillColor: graphColor,
              lineColor: graphColor,
              showLabels: false
            )
            .frame(
              width: geometry.size.width,
              height: geometry.size.height
            )
            .cornerRadius(4)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .clipped()
          .padding(.horizontal, 0)
          .frame(width: 70)
        }

        // Icon overlay anchored to the left
        HStack {
          if cpuSettings.showIcon {
            Image(systemName: "cpu")
              .font(.system(size: 10))
              .foregroundColor(graphColor)
              .padding(.leading, 6)
              .padding(.top, -6)
          }
          Spacer()
        }

        Text("\(Int(systemInfo.cpuUsage))%")
          .foregroundColor(theme.foreground)
          .frame(maxWidth: .infinity, alignment: .trailing)
          .padding(.trailing, 6)
          .padding(.top, -6)
      }
    }
  }

  private func openActivityMonitor() {
    Task {
      _ = try? await ShellExecutor.run("open -a 'Activity Monitor'")
    }
  }
}
