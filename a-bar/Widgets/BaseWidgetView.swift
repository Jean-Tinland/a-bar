import SwiftUI

/// Base widget view providing consistent styling and interaction
struct BaseWidgetView<Content: View>: View {
    let isHighlighted: Bool
    let highlightColor: Color
    let backgroundColor: Color?
    let width: CGFloat?
    let noPadding: Bool
    let onClick: (() -> Void)?
    let onRightClick: (() -> Void)?
    @ViewBuilder let content: () -> Content

    @EnvironmentObject var settings: SettingsManager
    @Environment(\.widgetOrientation) var orientation

    @State private var isHovered = false

    init(
        isHighlighted: Bool = false,
        highlightColor: Color = Color.clear,
        backgroundColor: Color? = nil,
        width: CGFloat? = nil,
        noPadding: Bool = false,
        onClick: (() -> Void)? = nil,
        onRightClick: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        let theme = ThemeManager.currentTheme(for: SettingsManager.shared.settings.theme)
        self.isHighlighted = isHighlighted
        self.highlightColor = highlightColor
        self.backgroundColor = backgroundColor ?? theme.minor
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

    private var isVertical: Bool {
        orientation == .vertical
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
            .multilineTextAlignment(isVertical ? .center : .leading)
            .fixedSize(horizontal: !isVertical, vertical: false)
            .padding(.horizontal, noPadding ? 0 : (isVertical ? 4 : 6))
            .padding(.vertical, noPadding ? 0 : 4)
            .frame(maxHeight: isVertical ? nil : .infinity)
            .frame(maxWidth: isVertical ? .infinity : nil)
            .frame(width: isVertical ? nil : width)
            .clipped()
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
                isHovered = hovering
                if onClick != nil {
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            }
            .padding(.vertical, isVertical ? 2 : 4)
            .padding(.horizontal, isVertical ? 2 : 0)
    }

    @ViewBuilder
    private var backgroundView: some View {
        if isHighlighted {
            RoundedRectangle(cornerRadius: 4)
                .fill(highlightColor)
        } else if let bg = backgroundColor {
            RoundedRectangle(cornerRadius: 4)
                .fill(bg)
        } else if isHovered && onClick != nil {
            RoundedRectangle(cornerRadius: 4)
                .fill(theme.highlight.opacity(0.3))
        } else {
            Color.clear
        }
    }
}
