import SwiftUI

/// Widget showing the currently focused application and window
struct ProcessWidget: View {
    let displayIndex: Int

    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var yabaiService: YabaiService
    @Environment(\.widgetOrientation) var orientation

    private var processSettings: ProcessWidgetSettings {
        settings.settings.widgets.process
    }

    private var theme: ABarTheme {
        ThemeManager.currentTheme(for: settings.settings.theme)
    }

    private var isVertical: Bool {
        orientation == .vertical
    }

    var body: some View {
        let globalSettings = settings.settings.global
        let userFont: Font = globalSettings.fontName.isEmpty ? .system(size: CGFloat(globalSettings.fontSize)) : .custom(globalSettings.fontName, size: CGFloat(globalSettings.fontSize))
        let userFontSmall: Font = globalSettings.fontName.isEmpty ? .system(size: CGFloat(Double(globalSettings.fontSize) * 0.9)) : .custom(globalSettings.fontName, size: CGFloat(Double(globalSettings.fontSize) * 0.9))

        let state = yabaiService.state
        let focusedWin = state.focusedWindow

        let windowsOnCurrentSpace: [YabaiWindow] = {
            if processSettings.showCurrentSpaceOnly {
                guard let focusedSpace = state.focusedSpace else { return [] }
                return state.windows.filter { $0.space == focusedSpace.index }
            }
            return state.windows
        }()

        // Order windows the same way as OpenedAppsView: by stackIndex then by x position
        let orderedWindows = windowsOnCurrentSpace.sorted {
            if let idxA = $0.stackIndex, let idxB = $1.stackIndex, idxA != idxB {
                return idxA < idxB
            }
            return $0.frame.x < $1.frame.x
        }

        // Determine current space and layout mode for this view
        let currentSpace: YabaiSpace? = {
            if processSettings.showCurrentSpaceOnly {
                return state.focusedSpace
            }
            if let firstSpaceIndex = windowsOnCurrentSpace.first?.space {
                return state.spaces.first { $0.index == firstSpaceIndex }
            }
            return nil
        }()

        let layoutMode = currentSpace?.type.rawValue

        if orderedWindows.isEmpty {
            // No windows: show desktop
            AdaptiveStack(hSpacing: 4, vSpacing: 2) {
                Image(systemName: "app.dashed")
                    .font(userFont)
                    .foregroundColor(theme.foreground.opacity(0.6))
                if !processSettings.displayOnlyIcon && !isVertical {
                    Text("Desktop")
                        .font(userFont)
                        .foregroundColor(theme.foreground.opacity(0.6))
                }
            }
            .padding(.horizontal, 6)
            .padding(.leading, isVertical ? 0 : 4)
            .padding(.vertical, 3)
        } else {
            if isVertical {
                verticalWindowsContent(
                    orderedWindows: orderedWindows,
                    focusedWin: focusedWin,
                    layoutMode: layoutMode,
                    globalSettings: globalSettings,
                    userFont: userFont,
                    userFontSmall: userFontSmall
                )
            } else {
                horizontalWindowsContent(
                    orderedWindows: orderedWindows,
                    focusedWin: focusedWin,
                    layoutMode: layoutMode,
                    globalSettings: globalSettings,
                    userFont: userFont,
                    userFontSmall: userFontSmall
                )
            }
        }
    }

    @ViewBuilder
    private func horizontalWindowsContent(
        orderedWindows: [YabaiWindow],
        focusedWin: YabaiWindow?,
        layoutMode: String?,
        globalSettings: GlobalSettings,
        userFont: Font,
        userFontSmall: Font
    ) -> some View {
        HStack(spacing: globalSettings.barElementGap) {
            if let layoutMode = layoutMode, processSettings.showLayoutMode {
                Text(layoutMode)
                    .font(userFont.weight(.medium))
                    .foregroundColor(theme.foreground.opacity(0.9))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(theme.mainAlt.opacity(0.5))
                    )
            }
            ForEach(orderedWindows, id: \.id) { window in
                windowView(
                    window: window,
                    isFocused: window.id == focusedWin?.id,
                    globalSettings: globalSettings,
                    userFont: userFont,
                    userFontSmall: userFontSmall
                )
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func verticalWindowsContent(
        orderedWindows: [YabaiWindow],
        focusedWin: YabaiWindow?,
        layoutMode: String?,
        globalSettings: GlobalSettings,
        userFont: Font,
        userFontSmall: Font
    ) -> some View {
        VStack(spacing: globalSettings.barElementGap) {
            if let layoutMode = layoutMode, processSettings.showLayoutMode {
                Text(layoutMode)
                    .font(userFont.weight(.medium))
                    .foregroundColor(theme.foreground.opacity(0.9))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(theme.mainAlt.opacity(0.5))
                    )
            }
            ForEach(orderedWindows, id: \.id) { window in
                // In vertical mode, only show app icon
                AppIconView(appName: window.app, size: 16)
                    .opacity(window.id == focusedWin?.id ? 1.0 : 0.6)
                    .padding(4)
                    .background(
                        window.id == focusedWin?.id
                            ? RoundedRectangle(cornerRadius: 4).fill(theme.mainAlt.opacity(0.5))
                            : nil
                    )
                    .onTapGesture {
                        focusWindow(window)
                    }
                    .onHover { hovering in
                        if hovering {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func windowView(
        window: YabaiWindow,
        isFocused: Bool,
        globalSettings: GlobalSettings,
        userFont: Font,
        userFontSmall: Font
    ) -> some View {
        if isFocused {
            // Focused window: show icon, app name, title, and optional stack index badge on the right
            HStack(spacing: globalSettings.barElementGap) {
                AppIconView(appName: window.app, size: 16)
                if !processSettings.displayOnlyIcon {
                    VStack(alignment: .leading, spacing: -1) {
                        Text(window.app)
                            .font(userFont.weight(.medium))
                            .foregroundColor(theme.foreground)
                        if !processSettings.hideWindowTitle && !window.title.isEmpty {
                            Text(window.title.truncated(to: 20))
                                .font(userFont)
                                .foregroundColor(theme.foreground.opacity(0.7))
                        }
                    }
                }
                if let idx = window.stackIndex, idx != 0 {
                    Text("\(idx)")
                        .font(userFontSmall.weight(.medium))
                        .foregroundColor(theme.foreground.opacity(0.9))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(theme.minor.opacity(0.5))
                        )
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, processSettings.hideWindowTitle || processSettings.displayOnlyIcon ? 3 : 0)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(theme.mainAlt.opacity(0.5))
            )
            .onTapGesture {
                focusWindow(window)
            }
            .onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        } else {
            // Non-focused window: show only icon, optionally with small stack index badge
            HStack(spacing: 4) {
                AppIconView(appName: window.app, size: 16)
                if let idx = window.stackIndex, idx != 0 {
                    Text("\(idx)")
                        .font(userFontSmall.weight(.medium))
                        .foregroundColor(theme.foreground.opacity(0.85))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(theme.minor.opacity(0.5))
                        )
                }
            }
            .opacity(0.8)
            .onTapGesture {
                focusWindow(window)
            }
            .onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
    }
    
    private var focusedWindow: YabaiWindow? {
        let state = yabaiService.state
        
        if processSettings.showCurrentSpaceOnly {
            // Only show process if it's in the current space
            guard let focusedSpace = state.focusedSpace else { return nil }
            return state.focusedWindow.flatMap { window in
                window.space == focusedSpace.index ? window : nil
            }
        }
        
        return state.focusedWindow
    }
    
    private func focusWindow(_ window: YabaiWindow) {
        Task {
            await yabaiService.focusWindow(window.id)
        }
    }
}
