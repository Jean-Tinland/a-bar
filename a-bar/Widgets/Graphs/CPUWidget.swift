import SwiftUI

struct CPUWidget: View {
  @EnvironmentObject var settings: SettingsManager
  @EnvironmentObject var systemInfo: SystemInfoService
  @Environment(\.widgetOrientation) var orientation

  private var cpuSettings: CPUWidgetSettings {
    settings.settings.widgets.cpu
  }

  private var theme: ABarTheme {
    ThemeManager.currentTheme(for: settings.settings.theme)
  }

  private var isVertical: Bool {
    orientation == .vertical
  }

  var body: some View {
    let graphColor = cpuSettings.graphColor.color(from: theme)

    BaseWidgetView(noPadding: true, onClick: openActivityMonitor) {
      if isVertical {
        verticalContent(graphColor: graphColor)
      } else {
        horizontalContent(graphColor: graphColor)
      }
    }
  }

  @ViewBuilder
  private func horizontalContent(graphColor: Color) -> some View {
    ZStack {
      HStack {
        GeometryReader { geometry in
          GraphView(
            values: systemInfo.cpuHistory.values,
            maxValue: 100.0,
            fillColor: graphColor,
            lineColor: graphColor,
            showLabels: false,
            vertical: false
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

  @ViewBuilder
  private func verticalContent(graphColor: Color) -> some View {
    VStack(spacing: 2) {
      // Icon at top
      if cpuSettings.showIcon {
        Image(systemName: "cpu")
          .font(.system(size: 10))
          .foregroundColor(graphColor)
      }

      // Percentage
      Text("\(Int(systemInfo.cpuUsage))%")
        .font(.system(size: 9))
        .foregroundColor(theme.foreground)
    }
    .padding(4)
  }

  private func openActivityMonitor() {
    Task {
      _ = try? await ShellExecutor.run("open -a 'Activity Monitor'")
    }
  }
}
