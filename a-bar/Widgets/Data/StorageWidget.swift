import SwiftUI

/// Storage usage widget with vertical bars for each volume
enum StorageWidgetConstants {
    static let barWidth: CGFloat = 16
    static let barHeight: CGFloat = 22
}

struct StorageWidget: View {
    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var storageInfo: SystemInfoService

    private var theme: ABarTheme {
        ThemeManager.currentTheme(for: settings.settings.theme)
    }

    var body: some View {
        BaseWidgetView(
            noPadding: true,
            onClick: openDiskUtility
        ) {
            HStack(spacing: 6) {
                ForEach(storageInfo.volumes) { volume in
                    HStack(spacing: 4) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 3)
                                .frame(width: StorageWidgetConstants.barWidth, height: StorageWidgetConstants.barHeight)
                                .foregroundColor(theme.mainAlt.opacity(0.18))
                            RoundedRectangle(cornerRadius: 3)
                                .frame(width: StorageWidgetConstants.barWidth, height: StorageWidgetConstants.barHeight * CGFloat(volume.fullness))
                                .foregroundColor(barColor(for: volume))
                        }
                        VStack(alignment: .leading) {
                            Text("\(volume.fullnessPercent)%")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(theme.foreground)
                            Text(shortName(for: volume.name))
                                .font(.system(size: 8))
                                .foregroundColor(theme.foreground.opacity(0.7))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: 50)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                }
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 6)
        }
    }

    private func barColor(for volume: StorageVolume) -> Color {
        switch volume.fullness {
        case let x where x > 0.9:
            return theme.red
        case let x where x > 0.75:
            return theme.yellow
        default:
            return theme.green
        }
    }

    private func shortName(for name: String) -> String {
        if name.lowercased().contains("macintosh") { return "Mac" }
        return name
    }

    private func openDiskUtility() {
        Task {
            _ = try? await ShellExecutor.run("open -a 'Disk Utility'")
        }
    }
}
