import SwiftUI

/// Network statistics widget with graph
struct NetstatsWidget: View {
  @EnvironmentObject var settings: SettingsManager
  @EnvironmentObject var systemInfo: SystemInfoService

  private var netstatsSettings: NetstatsWidgetSettings {
    settings.settings.widgets.netstats
  }

  private var theme: ABarTheme {
    ThemeManager.currentTheme(for: settings.settings.theme)
  }

  private var globalSettings: GlobalSettings {
    settings.settings.global
  }

  var body: some View {
    let downloadColor = netstatsSettings.downloadColor.color(from: theme)
    let uploadColor = netstatsSettings.uploadColor.color(from: theme)
    
    BaseWidgetView(noPadding: true, onClick: openNetworkUtility) {
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
              showLabels: false
            )
            // Upload graph (blue, overlayed)
            GraphView(
              values: systemInfo.uploadHistory.values,
              maxValue: max(1, systemInfo.uploadHistory.values.max() ?? 1) * 1.2,
              fillColor: uploadColor,
              lineColor: uploadColor,
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

        // Download icon and speed (left)
        HStack {
          Image(systemName: "arrow.down")
            .font(.system(size: 10))
            .foregroundColor(downloadColor)
            .padding(.leading, 6)
            .padding(.top, -6)
          Text(Double(systemInfo.networkStats.download).formattedTransferRate())
            .font(globalSettings.settingsFont(scaledBy: 0.8))
            .foregroundColor(theme.foreground)
            .padding(.top, -6)
            .padding(.leading, -4)
          Spacer()
        }

        // Upload icon and speed (right)
        HStack {
          Spacer()
          Text(Double(systemInfo.networkStats.upload).formattedTransferRate())
            .font(globalSettings.settingsFont(scaledBy: 0.8))
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
  }

  private func openNetworkUtility() {
    Task {
      _ = try? await ShellExecutor.run(
        "open /System/Library/CoreServices/Applications/Network\\ Utility.app 2>/dev/null || open -a 'Activity Monitor'"
      )
    }
  }
}
