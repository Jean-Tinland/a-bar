import SwiftUI

/// Widget displaying yabai spaces
struct SpacesWidget: View {
    let displayIndex: Int
    
    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var yabaiService: YabaiService

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
            // Sticky windows section (if enabled)
            if spacesSettings.displayStickyWindowsSeparately {
                let stickyWindows = yabaiService.state.stickyWindows()
                if !stickyWindows.isEmpty {
                    StickyWindowsView(windows: stickyWindows)
                }
            }
            
            // Spaces
            ForEach(filteredSpaces) { space in
                SpaceView(
                    space: space,
                    displayIndex: displayIndex,
                    currentSpaceIndex: currentSpaceIndex
                )
            }
            
            // Create space button (requires SIP disabled)
            if !spacesSettings.hideCreateSpaceButton {
                CreateSpaceButton(displayIndex: displayIndex)
            }
        }
    }
    
    private var filteredSpaces: [YabaiSpace] {
        var spaces = yabaiService.state.spaces
        
        // Filter by display if not showing all spaces on all screens
        if !spacesSettings.showAllSpacesOnAllScreens {
            spaces = spaces.filter { $0.display == displayIndex + 1 }
        }
        
        // Apply exclusions
        let exclusions = spacesSettings.exclusions
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        
        spaces = spaces.filter { space in
            let label = space.displayLabel
            
            if spacesSettings.exclusionsAsRegex {
                return !exclusions.contains { pattern in
                    label.matches(pattern: pattern)
                }
            } else {
                return !exclusions.contains(label)
            }
        }
        
        // Hide empty spaces if enabled
        if spacesSettings.hideEmptySpaces {
            spaces = spaces.filter { space in
                space.hasFocus || 
                space.isVisible || 
                !yabaiService.state.windows(forSpace: space.index).isEmpty
            }
        }
        
        return spaces
    }
    
    private var currentSpaceIndex: Int {
        yabaiService.state.focusedSpace?.index ?? 1
    }
}

struct StickyWindowsView: View {
    let windows: [YabaiWindow]
    
    @EnvironmentObject var settings: SettingsManager
    
    private var globalSettings: GlobalSettings {
        settings.settings.global
    }
    
    private var theme: ABarTheme {
        ThemeManager.currentTheme(for: settings.settings.theme)
    }
    
    var body: some View {
        HStack(spacing: globalSettings.barElementGap) {
            Image(systemName: "pin.fill")
                .font(.system(size: 8))
                .foregroundColor(theme.minor)
            
            ForEach(uniqueApps, id: \.id) { window in
                AppIconView(appName: window.app, size: 14)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(theme.mainAlt)
        )
    }
    
    private var uniqueApps: [YabaiWindow] {
        var seen = Set<String>()
        return windows.filter { window in
            if seen.contains(window.app) {
                return false
            }
            seen.insert(window.app)
            return true
        }
    }
}

struct CreateSpaceButton: View {
    let displayIndex: Int
    
    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var yabaiService: YabaiService
    
    private var theme: ABarTheme {
        ThemeManager.currentTheme(for: settings.settings.theme)
    }
    
    var body: some View {
        Button(action: createSpace) {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(theme.foreground.opacity(0.8))
                .padding(.leading, 6)
                .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
    
    private func createSpace() {
        Task {
            await yabaiService.createSpace(onDisplay: displayIndex + 1)
        }
    }
}
