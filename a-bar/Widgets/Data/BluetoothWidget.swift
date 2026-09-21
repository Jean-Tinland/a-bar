import AppKit
import SwiftUI

/// Bluetooth status widget with a paired-devices popover
struct BluetoothWidget: View {
  let position: BarPosition

  @EnvironmentObject var settings: SettingsManager
  @EnvironmentObject var bluetooth: BluetoothService

  @StateObject private var popoverManager = WidgetPopoverManager(minWidth: 260, maxHeight: 420)

  private var bluetoothSettings: BluetoothWidgetSettings { settings.settings.widgets.bluetooth }
  private var globalSettings: GlobalSettings { settings.settings.global }
  private var theme: ABarTheme { ThemeManager.currentTheme(for: settings.settings.theme) }
  private var info: BluetoothInfo { bluetooth.info }

  var body: some View {
    let bgColor = bluetoothSettings.backgroundColor.color(from: theme)
    let fgColor =
      globalSettings.noColorInDataWidgets
      ? theme.foreground
      : bgColor.contrastingForeground(
        from: theme, opacity: globalSettings.barElementsBackgroundOpacity,
        barBackground: theme.background)

    // Hide if the radio is off and the setting is enabled
    if bluetoothSettings.hideWhenDisabled && !info.isPoweredOn {
      EmptyView()
    } else {
      BaseWidgetView(
        backgroundColor: globalSettings.noColorInDataWidgets ? theme.minor : bgColor,
        onClick: togglePopover,
        onRightClick: { bluetooth.openBluetoothSettings() }
      ) {
        HStack(spacing: 4) {
          if bluetoothSettings.showIcon {
            Image(
              systemName: info.isPoweredOn
                ? "antenna.radiowaves.left.and.right"
                : "antenna.radiowaves.left.and.right.slash"
            )
            .font(.system(size: 11))
            .foregroundColor(info.isPoweredOn ? fgColor : theme.red)
          }
          if let label = barLabel {
            Text(label)
              .foregroundColor(info.isPoweredOn ? fgColor : theme.red)
          }
        }
      }
      .background(
        WidgetPopoverAnchor(
          onMake: { view in
            popoverManager.attach(anchorView: view, position: position)
            popoverManager.setContent {
              BluetoothPopoverContent()
                .environmentObject(settings)
                .environmentObject(bluetooth)
            }
          }
        )
      )
      .onChange(of: popoverManager.isOpen) { isOpen in
        // Drive the service from the panel's real state, not from the click:
        // the popover can also be closed by an outside click or by another
        // popover opening, and the battery poll must stop in those cases too.
        bluetooth.setPopoverOpen(isOpen)
      }
      .onChange(of: info) { _ in
        // The popover lists devices, so its height follows the radio state and
        // the pairing list. Re-fit the panel or it keeps the size it had when
        // it was opened — toggling the radio off and back on would otherwise
        // squeeze the list into a scroller.
        popoverManager.refreshSize()
      }
    }
  }

  /// Bar text next to the icon. Nil renders the icon alone.
  private var barLabel: String? {
    guard info.hasController else { return "n/a" }
    // The slashed red icon already says the radio is off, so the label would
    // only repeat it — and it reads as a blank gap next to the icon.
    guard info.isPoweredOn else { return bluetoothSettings.showIcon ? nil : "Off" }

    let connected = info.connectedDevices
    if connected.isEmpty { return nil }

    if connected.count > 1 {
      return bluetoothSettings.showConnectedCount ? "\(connected.count)" : nil
    }

    guard bluetoothSettings.showConnectedDeviceName, let device = connected.first else {
      return bluetoothSettings.showConnectedCount ? "\(connected.count)" : nil
    }

    var label = device.name.truncated(to: bluetoothSettings.maxDeviceNameLength)
    if bluetoothSettings.showBatteryInBar, let level = device.battery?.lowest {
      label += " \(level)%"
    }
    return label
  }

  private func togglePopover() {
    if popoverManager.isOpen {
      popoverManager.close()
    } else {
      // Activate abar so the popover can render even if not focused
      NSApp.activate(ignoringOtherApps: true)
      popoverManager.open()
    }
  }
}

/// Popover listing paired devices, grouped connected-first.
///
/// Reads settings and state from the environment rather than capturing values,
/// because the content provider closure is evaluated against the `View` struct
/// captured when the anchor was made — captured values go stale.
private struct BluetoothPopoverContent: View {
  @EnvironmentObject var settings: SettingsManager
  @EnvironmentObject var bluetooth: BluetoothService

  private var globalSettings: GlobalSettings { settings.settings.global }
  private var theme: ABarTheme { ThemeManager.currentTheme(for: settings.settings.theme) }
  private var info: BluetoothInfo { bluetooth.info }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      header

      Divider()

      if !info.hasController {
        emptyState("No Bluetooth hardware")
      } else if !info.isPoweredOn {
        emptyState("Bluetooth is off")
      } else if info.devices.isEmpty {
        emptyState("No paired devices")
      } else {
        deviceList
      }

      Divider()

      Button("Bluetooth Settings…") {
        bluetooth.openBluetoothSettings()
      }
      .buttonStyle(.plain)
      .font(globalSettings.settingsFont(scaledBy: 0.9))
      .foregroundColor(theme.accent)
    }
    .padding(10)
    .frame(width: 260)
    .background(
      RoundedRectangle(cornerRadius: 8)
        .fill(theme.background)
        .overlay(
          RoundedRectangle(cornerRadius: 8)
            .stroke(theme.foreground.opacity(0.1), lineWidth: 1)
        )
    )
  }

  private var header: some View {
    HStack {
      Text("Bluetooth")
        .font(globalSettings.settingsFont(weight: .semibold))
        .foregroundColor(theme.foreground)
      Spacer()
      Button(info.isPoweredOn ? "On" : "Off") {
        bluetooth.togglePower()
      }
      .buttonStyle(.bordered)
      .font(globalSettings.settingsFont(scaledBy: 0.85))
      .foregroundColor(info.isPoweredOn ? theme.green : theme.red)
      .disabled(!info.canTogglePower)
      .help(
        info.canTogglePower
          ? "Toggle Bluetooth"
          : "Toggling Bluetooth is unavailable on this system")
    }
  }

  private var deviceList: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 2) {
        let connected = info.connectedDevices
        let others = info.devices.filter { !$0.isConnected }

        if !connected.isEmpty {
          sectionCaption("Connected")
          ForEach(connected) { device in
            DeviceRow(device: device)
          }
        }
        if !others.isEmpty {
          sectionCaption("Not connected")
          ForEach(others) { device in
            DeviceRow(device: device)
          }
        }
      }
    }
    .frame(maxHeight: 280)
  }

  private func sectionCaption(_ text: String) -> some View {
    Text(text)
      .font(globalSettings.settingsFont(scaledBy: 0.8))
      .foregroundColor(theme.foreground.opacity(0.6))
      .padding(.top, 4)
      .padding(.bottom, 2)
  }

  private func emptyState(_ text: String) -> some View {
    Text(text)
      .font(globalSettings.settingsFont(scaledBy: 0.9))
      .foregroundColor(theme.foreground.opacity(0.7))
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.vertical, 6)
  }
}

/// One paired device: icon, name, battery, connect/disconnect on click.
private struct DeviceRow: View {
  let device: BluetoothPairedDevice

  @EnvironmentObject var settings: SettingsManager
  @EnvironmentObject var bluetooth: BluetoothService

  @State private var isHovering = false

  private var globalSettings: GlobalSettings { settings.settings.global }
  private var theme: ABarTheme { ThemeManager.currentTheme(for: settings.settings.theme) }
  private var isPending: Bool { bluetooth.pendingAddresses.contains(device.id) }

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: device.kind.symbolName)
        .font(.system(size: 11))
        .frame(width: 16)
        .foregroundColor(device.isConnected ? theme.accent : theme.foreground.opacity(0.65))

      Text(device.name)
        .font(globalSettings.settingsFont(scaledBy: 0.9))
        .foregroundColor(device.isConnected ? theme.foreground : theme.foreground.opacity(0.75))
        .lineLimit(1)
        .truncationMode(.tail)

      Spacer(minLength: 4)

      if isPending {
        ProgressView()
          .scaleEffect(0.5)
          .frame(width: 16, height: 16)
      } else if let battery = device.battery {
        batteryView(battery)
      }
    }
    .padding(.horizontal, 6)
    .padding(.vertical, 4)
    .contentShape(Rectangle())
    .background(
      RoundedRectangle(cornerRadius: 4)
        .fill(isHovering ? theme.foreground.opacity(0.1) : Color.clear)
    )
    .onTapGesture {
      bluetooth.toggleConnection(for: device)
    }
    .onHover { hovering in
      isHovering = hovering
      if hovering {
        NSCursor.pointingHand.push()
      } else {
        NSCursor.pop()
      }
    }
  }

  @ViewBuilder
  private func batteryView(_ battery: BluetoothBatteryLevels) -> some View {
    HStack(spacing: 4) {
      if let main = battery.main, battery.left == nil, battery.right == nil {
        batteryLabel(nil, main)
      } else {
        if let left = battery.left { batteryLabel("L", left) }
        if let right = battery.right { batteryLabel("R", right) }
        if let caseLevel = battery.caseLevel { batteryLabel("C", caseLevel) }
      }
    }
  }

  private func batteryLabel(_ prefix: String?, _ level: Int) -> some View {
    Text(prefix.map { "\($0) \(level)%" } ?? "\(level)%")
      .font(globalSettings.settingsFont(scaledBy: 0.8))
      .foregroundColor(level < 20 ? theme.red : theme.foreground.opacity(0.7))
  }
}
