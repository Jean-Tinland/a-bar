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
            WidgetContainer(widget: widget, displayIndex: displayIndex)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        // Center section
        HStack(spacing: globalSettings.barElementGap) {
          ForEach(centerWidgets) { widget in
            WidgetContainer(widget: widget, displayIndex: displayIndex)
          }
        }

        // Right section
        HStack(spacing: globalSettings.barElementGap) {
          ForEach(rightWidgets) { widget in
            WidgetContainer(widget: widget, displayIndex: displayIndex)
          }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
      }
      .padding(.horizontal, 8)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(barBackground)
      .overlay(
        Group {
          if borderEnabled {
            // Border at top for bottom bar, at bottom for top bar
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
  private var barBackground: some View {
    Rectangle()
      .fill(theme.background.opacity(0.95))
  }
}

/// Container view that renders the appropriate widget based on configuration
struct WidgetContainer: View {
  let widget: WidgetInstance
  let displayIndex: Int

  @EnvironmentObject var settings: SettingsManager
  @EnvironmentObject var yabaiService: YabaiService
  @EnvironmentObject var systemInfoService: SystemInfoService

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

struct WidgetIcon: View {
  let systemName: String
  var color: Color? = nil

  @EnvironmentObject var settings: SettingsManager

  private var theme: ABarTheme {
    ThemeManager.currentTheme(for: settings.settings.theme)
  }

  var body: some View {
    Image(systemName: systemName)
      .font(.system(size: 10))
      .foregroundColor(color ?? theme.foreground)
  }
}

struct WidgetSeparator: View {
  @EnvironmentObject var settings: SettingsManager

  private var theme: ABarTheme {
    ThemeManager.currentTheme(for: settings.settings.theme)
  }

  var body: some View {
    Rectangle()
      .fill(theme.minor.opacity(0.3))
      .frame(width: 1, height: 12)
      .padding(.horizontal, 4)
  }
}
