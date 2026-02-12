import SwiftUI

/// Main bar view containing all widgets arranged in sections
struct BarView: View {
  let displayIndex: Int
  let screen: NSScreen
  let position: BarPosition

  @EnvironmentObject var settings: SettingsManager
  @EnvironmentObject var yabaiService: YabaiService
  @EnvironmentObject var layoutManager: LayoutManager

  // We access the current theme and global settings to apply consistent styling and behavior across the bar and its widgets
  private var theme: ABarTheme {
    ThemeManager.currentTheme(for: settings.settings.theme)
  }

  // Global settings are accessed to determine things like whether to show borders, spacing between widgets, and other user preferences that affect the overall appearance of the bar
  private var globalSettings: GlobalSettings {
    settings.settings.global
  }

  /// Get the bar layout for this specific bar
  private var barLayout: SingleBarLayout? {
    layoutManager.barLayout(forDisplay: displayIndex, position: position)
  }

  // The body of the view constructs the layout of the bar using an HStack to arrange the left, center, and right sections. Each section contains its respective widgets, which are rendered using the WidgetContainer view. The bar's background and optional border are also applied here based on user settings.
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
      // A minimal padding is necessary on the built-in screen as it has rounded corners
      // Without it, the content might be clipped or appear too close to the edges
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

  // The body of the WidgetContainer uses a switch statement to determine which specific widget view to render based on the widget's identifier. Each case corresponds to a different type of widget
  // If the widget type is not recognized or if there's an issue with user widgets, it falls back to rendering an EmptyView
  var body: some View {
    Group {
      switch widget.identifier {
      case .spaces:
        SpacesWidget(displayIndex: displayIndex)
      case .process:
        ProcessWidget(displayIndex: displayIndex)
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
          UserWidget(config: settings.settings.userWidgets[index])
        } else {
          EmptyView()
        }
      }
    }
  }
}
