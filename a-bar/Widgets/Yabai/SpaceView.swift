import SwiftUI

/// View for a single yabai space
struct SpaceView: View {
    let space: YabaiSpace
    let displayIndex: Int
    let currentSpaceIndex: Int
    
    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var yabaiService: YabaiService
    
    @State private var isHovered = false
    @State private var isEditing = false
    @State private var editedLabel: String = ""
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
        space.hasFocus
    }
    
    private var isVisible: Bool {
        space.isVisible
    }
    
  var body: some View {
      HStack(spacing: 4) {
              // Space label
          if isEditing {
              TextField("", text: $editedLabel, onCommit: saveLabel)
                  .textFieldStyle(.plain)
                  .font(settingsFont(scaledBy: 1.0, weight: .medium))
                  .foregroundColor(theme.foreground)
                  .frame(width: CGFloat(max(1, editedLabel.count)) * 12)
                  .lineLimit(1)
                  .truncationMode(.tail)
          } else {
              Text(space.displayLabel)
                  .font(settingsFont(scaledBy: 1.0, weight: .medium))
                  .foregroundColor(labelColor)
                  .lineLimit(1)
                  .truncationMode(.tail)
          }
              // Opened apps icons
          OpenedAppsView(space: space, displayIndex: displayIndex)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .fixedSize(horizontal: true, vertical: false)
      .frame(maxHeight: .infinity)
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
      .clipShape(RoundedRectangle(cornerRadius: globalSettings.barElementsCornerRadius))
      .scaleEffect(isPressed ? 0.94 : 1.0)
      .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
      .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
          isPressed = pressing
      }) {}
      .onTapGesture {
          goToSpace()
      }
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
      .contextMenu {
          spaceContextMenu
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
            RoundedRectangle(cornerRadius: globalSettings.barElementsCornerRadius)
            .fill(theme.mainAlt.opacity((globalSettings.barElementsBackgroundOpacity / 100) * 0.45))
        } else if isHovered {
            RoundedRectangle(cornerRadius: globalSettings.barElementsCornerRadius)
              .fill(theme.mainAlt.opacity((globalSettings.barElementsBackgroundOpacity / 100) * 0.3))
        } else {
            theme.minor.opacity(globalSettings.barElementsBackgroundOpacity / 100)
        }
    }
    
    @ViewBuilder
    private var spaceContextMenu: some View {
        Button("Focus") {
            goToSpace()
        }
        
        Divider()
        
        Button("Rename...") {
            startEditing()
        }
        
        Divider()
        
        Button("Move Left") {
            moveSpace(.left)
        }
        .disabled(space.index <= 1)
        
        Button("Move Right") {
            moveSpace(.right)
        }
        
        Divider()
        
        Button("Delete") {
            deleteSpace()
        }
    }
    
    private func goToSpace() {
        guard !isFocused else { return }
        
        Task {
            await yabaiService.goToSpace(space.index)
        }
    }
    
    private func startEditing() {
        editedLabel = space.displayLabel
        isEditing = true
    }
    
    private func saveLabel() {
        isEditing = false
        guard !editedLabel.isEmpty, editedLabel != space.displayLabel else { return }
        
        Task {
            await yabaiService.renameSpace(space.index, label: editedLabel)
        }
    }
    
    private func moveSpace(_ direction: YabaiService.SwapDirection) {
        Task {
            await yabaiService.swapSpace(space.index, direction: direction)
        }
    }
    
    private func deleteSpace() {
        Task {
            await yabaiService.removeSpace(space.index, onDisplay: space.display)
        }
    }
}
