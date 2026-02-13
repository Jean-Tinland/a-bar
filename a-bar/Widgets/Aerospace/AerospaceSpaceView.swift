import SwiftUI

/// View for a single AeroSpace workspace
struct AerospaceSpaceView: View {
    let workspace: AerospaceWorkspace
    let displayIndex: Int

    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var aerospaceService: AerospaceService

    @State private var isHovered = false
    @State private var isPressed = false

    private var spacesSettings: SpacesWidgetSettings {
        settings.settings.widgets.spaces
    }

    private var theme: ABarTheme {
        ThemeManager.currentTheme(for: settings.settings.theme)
    }

    private var globalSettings: GlobalSettings {
        settings.settings.global
    }

    private func settingsFont(scaledBy factor: Double = 1.0, weight: Font.Weight? = nil, design: Font.Design? = nil) -> Font {
        let size = CGFloat(Double(globalSettings.fontSize) * factor)
        if globalSettings.fontName.isEmpty {
            if let weight = weight {
                if let design = design {
                    return .system(size: size, weight: weight, design: design)
                }
                return .system(size: size, weight: weight)
            }
            return .system(size: size)
        }
        return .custom(globalSettings.fontName, size: size)
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
                .font(settingsFont(scaledBy: 1.0, weight: .medium))
                .foregroundColor(labelColor)
                .lineLimit(1)
                .truncationMode(.tail)

            // Opened apps icons
            AerospaceOpenedAppsView(workspace: workspace)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(spaceBackground)
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
            RoundedRectangle(cornerRadius: 4)
                .fill(theme.mainAlt.opacity(0.9))
        } else if isVisible {
            RoundedRectangle(cornerRadius: 4)
                .fill(theme.mainAlt)
        } else if isHovered {
            RoundedRectangle(cornerRadius: 4)
                .fill(theme.minor.opacity(1))
        } else {
            theme.minor
        }
    }

    private func goToWorkspace() {
        guard !isFocused else { return }

        Task {
            await aerospaceService.goToWorkspace(workspace.workspace)
        }
    }
}
