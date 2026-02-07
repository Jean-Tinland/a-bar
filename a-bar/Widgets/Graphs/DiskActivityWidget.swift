import SwiftUI

/// Disk activity widget with graph showing read/write activity
struct DiskActivityWidget: View {
  @EnvironmentObject var settings: SettingsManager
  @EnvironmentObject var systemInfo: SystemInfoService
  @Environment(\.widgetOrientation) var orientation

  private var diskSettings: DiskActivityWidgetSettings {
    settings.settings.widgets.diskActivity
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
    let readColor = diskSettings.readColor.color(from: theme)
    let writeColor = diskSettings.writeColor.color(from: theme)

    BaseWidgetView(noPadding: true, onClick: openActivityMonitor) {
      if isVertical {
        verticalContent(readColor: readColor, writeColor: writeColor)
      } else {
        horizontalContent(readColor: readColor, writeColor: writeColor)
      }
    }
  }

  @ViewBuilder
  private func horizontalContent(readColor: Color, writeColor: Color) -> some View {
    ZStack {
      // Center graph
      GeometryReader { geometry in
        ZStack {
          // Read graph (blue)
          GraphView(
            values: systemInfo.diskReadHistory.values,
            maxValue: max(1, systemInfo.diskReadHistory.values.max() ?? 1) * 1.2,
            fillColor: readColor,
            lineColor: readColor,
            showLabels: false,
            vertical: false
          )
          // Write graph (red, overlayed)
          GraphView(
            values: systemInfo.diskWriteHistory.values,
            maxValue: max(1, systemInfo.diskWriteHistory.values.max() ?? 1) * 1.2,
            fillColor: writeColor,
            lineColor: writeColor,
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

      // Read icon and speed (left)
      HStack {
        Image(systemName: "arrow.down.doc")
          .font(.system(size: 10))
          .foregroundColor(readColor)
          .padding(.leading, 6)
          .padding(.top, -6)
        Text(formatSpeed(Double(systemInfo.diskStats.read)))
          .font(settingsFont(scaledBy: 0.8))
          .foregroundColor(theme.foreground)
          .padding(.top, -6)
          .padding(.leading, -4)
        Spacer()
      }

      // Write icon and speed (right)
      HStack {
        Spacer()
        Text(formatSpeed(Double(systemInfo.diskStats.write)))
          .font(settingsFont(scaledBy: 0.8))
          .foregroundColor(theme.foreground)
          .padding(.top, -6)
          .padding(.trailing, -4)
        Image(systemName: "arrow.up.doc")
          .font(.system(size: 10))
          .foregroundColor(writeColor)
          .padding(.trailing, 6)
          .padding(.top, -6)
      }
    }
  }

  @ViewBuilder
  private func verticalContent(readColor: Color, writeColor: Color) -> some View {
    VStack(spacing: 2) {
      // Read stats
      HStack(spacing: 2) {
        Image(systemName: "arrow.down.doc")
          .font(.system(size: 8))
          .foregroundColor(readColor)
        Text(formatSpeedCompact(Double(systemInfo.diskStats.read)))
          .font(.system(size: 8))
          .foregroundColor(theme.foreground)
      }

      // Write stats
      HStack(spacing: 2) {
        Image(systemName: "arrow.up.doc")
          .font(.system(size: 8))
          .foregroundColor(writeColor)
        Text(formatSpeedCompact(Double(systemInfo.diskStats.write)))
          .font(.system(size: 8))
          .foregroundColor(theme.foreground)
      }

      // Vertical graph
      GeometryReader { geometry in
        ZStack {
          GraphView(
            values: systemInfo.diskReadHistory.values,
            maxValue: max(1, systemInfo.diskReadHistory.values.max() ?? 1) * 1.2,
            fillColor: readColor,
            lineColor: readColor,
            showLabels: false,
            vertical: true
          )
          GraphView(
            values: systemInfo.diskWriteHistory.values,
            maxValue: max(1, systemInfo.diskWriteHistory.values.max() ?? 1) * 1.2,
            fillColor: writeColor,
            lineColor: writeColor,
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

  private func openActivityMonitor() {
    Task {
      _ = try? await ShellExecutor.run("open -a 'Activity Monitor'")
    }
  }
}
