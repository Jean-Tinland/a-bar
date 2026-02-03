import SwiftUI

struct GPUWidget: View {
  @EnvironmentObject var settings: SettingsManager
  @EnvironmentObject var systemInfo: SystemInfoService

  private var gpuSettings: GPUWidgetSettings {
    settings.settings.widgets.gpu
  }

  private var theme: ABarTheme {
    ThemeManager.currentTheme(for: settings.settings.theme)
  }

  var body: some View {
    let isLoading = systemInfo.gpuUsage == 0 && systemInfo.gpuHistory.values.isEmpty
    let graphColor = gpuSettings.graphColor.color(from: theme)
    
    BaseWidgetView(noPadding: !isLoading, onClick: openActivityMonitor) {
      if isLoading {
        ProgressView()
          .scaleEffect(0.5)
          .frame(width: 16, height: 16)
      } else {
        ZStack {
          HStack {
            GeometryReader { geometry in
              GraphView(
                values: systemInfo.gpuHistory.values,
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
            if gpuSettings.showIcon {
              Image(systemName: "cpu")
                .font(.system(size: 10))
                .foregroundColor(graphColor)
                .padding(.leading, 6)
                .padding(.top, -6)
            }
            Spacer()
          }

          Text("\(Int(systemInfo.gpuUsage))%")
            .foregroundColor(theme.foreground)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 6)
            .padding(.top, -6)
        }
      }
    }
  }

  private func openActivityMonitor() {
    Task {
      _ = try? await ShellExecutor.run("open -a 'Activity Monitor'")
    }
  }
}
