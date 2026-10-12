import Foundation

/// Identifies a bar window by the display it belongs to and the edge it sits against.
struct BarWindowKey: Hashable {
  let displayIndex: Int
  let position: BarPosition
}

/// Which bars exist, for the screens attached right now.
///
/// Displays come and go - a laptop lid closes, a dock is unplugged - while the layout the user
/// configured stays as it was. So the layout is a wish and the screen count is the constraint:
/// a display the user configured but is no longer attached gets no bar, and a display that is
/// attached but never configured gets none either.
enum BarWindowPlan {

  /// Only structural inputs require new windows; SwiftUI updates appearance and data in place.
  struct Configuration: Equatable {
    let screenCount: Int
    let layout: MultiDisplayLayout
    let barEnabled: Bool
    let height: CGFloat
    let inset: CGFloat

    init(screenCount: Int, layout: MultiDisplayLayout, global: GlobalSettings) {
      self.screenCount = screenCount
      self.layout = layout
      self.barEnabled = global.barEnabled
      self.height = global.barHeight
      self.inset = global.barDistanceFromEdges
    }
  }

  /// Compare sampling inputs independently so cosmetic changes do not restart services.
  struct ServiceConfiguration: Equatable {
    struct Bluetooth: Equatable {
      let refreshInterval: TimeInterval
      let batteryRefreshInterval: TimeInterval
      let showBatteryInBar: Bool
    }

    struct Wifi: Equatable {
      let refreshInterval: TimeInterval
      let scanInterval: TimeInterval
      let networkDevice: String
    }

    let systemWidgets: Set<WidgetIdentifier>
    let systemIntervals: [WidgetIdentifier: TimeInterval]
    let bluetooth: Bluetooth?
    let wifi: Wifi?

    init(widgets: Set<WidgetIdentifier>, settings: WidgetSettings) {
      systemWidgets = Set(widgets.filter { !WidgetRefreshSchedule.readings(for: $0).isEmpty })
      systemIntervals = Dictionary(uniqueKeysWithValues:
        WidgetRefreshSchedule.timers(for: widgets, in: settings).map { ($0.widget, $0.interval) })
      bluetooth = widgets.contains(.bluetooth) ? Bluetooth(
        refreshInterval: settings.bluetooth.refreshInterval,
        batteryRefreshInterval: settings.bluetooth.batteryRefreshInterval,
        showBatteryInBar: settings.bluetooth.showBatteryInBar) : nil
      wifi = widgets.contains(.wifi) ? Wifi(
        refreshInterval: settings.wifi.refreshInterval,
        scanInterval: settings.wifi.scanInterval,
        networkDevice: settings.wifi.networkDevice.trimmingCharacters(in: .whitespaces)) : nil
    }
  }

  /// The bars to open, in creation order: each attached display in index order, top before
  /// bottom.
  static func windows(
    screenCount: Int, layout: MultiDisplayLayout, barEnabled: Bool
  ) -> [BarWindowKey] {
    guard barEnabled else { return [] }

    return (0..<max(0, screenCount)).flatMap { index -> [BarWindowKey] in
      guard let display = layout.configuration(forDisplay: index) else { return [] }
      return [
        display.topBar.map { _ in BarWindowKey(displayIndex: index, position: .top) },
        display.bottomBar.map { _ in BarWindowKey(displayIndex: index, position: .bottom) },
      ].compactMap { $0 }
    }
  }

  /// The widgets actually on screen, which is what decides whether a sampler runs at all.
  /// Hidden widgets must not poll or initialize blocking hardware APIs, and a bar switched off
  /// hides all of them however the layout is configured.
  static func visibleWidgets(
    screenCount: Int, layout: MultiDisplayLayout, barEnabled: Bool
  ) -> Set<WidgetIdentifier> {
    barEnabled ? layout.enabledWidgets(displayCount: screenCount) : []
  }
}
