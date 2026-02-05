import SwiftUI

/// Network statistics widget with graph
struct NetstatsWidget: View {
  @EnvironmentObject var settings: SettingsManager
  @EnvironmentObject var systemInfo: SystemInfoService
  @Environment(\.widgetOrientation) var orientation

  private var netstatsSettings: NetstatsWidgetSettings {
    settings.settings.widgets.netstats
  }

  private var theme: ABarTheme {
    ThemeManager.currentTheme(for: settings.settings.theme)
  }

  private var globalSettings: GlobalSettings {
    settings.settings.global
  }

  private var isVertical: Bool {
    orientation == .vertical
  }

  private var userFont: Font {
    globalSettings.fontName.isEmpty
      ? .system(size: CGFloat(globalSettings.fontSize))
      : .custom(globalSettings.fontName, size: CGFloat(globalSettings.fontSize))
  }

  private func settingsFont(
    scaledBy factor: Double = 1.0, weight: Font.Weight? = nil, design: Font.Design? = nil
  ) -> Font {
    let size = CGFloat(Double(globalSettings.fontSize) * factor)
    if globalSettings.fontName.isEmpty {
      if let weight = weight {
        if let design = design {
          return .system(size: size, weight: weight, design: design)
        }
        return .system(size: size, weight: weight)
      }
      return .system(size: size)
    }
    return .custom(globalSettings.fontName, size: size)
  }

  var body: some View {
    let downloadColor = netstatsSettings.downloadColor.color(from: theme)
    let uploadColor = netstatsSettings.uploadColor.color(from: theme)

    BaseWidgetView(noPadding: true, onClick: openNetworkUtility) {
      if isVertical {
        verticalContent(downloadColor: downloadColor, uploadColor: uploadColor)
      } else {
        horizontalContent(downloadColor: downloadColor, uploadColor: uploadColor)
      }
    }
  }

  @ViewBuilder
  private func horizontalContent(downloadColor: Color, uploadColor: Color) -> some View {
    ZStack {
      // Center graph
      GeometryReader { geometry in
        ZStack {
          // Download graph (magenta)
          GraphView(
            values: systemInfo.downloadHistory.values,
            maxValue: max(1, systemInfo.downloadHistory.values.max() ?? 1) * 1.2,
            fillColor: downloadColor,
            lineColor: downloadColor,
            showLabels: false,
            vertical: false
          )
          // Upload graph (blue, overlayed)
          GraphView(
            values: systemInfo.uploadHistory.values,
            maxValue: max(1, systemInfo.uploadHistory.values.max() ?? 1) * 1.2,
            fillColor: uploadColor,
            lineColor: uploadColor,
            showLabels: false,
            vertical: false
          )
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
        .cornerRadius(4)
        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .clipped()
      .padding(.horizontal, 0)
      .frame(width: 140)

      // Download icon and speed (left)
      HStack {
        Image(systemName: "arrow.down")
          .font(.system(size: 10))
          .foregroundColor(downloadColor)
          .padding(.leading, 6)
          .padding(.top, -6)
        Text(formatSpeed(Double(systemInfo.networkStats.download)))
          .font(settingsFont(scaledBy: 0.8))
          .foregroundColor(theme.foreground)
          .padding(.top, -6)
          .padding(.leading, -4)
        Spacer()
      }

      // Upload icon and speed (right)
      HStack {
        Spacer()
        Text(formatSpeed(Double(systemInfo.networkStats.upload)))
          .font(settingsFont(scaledBy: 0.8))
          .foregroundColor(theme.foreground)
          .padding(.top, -6)
          .padding(.trailing, -4)
        Image(systemName: "arrow.up")
          .font(.system(size: 10))
          .foregroundColor(uploadColor)
          .padding(.trailing, 6)
          .padding(.top, -6)
      }
    }
  }

  @ViewBuilder
  private func verticalContent(downloadColor: Color, uploadColor: Color) -> some View {
    VStack(spacing: 2) {
      // Download stats
      HStack(spacing: 2) {
        Image(systemName: "arrow.down")
          .font(.system(size: 8))
          .foregroundColor(downloadColor)
        Text(formatSpeedCompact(Double(systemInfo.networkStats.download)))
          .font(.system(size: 8))
          .foregroundColor(theme.foreground)
      }

      // Upload stats
      HStack(spacing: 2) {
        Image(systemName: "arrow.up")
          .font(.system(size: 8))
          .foregroundColor(uploadColor)
        Text(formatSpeedCompact(Double(systemInfo.networkStats.upload)))
          .font(.system(size: 8))
          .foregroundColor(theme.foreground)
      }

      // Vertical graph
      GeometryReader { geometry in
        ZStack {
          GraphView(
            values: systemInfo.downloadHistory.values,
            maxValue: max(1, systemInfo.downloadHistory.values.max() ?? 1) * 1.2,
            fillColor: downloadColor,
            lineColor: downloadColor,
            showLabels: false,
            vertical: true
          )
          GraphView(
            values: systemInfo.uploadHistory.values,
            maxValue: max(1, systemInfo.uploadHistory.values.max() ?? 1) * 1.2,
            fillColor: uploadColor,
            lineColor: uploadColor,
            showLabels: false,
            vertical: true
          )
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
        .cornerRadius(4)
      }
      .frame(maxWidth: .infinity)
      .frame(height: 50)
      .clipped()
    }
    .padding(4)
  }

  private func formatSpeedCompact(_ bytesPerSecond: Double) -> String {
    if bytesPerSecond < 1024 {
      return String(format: "%.0fB", bytesPerSecond)
    } else if bytesPerSecond < 1024 * 1024 {
      return String(format: "%.0fK", bytesPerSecond / 1024)
    } else if bytesPerSecond < 1024 * 1024 * 1024 {
      return String(format: "%.1fM", bytesPerSecond / 1024 / 1024)
    } else {
      return String(format: "%.1fG", bytesPerSecond / 1024 / 1024 / 1024)
    }
  }

  private func formatSpeed(_ bytesPerSecond: Double) -> String {
    if bytesPerSecond < 1024 {
      return String(format: "%.0fB/s", bytesPerSecond)
    } else if bytesPerSecond < 1024 * 1024 {
      return String(format: "%.1fK/s", bytesPerSecond / 1024)
    } else if bytesPerSecond < 1024 * 1024 * 1024 {
      return String(format: "%.1fM/s", bytesPerSecond / 1024 / 1024)
    } else {
      return String(format: "%.1fG/s", bytesPerSecond / 1024 / 1024 / 1024)
    }
  }

  private func openNetworkUtility() {
    Task {
      _ = try? await ShellExecutor.run(
        "open /System/Library/CoreServices/Applications/Network\\ Utility.app 2>/dev/null || open -a 'Activity Monitor'"
      )
    }
  }
}
