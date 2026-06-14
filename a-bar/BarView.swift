import SwiftUI

/// Main bar view containing all widgets arranged in sections
struct BarView: View {
  let displayIndex: Int
  let screen: NSScreen
  let position: BarPosition

  @EnvironmentObject var settings: SettingsManager
  @EnvironmentObject var yabaiService: YabaiService
  @EnvironmentObject var layoutManager: LayoutManager

  private var theme: ABarTheme {
    ThemeManager.currentTheme(for: settings.settings.theme)
  }

  private var globalSettings: GlobalSettings {
    settings.settings.global
  }

  /// Get the bar layout for this specific bar
  private var barLayout: SingleBarLayout? {
    layoutManager.barLayout(forDisplay: displayIndex, position: position)
  }

  var body: some View {
    GeometryReader { geometry in
      let borderEnabled = globalSettings.showBorder
      HStack(spacing: 0) {
        // Left section
        HStack(spacing: globalSettings.barElementGap) {
          ForEach(leftWidgets) { widget in
            WidgetContainer(widget: widget, displayIndex: displayIndex, position: position)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        // Center section
        HStack(spacing: globalSettings.barElementGap) {
          ForEach(centerWidgets) { widget in
            WidgetContainer(widget: widget, displayIndex: displayIndex, position: position)
          }
        }

        // Right section
        HStack(spacing: globalSettings.barElementGap) {
          ForEach(rightWidgets) { widget in
            WidgetContainer(widget: widget, displayIndex: displayIndex, position: position)
          }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
      }
      .padding(.horizontal, globalSettings.barHorizontalPadding)
      .padding(.vertical, globalSettings.barVerticalPadding)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
       .background(barBackground)
      .overlay(
        Group {
          if borderEnabled {
            if (globalSettings.barDistanceFromEdges > 0) {
              // Display a border that go around all the bar
              RoundedRectangle(cornerRadius: globalSettings.barCornerRadius)
                .stroke(theme.foreground.opacity(0.1), lineWidth: 1)
            } else {
                // Border at top for bottom bar, at bottom for top bar
              if position == .top {
                VStack(spacing: 0) {
                  Spacer(minLength: 0)
                  Rectangle()
                    .fill(theme.foreground.opacity(0.1))
                    .frame(height: 1)
                }
              } else {
                VStack(spacing: 0) {
                  Rectangle()
                    .fill(theme.foreground.opacity(0.1))
                    .frame(height: 1)
                  Spacer(minLength: 0)
                }
              }
            }
          }
        }, alignment: position == .top ? .bottom : .top
      )
    }
  }

  private var leftWidgets: [WidgetInstance] {
    barLayout?.widgets(for: .left) ?? []
  }

  private var centerWidgets: [WidgetInstance] {
    barLayout?.widgets(for: .center) ?? []
  }

  private var rightWidgets: [WidgetInstance] {
    barLayout?.widgets(for: .right) ?? []
  }

  @ViewBuilder
  var barBackground: some View {
    let cornerRadius = globalSettings.barCornerRadius

    if globalSettings.barBackgroundBlur {
      ZStack {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .fill(.ultraThinMaterial)

        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .fill(theme.background.opacity(globalSettings.barOpacity / 100))
      }
    } else {
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .fill(theme.background.opacity(globalSettings.barOpacity / 100))
    }
  }

}

/// Container view that renders the appropriate widget based on configuration
struct WidgetContainer: View {
  let widget: WidgetInstance
  let displayIndex: Int
  let position: BarPosition

  @EnvironmentObject var settings: SettingsManager
  @EnvironmentObject var yabaiService: YabaiService
  @EnvironmentObject var aerospaceService: AerospaceService
  @EnvironmentObject var systemInfoService: SystemInfoService

  var body: some View {
    Group {
      switch widget.identifier {
      case .spaces:
        SpacesWidget(displayIndex: displayIndex)
      case .process:
        ProcessWidget()
      case .aerospaceSpaces:
        AerospaceSpacesWidget(displayIndex: displayIndex)
      case .aerospaceProcess:
        AerospaceProcessWidget(displayIndex: displayIndex)
      case .battery:
        BatteryWidget()
      case .weather:
        WeatherWidget()
      case .time:
        TimeWidget()
      case .date:
        DateWidget()
      case .wifi:
        WifiWidget()
      case .sound:
        SoundWidget(position: position)
      case .mic:
        MicWidget(position: position)
      case .keyboard:
        KeyboardWidget()
      case .github:
        GitHubWidget()
      case .hackerNews:
        HackerNewsWidget(position: position)
      case .cpu:
        CPUWidget()
      case .memory:
        MemoryWidget()
      case .gpu:
        GPUWidget()
      case .netstats:
        NetstatsWidget()
      case .diskActivity:
        DiskActivityWidget()
      case .storage:
        StorageWidget()
      case .userWidget:
        if let index = widget.userWidgetIndex,
          index < settings.settings.userWidgets.count
        {
          UserWidget(config: settings.settings.userWidgets[index], position: position)
        } else {
          EmptyView()
        }
      }
    }
  }
}
