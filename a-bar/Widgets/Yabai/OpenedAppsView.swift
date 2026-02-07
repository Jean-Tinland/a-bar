import SwiftUI

/// View showing app icons for windows in a space
struct OpenedAppsView: View {
    let space: YabaiSpace
    let displayIndex: Int

    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var yabaiService: YabaiService
    @Environment(\.widgetOrientation) var orientation

    private var spacesSettings: SpacesWidgetSettings {
        settings.settings.widgets.spaces
    }

    private var theme: ABarTheme {
        ThemeManager.currentTheme(for: settings.settings.theme)
    }

    private var isVertical: Bool {
        orientation == .vertical
    }

    var body: some View {
        if !displayedApps.isEmpty {
            if isVertical {
                // In vertical mode, show fewer icons or wrap them
                VStack(spacing: 1) {
                    ForEach(displayedApps.prefix(3), id: \.id) { window in
                        AppIconButton(window: window)
                    }
                }
            } else {
                HStack(spacing: 1) {
                    ForEach(displayedApps, id: \.id) { window in
                        AppIconButton(window: window)
                    }
                }
            }
        }
    }
    
    private var displayedApps: [YabaiWindow] {
        let windows: [YabaiWindow]
        if spacesSettings.displayStickyWindowsSeparately {
            windows = yabaiService.state.nonStickyWindows(forSpace: space.index)
        } else {
            windows = yabaiService.state.windows(forSpace: space.index)
        }
        // Apply exclusions
        let exclusions = spacesSettings.exclusions
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let titleExclusions = spacesSettings.titleExclusions
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        var filtered = windows.filter { window in
            // Check app name exclusions
            let appExcluded = spacesSettings.exclusionsAsRegex
                ? exclusions.contains { window.app.matches(pattern: $0) }
                : exclusions.contains(window.app)
            // Check title exclusions
            let titleExcluded = spacesSettings.exclusionsAsRegex
                ? titleExclusions.contains { window.title.matches(pattern: $0) }
                : titleExclusions.contains { window.title.contains($0) }
            return !appExcluded && !titleExcluded
        }
        // Remove duplicates if enabled
        if spacesSettings.hideDuplicateApps {
            var seen = Set<String>()
            filtered = filtered.filter { window in
                if seen.contains(window.app) {
                    return false
                }
                seen.insert(window.app)
                return true
            }
        }
        // Order by stack index if available, else by position (frame.x)
        filtered.sort {
            if let idxA = $0.stackIndex, let idxB = $1.stackIndex, idxA != idxB {
                return idxA < idxB
            }
            // Otherwise, order by x position (left to right)
            return $0.frame.x < $1.frame.x
        }
        return filtered
    }
}

struct AppIconButton: View {
    let window: YabaiWindow
    
    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var yabaiService: YabaiService
    
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
            await yabaiService.focusWindow(window.id)
        }
    }
}
