import AppKit
import SwiftUI

/// Network statistics widget with graph
struct NetstatsWidget: View {
  @EnvironmentObject var systemInfo: SystemInfoService

  var body: some View {
    NetstatsPanel(
      downloadHistory: systemInfo.downloadHistory.values,
      uploadHistory: systemInfo.uploadHistory.values,
      download: Double(systemInfo.networkStats.download),
      upload: Double(systemInfo.networkStats.upload),
      onClick: openNetworkUtility)
  }

  private func openNetworkUtility() {
    Task {
      _ = try? await ShellExecutor.run(
        "open /System/Library/CoreServices/Applications/Network\\ Utility.app 2>/dev/null || open -a 'Activity Monitor'"
      )
    }
  }
}

/// Keep the ordinary font sizes; only shrink a row that cannot fit the bar's inner height.
struct NetstatsLayout {
  let height: CGFloat
  let contentScale: CGFloat

  init(global: GlobalSettings) {
    height = max(0, global.barHeight - 2 * global.barVerticalPadding)
    let textSize = global.fontSize * 0.8
    let textFont = NSFont(name: global.fontName, size: textSize) ?? .systemFont(ofSize: textSize)
    let layoutManager = NSLayoutManager()
    let rowHeight = max(layoutManager.defaultLineHeight(for: textFont),
                        layoutManager.defaultLineHeight(for: .systemFont(ofSize: 10)))
    contentScale = min(1, height / rowHeight)
  }
}

/// The panel can render cached samples without starting the system information service.
struct NetstatsPanel: View {
  let downloadHistory: [Double]
  let uploadHistory: [Double]
  let download: Double
  let upload: Double
  var onClick: (() -> Void)? = nil

  @EnvironmentObject var settings: SettingsManager

  var body: some View {
    let global = settings.settings.global
    let netstats = settings.settings.widgets.netstats
    let theme = ThemeManager.currentTheme(for: settings.settings.theme)
    let downloadColor = netstats.downloadColor.color(from: theme)
    let uploadColor = netstats.uploadColor.color(from: theme)
    let layout = NetstatsLayout(global: global)

    if layout.height > 0 {
      BaseWidgetView(noPadding: true, onClick: onClick) {
        ZStack {
          ZStack {
            GraphView(
              values: downloadHistory,
              maxValue: max(1, downloadHistory.max() ?? 1) * 1.2,
              fillColor: downloadColor,
              lineColor: downloadColor,
              showLabels: false)
            GraphView(
              values: uploadHistory,
              maxValue: max(1, uploadHistory.max() ?? 1) * 1.2,
              fillColor: uploadColor,
              lineColor: uploadColor,
              showLabels: false)
          }
          .frame(width: 140, height: layout.height)
          .cornerRadius(global.barElementsCornerRadius)

          HStack(spacing: 4) {
            Image(systemName: "arrow.down")
              .font(.system(size: 10 * layout.contentScale))
              .foregroundColor(downloadColor)
            Text(download.formattedTransferRate())
              .font(global.settingsFont(scaledBy: 0.8 * Double(layout.contentScale)))
              .foregroundColor(theme.foreground)
            Spacer(minLength: 0)
            Text(upload.formattedTransferRate())
              .font(global.settingsFont(scaledBy: 0.8 * Double(layout.contentScale)))
              .foregroundColor(theme.foreground)
            Image(systemName: "arrow.up")
              .font(.system(size: 10 * layout.contentScale))
              .foregroundColor(uploadColor)
          }
          .padding(.horizontal, 6)
          .frame(width: 140, height: layout.height)
        }
        .frame(width: 140, height: layout.height)
      }
      .frame(width: 140, height: layout.height)
      .clipped()
    } else {
      Color.clear.frame(width: 140, height: 0)
    }
  }
}
