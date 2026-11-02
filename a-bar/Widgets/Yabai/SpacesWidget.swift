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
    
    var body: some View {
        HStack(spacing: globalSettings.barElementGap) {
            // Sticky windows section (if enabled)
            if spacesSettings.displayStickyWindowsSeparately {
                let stickyWindows = yabaiService.state.stickyWindows()
                if !stickyWindows.isEmpty {
                    StickyWindowsView(apps: WindowFilter.deduplicatedByApp(stickyWindows, appName: \.app).map(\.app)).equatable()
                }
            }
            
            // Spaces
            ForEach(filteredSpaces) { space in
                SpaceView(
                    space: space,
                    displayIndex: displayIndex,
                    yabaiService: yabaiService,
                    windows: OpenedAppsView.windows(for: space, state: yabaiService.state, settings: spacesSettings)
                ).equatable()
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
        spaces = WindowFilter.excludingLabels(
            spaces,
            excluding: spacesSettings.exclusions,
            asRegex: spacesSettings.exclusionsAsRegex,
            label: \.displayLabel
        )
        
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
    
}

struct StickyWindowsView: View, Equatable {
    let apps: [String]

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.apps == rhs.apps }
    
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
                .foregroundColor(theme.foreground.opacity(0.8))
            
            ForEach(apps, id: \.self) { app in
                AppIconView(appName: app, size: 14)
            }
        }
        .frame(maxHeight: .infinity)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(
          RoundedRectangle(cornerRadius: globalSettings.barElementsCornerRadius)
            .fill(
              theme.mainAlt
                .opacity((globalSettings.barElementsBackgroundOpacity / 100.0) * 0.45)
            )
        )
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
                .padding(.horizontal, 6)
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
