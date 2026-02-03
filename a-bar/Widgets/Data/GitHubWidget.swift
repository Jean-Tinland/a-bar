import SwiftUI

/// GitHub notifications widget
struct GitHubWidget: View {
    @EnvironmentObject var settings: SettingsManager
    
    @State private var notificationCount: Int = 0
    @State private var isLoading = true
    
    private var githubSettings: GitHubWidgetSettings {
        settings.settings.widgets.github
    }
    
    private var theme: ABarTheme {
        ThemeManager.currentTheme(for: settings.settings.theme)
    }
    
    var body: some View {
        // Hide if no notifications and setting is enabled
        if githubSettings.hideWhenNoNotifications && notificationCount == 0 && !isLoading {
            EmptyView()
        } else {
            BaseWidgetView(
                isHighlighted: notificationCount > 0,
                highlightColor: theme.blue.opacity(0.2),
                onClick: openNotifications,
                onRightClick: refreshNotifications
            ) {
                HStack(spacing: 4) {
                    if githubSettings.showIcon {
                        Image("GitHubIcon")
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 12, height: 12)
                            .foregroundColor(notificationCount > 0 ? theme.blue : theme.foreground)
                    }
                    
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.4)
                            .frame(width: 12, height: 12)
                    } else {
                        Text(notificationText)
                            .foregroundColor(notificationCount > 0 ? theme.blue : theme.foreground)
                    }
                }
            }
            .onAppear {
                if isLoading {
                    refreshNotifications()
                }
            }
            .onReceive(Timer.publish(every: githubSettings.refreshInterval, on: .main, in: .common).autoconnect()) { _ in
                refreshNotifications()
            }
        }
    }
    
    private var notificationText: String {
        if notificationCount > 99 {
            return "99+"
        }
        return "\(notificationCount)"
    }
    
    private func refreshNotifications() {
        Task {
            isLoading = true
            
            do {
                let output = try await ShellExecutor.run("\(githubSettings.ghBinaryPath) api notifications 2>/dev/null")
                
                if let data = output.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    await MainActor.run {
                        notificationCount = json.count
                        isLoading = false
                    }
                } else {
                    await MainActor.run {
                        notificationCount = 0
                        isLoading = false
                    }
                }
            } catch {
                print("GitHub notification fetch error: \(error)")
                await MainActor.run {
                    notificationCount = 0
                    isLoading = false
                }
            }
        }
    }
    
    private func openNotifications() {
        if let url = URL(string: githubSettings.notificationUrl) {
            NSWorkspace.shared.open(url)
        }
    }
}
