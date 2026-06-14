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

    var body: some View {
        HStack(spacing: globalSettings.barElementGap) {
            // Workspaces
            ForEach(filteredWorkspaces) { workspace in
                AerospaceSpaceView(
                    workspace: workspace
                )
            }
        }
    }

    private var filteredWorkspaces: [AerospaceWorkspace] {
        var workspaces: [AerospaceWorkspace]

        // Filter by monitor if not showing all spaces on all screens
        if spacesSettings.showAllSpacesOnAllScreens {
            workspaces = aerospaceService.state.workspaces
        } else {
            // Match by screen name to correctly map AeroSpace monitors to macOS screens,
            // since AeroSpace monitor IDs don't necessarily follow NSScreen ordering.
            let screens = NSScreen.screens
            if screens.indices.contains(displayIndex),
               let monitorId = aerospaceService.state.monitorId(forScreenName: screens[displayIndex].localizedName) {
                workspaces = aerospaceService.state.workspaces(forMonitor: monitorId)
            } else {
                workspaces = aerospaceService.state.workspaces(forMonitor: displayIndex + 1)
            }
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
