import SwiftUI

/// View for a single AeroSpace workspace
struct AerospaceSpaceView: View {
    let workspace: AerospaceWorkspace

    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var aerospaceService: AerospaceService

    @State private var isHovered = false
    @State private var isPressed = false

    private var theme: ABarTheme {
        ThemeManager.currentTheme(for: settings.settings.theme)
    }

    private var globalSettings: GlobalSettings {
        settings.settings.global
    }

    private var isFocused: Bool {
        workspace.isFocused
    }

    private var isVisible: Bool {
        workspace.isVisible
    }

    var body: some View {
        HStack(spacing: 4) {
            // Workspace label
            Text(workspace.displayLabel)
                .font(globalSettings.settingsFont(scaledBy: 1.0, weight: .medium))
                .foregroundColor(labelColor)
                .lineLimit(1)
                .truncationMode(.tail)

            // Opened apps icons
            AerospaceOpenedAppsView(workspace: workspace)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(spaceBackground)
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
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .scaleEffect(isPressed ? 0.94 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            isPressed = pressing
        }) {}
        .onHover { hovering in
            withAnimation(.abarFast) {
                isHovered = hovering
            }
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .onTapGesture {
            goToWorkspace()
        }
    }

    private var labelColor: Color {
        if isFocused {
            return theme.foreground
        } else if isVisible {
            return theme.foreground.opacity(0.9)
        } else {
            return theme.foreground.opacity(0.6)
        }
    }

    @ViewBuilder
    private var spaceBackground: some View {
        if isFocused {
          RoundedRectangle(cornerRadius: globalSettings.barElementsCornerRadius)
            .fill(theme.mainAlt.opacity((globalSettings.barElementsBackgroundOpacity / 100) * 0.6))
        } else if isVisible {
            RoundedRectangle(cornerRadius: 4)
          RoundedRectangle(cornerRadius: globalSettings.barElementsCornerRadius)
            .fill(theme.mainAlt.opacity((globalSettings.barElementsBackgroundOpacity / 100) * 0.45))
        } else if isHovered {
            RoundedRectangle(cornerRadius: globalSettings.barElementsCornerRadius)
              .fill(theme.mainAlt.opacity((globalSettings.barElementsBackgroundOpacity / 100) * 0.3))
        } else {
            theme.minor.opacity(globalSettings.barElementsBackgroundOpacity / 100)
        }
    }

    private func goToWorkspace() {
        guard !isFocused else { return }

        Task {
            await aerospaceService.goToWorkspace(workspace.workspace)
        }
    }
}
