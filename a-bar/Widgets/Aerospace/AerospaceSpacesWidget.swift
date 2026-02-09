import SwiftUI

/// Widget displaying AeroSpace workspaces (spaces)
struct AerospaceSpacesWidget: View {
    let displayIndex: Int

    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var aerospaceService: AerospaceService

    private var globalSettings: GlobalSettings {
        settings.settings.global
    }

    private var spacesSettings: SpacesWidgetSettings {
        settings.settings.widgets.spaces
    }

    private var theme: ABarTheme {
        ThemeManager.currentTheme(for: settings.settings.theme)
    }

    var body: some View {
        HStack(spacing: globalSettings.barElementGap) {
            // Workspaces
            ForEach(filteredWorkspaces) { workspace in
                AerospaceSpaceView(
                    workspace: workspace,
                    displayIndex: displayIndex
                )
            }
        }
    }

    private var filteredWorkspaces: [AerospaceWorkspace] {
        let monitorId = displayIndex + 1
        var workspaces: [AerospaceWorkspace]

        // Filter by monitor if not showing all spaces on all screens
        if spacesSettings.showAllSpacesOnAllScreens {
            workspaces = aerospaceService.state.workspaces
        } else {
            workspaces = aerospaceService.state.workspaces(forMonitor: monitorId)
        }

        // Apply exclusions
        let exclusions = spacesSettings.exclusions
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        workspaces = workspaces.filter { workspace in
            let label = workspace.displayLabel

            if spacesSettings.exclusionsAsRegex {
                return !exclusions.contains { pattern in
                    label.matches(pattern: pattern)
                }
            } else {
                return !exclusions.contains(label)
            }
        }

        // Hide empty workspaces if enabled
        if spacesSettings.hideEmptySpaces {
            workspaces = workspaces.filter { workspace in
                workspace.isFocused ||
                workspace.isVisible ||
                !workspace.windows.isEmpty
            }
        }

        return workspaces
    }
}
