import SwiftUI

/// Orientation for widget layout
enum WidgetOrientation {
  case horizontal
  case vertical
}

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

  /// Whether this bar is vertical (left or right edge)
  private var isVertical: Bool {
    position.isVertical
  }

  /// Widget orientation based on bar position
  private var orientation: WidgetOrientation {
    isVertical ? .vertical : .horizontal
  }

  // The body of the view constructs the layout of the bar using an HStack to arrange the left, center, and right sections. Each section contains its respective widgets, which are rendered using the WidgetContainer view. The bar's background and optional border are also applied here based on user settings.
  var body: some View {
    GeometryReader { geometry in
      let borderEnabled = globalSettings.showBorder

      if isVertical {
        verticalBarContent
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(barBackground)
          .overlay(verticalBorderOverlay(enabled: borderEnabled))
      } else {
        horizontalBarContent
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(barBackground)
          .overlay(horizontalBorderOverlay(enabled: borderEnabled))
      }
    }
  }

  // MARK: - Horizontal Bar Layout (Top/Bottom)

  @ViewBuilder
  private var horizontalBarContent: some View {
    HStack(spacing: 0) {
      // Left section
      HStack(spacing: globalSettings.barElementGap) {
        ForEach(leftWidgets) { widget in
          WidgetContainer(widget: widget, displayIndex: displayIndex, orientation: orientation)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      // Center section
      HStack(spacing: globalSettings.barElementGap) {
        ForEach(centerWidgets) { widget in
          WidgetContainer(widget: widget, displayIndex: displayIndex, orientation: orientation)
        }
      }

      // Right section
      HStack(spacing: globalSettings.barElementGap) {
        ForEach(rightWidgets) { widget in
          WidgetContainer(widget: widget, displayIndex: displayIndex, orientation: orientation)
        }
      }
      .frame(maxWidth: .infinity, alignment: .trailing)
    }
    .padding(.horizontal, 8)
  }

  // MARK: - Vertical Bar Layout (Left/Right)

  @ViewBuilder
  private var verticalBarContent: some View {
    VStack(spacing: 0) {
      // Top section (mapped from left)
      VStack(spacing: globalSettings.barElementGap) {
        ForEach(leftWidgets) { widget in
          WidgetContainer(widget: widget, displayIndex: displayIndex, orientation: orientation)
        }
      }
      .frame(maxHeight: .infinity, alignment: .top)

      // Middle section (mapped from center)
      VStack(spacing: globalSettings.barElementGap) {
        ForEach(centerWidgets) { widget in
          WidgetContainer(widget: widget, displayIndex: displayIndex, orientation: orientation)
        }
      }

      // Bottom section (mapped from right)
      VStack(spacing: globalSettings.barElementGap) {
        ForEach(rightWidgets) { widget in
          WidgetContainer(widget: widget, displayIndex: displayIndex, orientation: orientation)
        }
      }
      .frame(maxHeight: .infinity, alignment: .bottom)
    }
    .padding(.vertical, 8)
  }

  // MARK: - Border Overlays

  @ViewBuilder
  private func horizontalBorderOverlay(enabled: Bool) -> some View {
    if enabled {
      // Border at bottom for top bar, at top for bottom bar
      if position == .top {
        VStack(spacing: 0) {
          Spacer(minLength: 0)
          Rectangle()
            .fill(theme.minor)
            .frame(height: 1)
        }
      } else {
        VStack(spacing: 0) {
          Rectangle()
            .fill(theme.minor)
            .frame(height: 1)
          Spacer(minLength: 0)
        }
      }
    }
  }

  @ViewBuilder
  private func verticalBorderOverlay(enabled: Bool) -> some View {
    if enabled {
      // Border on right edge for left bar, on left edge for right bar
      if position == .left {
        HStack(spacing: 0) {
          Spacer(minLength: 0)
          Rectangle()
            .fill(theme.minor)
            .frame(width: 1)
        }
      } else {
        HStack(spacing: 0) {
          Rectangle()
            .fill(theme.minor)
            .frame(width: 1)
          Spacer(minLength: 0)
        }
      }
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
  private var barBackground: some View {
    // The background of the bar is a slightly transparent rectangle filled with the theme's background color.
    // Opacity is hardcoded for now, but can be made user-configurable if needed. This allows the bar to blend with the desktop while still providing enough contrast for the widgets to be visible.
    Rectangle()
      .fill(theme.background.opacity(0.95))
  }
}

/// Container view that renders the appropriate widget based on configuration
struct WidgetContainer: View {
  let widget: WidgetInstance
  let displayIndex: Int
  var orientation: WidgetOrientation = .horizontal

  @EnvironmentObject var settings: SettingsManager
  @EnvironmentObject var yabaiService: YabaiService
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
        SoundWidget()
      case .mic:
        MicWidget()
      case .keyboard:
        KeyboardWidget()
      case .github:
        GitHubWidget()
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
    .environment(\.widgetOrientation, orientation)
  }
}

// MARK: - Widget Orientation Environment Key

private struct WidgetOrientationKey: EnvironmentKey {
  static let defaultValue: WidgetOrientation = .horizontal
}

extension EnvironmentValues {
  var widgetOrientation: WidgetOrientation {
    get { self[WidgetOrientationKey.self] }
    set { self[WidgetOrientationKey.self] = newValue }
  }
}
