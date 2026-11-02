import SwiftUI

struct OpenedAppsView: View, Equatable {
    let windows: [YabaiWindowPresentation]
    let service: YabaiService

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.windows == rhs.windows && lhs.service === rhs.service
    }

    var body: some View {
        if !windows.isEmpty {
            HStack(spacing: 1) {
                ForEach(windows) { window in
                    AppIconButton(window: window, service: service).equatable()
                }
            }
        }
    }

    static func windows(for space: YabaiSpace, state: YabaiState, settings spacesSettings: SpacesWidgetSettings) -> [YabaiWindowPresentation] {
        let windows: [YabaiWindow]
        if spacesSettings.displayStickyWindowsSeparately {
            windows = state.nonStickyWindows(forSpace: space.index)
        } else {
            windows = state.windows(forSpace: space.index)
        }
        // Apply exclusions
        var filtered = WindowFilter.excludingWindows(
            windows,
            excludingApps: spacesSettings.exclusions,
            excludingTitles: spacesSettings.titleExclusions,
            asRegex: spacesSettings.exclusionsAsRegex,
            appName: \.app,
            title: \.title
        )
        // Remove duplicates if enabled
        if spacesSettings.hideDuplicateApps {
            filtered = WindowFilter.deduplicatedByApp(filtered, appName: \.app)
        }
        // Keep icon positions stable without changing which duplicate window they represent.
        return filtered.sorted { ($0.app, $0.id) < ($1.app, $1.id) }
            .map(YabaiWindowPresentation.init)
    }
}

struct AppIconButton: View, Equatable {
    let window: YabaiWindowPresentation
    
    @EnvironmentObject var settings: SettingsManager
    let service: YabaiService
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.window == rhs.window && lhs.service === rhs.service
    }

    @State private var isHovered = false
    
    private var theme: ABarTheme {
        ThemeManager.currentTheme(for: settings.settings.theme)
    }
    
    var body: some View {
        AppIconView(appName: window.app, size: 14)
            .opacity(window.hasFocus ? 1.0 : 0.7)
            .scaleEffect(isHovered ? 1.1 : 1.0)
            .onHover { hovering in
                withAnimation(.abarFast) {
                    isHovered = hovering
                }
            }
            .onTapGesture {
                focusWindow()
            }
            .help(window.title.isEmpty ? window.app : "\(window.app) - \(window.title)")
    }
    
    private func focusWindow() {
        Task {
            await service.focusWindow(window.id)
        }
    }
}
