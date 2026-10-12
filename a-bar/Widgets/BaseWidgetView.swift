import SwiftUI

/// Base widget view providing consistent styling and interaction
struct BaseWidgetView<Content: View>: View {
    let backgroundColor: Color?
    let width: CGFloat?
    let noPadding: Bool
    let onClick: (() -> Void)?
    let onRightClick: (() -> Void)?
    @ViewBuilder let content: () -> Content

    @EnvironmentObject var settings: SettingsManager

    init(
        backgroundColor: Color? = nil,
        width: CGFloat? = nil,
        noPadding: Bool = false,
        onClick: (() -> Void)? = nil,
        onRightClick: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.backgroundColor = backgroundColor
        self.width = width
        self.noPadding = noPadding
        self.onClick = onClick
        self.onRightClick = onRightClick
        self.content = content
    }

    private var theme: ABarTheme {
        ThemeManager.currentTheme(for: settings.settings.theme)
    }

    private var globalSettings: GlobalSettings {
        settings.settings.global
    }

    var body: some View {
        content()
            .font(
                globalSettings.fontName.isEmpty
                    ? .system(size: CGFloat(globalSettings.fontSize))
                    : .custom(globalSettings.fontName, size: CGFloat(globalSettings.fontSize))
            )
            .lineLimit(1)
            .truncationMode(.tail)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, noPadding ? 0 : 6)
            .padding(.vertical, noPadding ? 0 : 4)
            .frame(maxHeight: .infinity)
            .frame(width: width)
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
            .background(backgroundView)
            .contentShape(Rectangle())
            .onTapGesture {
                onClick?()
            }
            .contextMenu {
                if onRightClick != nil {
                    Button("Refresh") {
                        onRightClick?()
                    }
                }
            }
            .onHover { hovering in
                if onClick != nil {
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            }
    }

    @ViewBuilder
    private var backgroundView: some View {
        RoundedRectangle(cornerRadius: globalSettings.barElementsCornerRadius)
            .fill((backgroundColor ?? theme.minor).opacity(globalSettings.barElementsBackgroundOpacity / 100))
    }
}
