import SwiftUI

/// Compute ordering from raw geometry before comparing the values the widget renders.
struct ProcessWidget: View {
    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var yabaiService: YabaiService

    var body: some View {
        let state = yabaiService.state
        let windows: [YabaiWindow] = {
            guard settings.settings.widgets.process.showCurrentSpaceOnly else { return state.windows }
            guard let space = state.focusedSpace else { return [] }
            return state.windows.filter {
                $0.space == space.index || ($0.isSticky && $0.id == state.focusedWindow?.id)
            }
        }()
        let ordered = WindowFilter.orderedByStackThenPosition(windows, stackIndex: \.stackIndex, x: \.frame.x)
        ProcessContent(windows: ordered.map(YabaiWindowPresentation.init),
                       layout: state.focusedSpace?.type, service: yabaiService)
            .equatable()
    }
}

private struct ProcessContent: View, Equatable {
    let windows: [YabaiWindowPresentation]
    let layout: YabaiSpace.SpaceType?
    let service: YabaiService
    @EnvironmentObject var settings: SettingsManager

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.windows == rhs.windows && lhs.layout == rhs.layout && lhs.service === rhs.service
    }

    @State private var focusedWindowPressed = false
    @State private var unfocusedWindowPressed: Set<Int> = []
    
    private var theme: ABarTheme {
        ThemeManager.currentTheme(for: settings.settings.theme)
    }
    
    var body: some View {
        let globalSettings = settings.settings.global
        // 显式捕获配置值，让窗口数据不变时列表也能响应设置更新。
        let processSettings = settings.settings.widgets.process
        let userFont: Font = globalSettings.fontName.isEmpty ? .system(size: CGFloat(globalSettings.fontSize)) : .custom(globalSettings.fontName, size: CGFloat(globalSettings.fontSize))
        let userFontSmall: Font = globalSettings.fontName.isEmpty ? .system(size: CGFloat(Double(globalSettings.fontSize) * 0.9)) : .custom(globalSettings.fontName, size: CGFloat(Double(globalSettings.fontSize) * 0.9))

        let orderedWindows = windows
        let focusedWin = windows.first { $0.hasFocus }

      HStack(spacing: globalSettings.barElementGap) {
        if processSettings.spaceLayoutDisplay != .off, let layout {
          stateBadge("Space \(layout.rawValue)", font: userFontSmall,
                     systemImage: processSettings.spaceLayoutDisplay == .icon ? layout.systemImage : nil)
            .help("Current space layout: \(layout.rawValue)")
            .accessibilityLabel("Current space layout: \(layout.rawValue)")
        }
        if orderedWindows.isEmpty {
            // No windows: show desktop
          HStack(spacing: globalSettings.barElementGap) {
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
          .padding(.vertical, 3)
        } else {
          ForEach(orderedWindows, id: \.id) { window in
            if window.id == focusedWin?.id {
                // Focused window state comes from the shared, event-driven yabai snapshot.
              HStack(spacing: globalSettings.barElementGap) {
                AppIconView(appName: window.app, size: 16)
                if !processSettings.displayOnlyIcon {
                  VStack(alignment: .leading, spacing: -3) {
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
                if processSettings.showLayoutMode {
                  stateBadge(window.layoutLabel, font: userFontSmall,
                             systemImage: processSettings.layoutModeUsesIcon ? window.layoutType.systemImage : nil)
                    .help("Focused window layout: \(window.layoutLabel)")
                    .accessibilityLabel("Focused window layout: \(window.layoutLabel)")
                }
                if window.isSticky {
                  stateBadge("sticky", font: userFontSmall)
                    .help("Focused window is visible on all spaces")
                    .accessibilityLabel("Focused window is sticky: visible on all spaces")
                }
                if let idx = window.stackIndex, idx != 0 {
                  stateBadge("\(idx)", font: userFontSmall)
                }
              }
              .padding(.horizontal, 4)
              .padding(.vertical, processSettings.hideWindowTitle || processSettings.displayOnlyIcon ? 2 : 0)
              .frame(maxHeight: .infinity)
              .background(
                RoundedRectangle(cornerRadius: globalSettings.barElementsCornerRadius)
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
              .scaleEffect(focusedWindowPressed && window.id == focusedWin?.id ? 0.94 : 1.0)
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
                      RoundedRectangle(cornerRadius: globalSettings.barElementsCornerRadius)
                        .fill(theme.minor.opacity(0.5))
                    )
                }
              }
              .padding(.horizontal, 4)
              .opacity(0.8)
              .scaleEffect(unfocusedWindowPressed.contains(window.id) ? 0.94 : 1.0)
              .animation(.spring(response: 0.25, dampingFraction: 0.7), value: unfocusedWindowPressed.contains(window.id))
              .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
                  if pressing {
                      unfocusedWindowPressed.insert(window.id)
                  } else {
                      unfocusedWindowPressed.remove(window.id)
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
      }
    }
    private func stateBadge(_ label: String, font: Font, systemImage: String? = nil) -> some View {
      let global = settings.settings.global
      return Group {
        if let systemImage {
          Image(systemName: systemImage)
        } else {
          Text(label)
        }
      }
        .font(font.weight(.medium))
        .foregroundColor(theme.foreground.opacity(0.9))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
          RoundedRectangle(cornerRadius: global.barElementsCornerRadius)
            .fill(theme.minor.opacity((global.barElementsBackgroundOpacity / 100) * 0.5))
        )
    }

    private func focusWindow(_ window: YabaiWindowPresentation) {
        Task {
            await service.focusWindow(window.id)
        }
    }
}

