import SwiftUI

/// Disk activity widget with graph showing read/write activity
struct DiskActivityWidget: View {
  @EnvironmentObject var settings: SettingsManager
  @EnvironmentObject var systemInfo: SystemInfoService

  private var diskSettings: DiskActivityWidgetSettings {
    settings.settings.widgets.diskActivity
  }

  private var theme: ABarTheme {
    ThemeManager.currentTheme(for: settings.settings.theme)
  }

  private var globalSettings: GlobalSettings {
    settings.settings.global
  }

  var body: some View {
    let readColor = diskSettings.readColor.color(from: theme)
    let writeColor = diskSettings.writeColor.color(from: theme)
    
    BaseWidgetView(noPadding: true, onClick: openActivityMonitor) {
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
              showLabels: false
            )
            // Write graph (red, overlayed)
            GraphView(
              values: systemInfo.diskWriteHistory.values,
              maxValue: max(1, systemInfo.diskWriteHistory.values.max() ?? 1) * 1.2,
              fillColor: writeColor,
              lineColor: writeColor,
              showLabels: false
            )
          }
          .frame(width: geometry.size.width, height: geometry.size.height)
          .cornerRadius(globalSettings.barElementsCornerRadius)
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
          Text(Double(systemInfo.diskStats.read).formattedTransferRate())
            .font(globalSettings.settingsFont(scaledBy: 0.8))
            .foregroundColor(theme.foreground)
            .padding(.top, -6)
            .padding(.leading, -4)
          Spacer()
        }

        // Write icon and speed (right)
        HStack {
          Spacer()
          Text(Double(systemInfo.diskStats.write).formattedTransferRate())
            .font(globalSettings.settingsFont(scaledBy: 0.8))
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
  }

  private func openActivityMonitor() {
    Task {
      _ = try? await ShellExecutor.run("open -a 'Activity Monitor'")
    }
  }
}
