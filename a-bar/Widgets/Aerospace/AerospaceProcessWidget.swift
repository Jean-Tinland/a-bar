import SwiftUI

/// Widget showing the currently focused application and window for AeroSpace
struct AerospaceProcessWidget: View {
    let displayIndex: Int

    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var aerospaceService: AerospaceService
    
    @State private var focusedWindowPressed = false
    @State private var unfocusedWindowPressed: Set<Int> = []

    private var processSettings: ProcessWidgetSettings {
        settings.settings.widgets.process
    }

    private var theme: ABarTheme {
        ThemeManager.currentTheme(for: settings.settings.theme)
    }

    var body: some View {
        let globalSettings = settings.settings.global
        let userFont: Font = globalSettings.fontName.isEmpty
            ? .system(size: CGFloat(globalSettings.fontSize))
            : .custom(globalSettings.fontName, size: CGFloat(globalSettings.fontSize))

        let state = aerospaceService.state
        let focusedWin = state.focusedWindow
        let monitorId = displayIndex + 1

        let windowsOnCurrentSpace: [AerospaceWindow] = {
            if processSettings.showCurrentSpaceOnly {
                guard let focusedWorkspace = state.focusedWorkspace else { return [] }
                // Only show windows from the focused workspace on this monitor
                if focusedWorkspace.monitorId == monitorId {
                    return focusedWorkspace.windows
                }
                return []
            }
            // Show all windows on this monitor
            return state.workspaces(forMonitor: monitorId).flatMap { $0.windows }
        }()

        if windowsOnCurrentSpace.isEmpty {
            // No windows: show desktop
            HStack(spacing: 4) {
                Image(systemName: "app.dashed")
                    .font(userFont)
                    .foregroundColor(theme.foreground.opacity(0.6))
                if !processSettings.displayOnlyIcon {
                    Text("Desktop")
                        .font(userFont)
                        .foregroundColor(theme.foreground.opacity(0.6))
                }
            }
            .padding(.horizontal, 6)
            .padding(.leading, 4)
            .padding(.vertical, 3)
        } else {
            HStack(spacing: globalSettings.barElementGap) {
                ForEach(windowsOnCurrentSpace) { window in
                    if window.id == focusedWin?.id {
                        // Focused window
                        HStack(spacing: globalSettings.barElementGap) {
                            AppIconView(appName: window.appName, size: 16)
                            if !processSettings.displayOnlyIcon {
                                VStack(alignment: .leading, spacing: -1) {
                                    Text(window.appName)
                                        .font(userFont.weight(.medium))
                                        .foregroundColor(theme.foreground)
                                    if !processSettings.hideWindowTitle && !window.windowTitle.isEmpty {
                                        Text(window.windowTitle.truncated(to: 20))
                                            .font(userFont)
                                            .foregroundColor(theme.foreground.opacity(0.7))
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, processSettings.hideWindowTitle || processSettings.displayOnlyIcon ? 3 : 0)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                              .fill(theme.mainAlt.opacity((globalSettings.barElementsBackgroundOpacity / 100) * 0.5))
                        )
                        .overlay(
                          Group {
                            if (globalSettings.showElementsBorder) {
                              
                              RoundedRectangle(
                                cornerRadius: globalSettings.barElementsCornerRadius
                              )
                              .stroke(theme.foreground.opacity(0.1), lineWidth: 1)
                            }
                          }
                        )
                        .scaleEffect(focusedWindowPressed ? 0.94 : 1.0)
                        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: focusedWindowPressed)
                        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
                            focusedWindowPressed = pressing
                        }) {}
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
                        // Non-focused window
                        HStack(spacing: 4) {
                            AppIconView(appName: window.appName, size: 16)
                        }
                        .opacity(0.8)
                        .scaleEffect(unfocusedWindowPressed.contains(window.windowId) ? 0.94 : 1.0)
                        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: unfocusedWindowPressed.contains(window.windowId))
                        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
                            if pressing {
                                unfocusedWindowPressed.insert(window.windowId)
                            } else {
                                unfocusedWindowPressed.remove(window.windowId)
                            }
                        }) {}
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
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
        }
    }

    private func focusWindow(_ window: AerospaceWindow) {
        Task {
            await aerospaceService.focusWindow(window.windowId)
        }
    }
}
