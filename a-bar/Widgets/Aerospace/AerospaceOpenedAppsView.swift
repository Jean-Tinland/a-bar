import SwiftUI

/// View showing app icons for windows in an AeroSpace workspace
struct AerospaceOpenedAppsView: View {
    let workspace: AerospaceWorkspace

    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var aerospaceService: AerospaceService

    private var spacesSettings: SpacesWidgetSettings {
        settings.settings.widgets.spaces
    }

    private var theme: ABarTheme {
        ThemeManager.currentTheme(for: settings.settings.theme)
    }

    var body: some View {
        if !displayedApps.isEmpty {
            HStack(spacing: 1) {
                ForEach(displayedApps) { window in
                    AerospaceAppIconButton(window: window)
                }
            }
        }
    }

    private var displayedApps: [AerospaceWindow] {
        var windows = workspace.windows

        // Apply exclusions
        let exclusions = spacesSettings.exclusions
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let titleExclusions = spacesSettings.titleExclusions
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        windows = windows.filter { window in
            let appExcluded = spacesSettings.exclusionsAsRegex
                ? exclusions.contains { window.appName.matches(pattern: $0) }
                : exclusions.contains(window.appName)
            let titleExcluded = spacesSettings.exclusionsAsRegex
                ? titleExclusions.contains { window.windowTitle.matches(pattern: $0) }
                : titleExclusions.contains { window.windowTitle.contains($0) }
            return !appExcluded && !titleExcluded
        }

        // Remove duplicates if enabled
        if spacesSettings.hideDuplicateApps {
            var seen = Set<String>()
            windows = windows.filter { window in
                if seen.contains(window.appName) {
                    return false
                }
                seen.insert(window.appName)
                return true
            }
        }

        return windows
    }
}

struct AerospaceAppIconButton: View {
    let window: AerospaceWindow

    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var aerospaceService: AerospaceService

    @State private var isHovered = false

    private var theme: ABarTheme {
        ThemeManager.currentTheme(for: settings.settings.theme)
    }

    var body: some View {
        AppIconView(appName: window.appName, size: 14)
            .opacity(window.isFocused ? 1.0 : 0.7)
            .scaleEffect(isHovered ? 1.1 : 1.0)
            .onHover { hovering in
                withAnimation(.abarFast) {
                    isHovered = hovering
                }
            }
            .onTapGesture {
                focusWindow()
            }
            .help(window.windowTitle.isEmpty ? window.appName : "\(window.appName) - \(window.windowTitle)")
    }

    private func focusWindow() {
        Task {
            await aerospaceService.focusWindow(window.windowId)
        }
    }
}
