import SwiftUI

struct GPUWidget: View {
  @EnvironmentObject var settings: SettingsManager
  @EnvironmentObject var systemInfo: SystemInfoService
  @Environment(\.widgetOrientation) var orientation

  private var gpuSettings: GPUWidgetSettings {
    settings.settings.widgets.gpu
  }

  private var theme: ABarTheme {
    ThemeManager.currentTheme(for: settings.settings.theme)
  }

  private var isVertical: Bool {
    orientation == .vertical
  }

  var body: some View {
    let isLoading = systemInfo.gpuUsage == 0 && systemInfo.gpuHistory.values.isEmpty
    let graphColor = gpuSettings.graphColor.color(from: theme)

    BaseWidgetView(noPadding: !isLoading, onClick: openActivityMonitor) {
      if isLoading {
        ProgressView()
          .scaleEffect(0.5)
          .frame(width: 16, height: 16)
      } else if isVertical {
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
            values: systemInfo.gpuHistory.values,
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

  @ViewBuilder
  private func verticalContent(graphColor: Color) -> some View {
    VStack(spacing: 2) {
      // Icon at top
      if gpuSettings.showIcon {
        Image(systemName: "cpu")
          .font(.system(size: 10))
          .foregroundColor(graphColor)
      }

      // Percentage
      Text("\(Int(systemInfo.gpuUsage))%")
        .font(.system(size: 9))
        .foregroundColor(theme.foreground)

      // Vertical graph
      GeometryReader { geometry in
        GraphView(
          values: systemInfo.gpuHistory.values,
          maxValue: 100.0,
          fillColor: graphColor,
          lineColor: graphColor,
          showLabels: false,
          vertical: true
        )
        .frame(
          width: geometry.size.width,
          height: geometry.size.height
        )
        .cornerRadius(4)
      }
      .frame(maxWidth: .infinity)
      .frame(height: 60)
      .clipped()
    }
    .padding(4)
  }

  private func openActivityMonitor() {
    Task {
      _ = try? await ShellExecutor.run("open -a 'Activity Monitor'")
    }
  }
}
