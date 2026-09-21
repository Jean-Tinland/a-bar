import AppKit
import SwiftUI

/// Wi-Fi status widget with a nearby-networks popover
struct WifiWidget: View {
  let position: BarPosition

  @EnvironmentObject var settings: SettingsManager
  @EnvironmentObject var wifi: WifiService

  @StateObject private var popoverManager = WidgetPopoverManager(minWidth: 280, maxHeight: 420)

  private var wifiSettings: WifiWidgetSettings { settings.settings.widgets.wifi }
  private var globalSettings: GlobalSettings { settings.settings.global }
  private var theme: ABarTheme { ThemeManager.currentTheme(for: settings.settings.theme) }
  private var info: WifiInfo { wifi.info }

  var body: some View {
    let bgColor = wifiSettings.backgroundColor.color(from: theme)
    let fgColor =
      globalSettings.noColorInDataWidgets
      ? theme.foreground
      : bgColor.contrastingForeground(
        from: theme, opacity: globalSettings.barElementsBackgroundOpacity,
        barBackground: theme.background)

    // Hide if the radio is off and the setting is enabled
    if wifiSettings.hideWhenDisabled && !info.isPoweredOn {
      EmptyView()
    } else {
      BaseWidgetView(
        backgroundColor: globalSettings.noColorInDataWidgets ? theme.minor : bgColor,
        onClick: togglePopover,
        onRightClick: { wifi.openNetworkSettings() }
      ) {
        HStack(spacing: 4) {
          if wifiSettings.showIcon {
            Image(systemName: iconName)
              .font(.system(size: 11))
              .foregroundColor(info.isPoweredOn ? fgColor : theme.red)
          }

          if !wifiSettings.hideNetworkName, let label = barLabel {
            Text(label)
              .foregroundColor(info.isPoweredOn ? fgColor : theme.minor)
          }
        }
      }
      .background(
        WidgetPopoverAnchor(
          onMake: { view in
            popoverManager.attach(anchorView: view, position: position)
            popoverManager.setContent {
              WifiPopoverContent()
                .environmentObject(settings)
                .environmentObject(wifi)
            }
          }
        )
      )
      .onChange(of: popoverManager.isOpen) { isOpen in
        // Drive the service from the panel's real state, not from the click: the
        // popover can also be closed by an outside click or by another popover
        // opening, and the scanning must stop in those cases too.
        wifi.setPopoverOpen(isOpen)
      }
      .onChange(of: info) { _ in
        // The popover lists networks, so its height follows the radio state and the
        // scan results. Re-fit the panel or it keeps the size it had when it was
        // opened — the first scan landing would otherwise squeeze the list.
        popoverManager.refreshSize()
      }
    }
  }

  /// Three states the old widget collapsed into one: radio off, radio on but not
  /// associated, and associated.
  private var iconName: String {
    guard info.hasInterface, info.isPoweredOn else { return "wifi.slash" }
    return info.isConnected ? "wifi" : "wifi.exclamationmark"
  }

  /// Bar text next to the icon. Nil renders the icon alone.
  private var barLabel: String? {
    guard info.hasInterface else { return "n/a" }
    // The slashed red icon already says the radio is off, so the label would only
    // repeat it.
    guard info.isPoweredOn else { return wifiSettings.showIcon ? nil : "Off" }

    if let ssid = info.ssid {
      return ssid.truncated(to: wifiSettings.maxNetworkNameLength)
    }
    // Associated but unnamed means macOS redacted the name, not that we are offline.
    return info.isAssociated ? "Connected" : "Not connected"
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

/// Popover listing nearby networks, connected first.
///
/// Reads settings and state from the environment rather than capturing values, because
/// the content provider closure is evaluated against the `View` struct captured when the
/// anchor was made — captured values go stale.
private struct WifiPopoverContent: View {
  @EnvironmentObject var settings: SettingsManager
  @EnvironmentObject var wifi: WifiService

  /// SSID whose inline password field is expanded, if any.
  @State private var promptingSSID: String?

  private var globalSettings: GlobalSettings { settings.settings.global }
  private var theme: ABarTheme { ThemeManager.currentTheme(for: settings.settings.theme) }
  private var info: WifiInfo { wifi.info }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      header

      Divider()

      if !info.hasInterface {
        emptyState("No Wi-Fi hardware")
      } else if !info.isPoweredOn {
        emptyState("Wi-Fi is off")
      } else if !info.locationAuthorized {
        locationPrompt
      } else if info.networks.isEmpty {
        emptyState("Searching…")
      } else {
        networkList
      }

      if let error = wifi.lastError {
        Text(error)
          .font(globalSettings.settingsFont(scaledBy: 0.8))
          .foregroundColor(theme.red)
          .fixedSize(horizontal: false, vertical: true)
      }

      Divider()

      Button("Network Settings…") {
        wifi.openNetworkSettings()
      }
      .buttonStyle(.plain)
      .font(globalSettings.settingsFont(scaledBy: 0.9))
      .foregroundColor(theme.accent)
    }
    .padding(10)
    .frame(width: 280)
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
      Text("Wi-Fi")
        .font(globalSettings.settingsFont(weight: .semibold))
        .foregroundColor(theme.foreground)
      Spacer()
      Button(info.isPoweredOn ? "On" : "Off") {
        wifi.togglePower()
      }
      .buttonStyle(.bordered)
      .font(globalSettings.settingsFont(scaledBy: 0.85))
      .foregroundColor(info.isPoweredOn ? theme.green : theme.red)
      .disabled(!info.hasInterface)
      .help("Toggle Wi-Fi")
    }
  }

  /// Without the Location Services grant macOS redacts every network name, so there is
  /// nothing to list. Say why rather than showing an empty list.
  private var locationPrompt: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("macOS only reveals network names to apps allowed to use Location Services.")
        .font(globalSettings.settingsFont(scaledBy: 0.85))
        .foregroundColor(theme.foreground.opacity(0.7))
        .fixedSize(horizontal: false, vertical: true)
      Button("Open Location Services…") {
        wifi.openLocationSettings()
      }
      .buttonStyle(.plain)
      .font(globalSettings.settingsFont(scaledBy: 0.9))
      .foregroundColor(theme.accent)

      // Leaving the current network does not need its name, so keep it reachable here.
      if info.isAssociated {
        Button("Disconnect") {
          wifi.disconnect()
        }
        .buttonStyle(.plain)
        .font(globalSettings.settingsFont(scaledBy: 0.9))
        .foregroundColor(theme.red)
      }
    }
    .padding(.vertical, 4)
  }

  private var networkList: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 2) {
        let current = info.networks.filter { $0.isCurrent }
        let others = info.networks.filter { !$0.isCurrent }

        if !current.isEmpty {
          sectionCaption("Connected")
          ForEach(current) { network in
            NetworkRow(network: network, promptingSSID: $promptingSSID)
          }
          Text("macOS may reconnect automatically after disconnecting.")
            .font(globalSettings.settingsFont(scaledBy: 0.75))
            .foregroundColor(theme.foreground.opacity(0.5))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 6)
        }
        if !others.isEmpty {
          sectionCaption("Nearby")
          ForEach(others) { network in
            NetworkRow(network: network, promptingSSID: $promptingSSID)
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

/// One nearby network: lock, name, signal strength, join/disconnect on click.
private struct NetworkRow: View {
  let network: WifiNetwork
  @Binding var promptingSSID: String?

  @EnvironmentObject var settings: SettingsManager
  @EnvironmentObject var wifi: WifiService

  @State private var isHovering = false
  @State private var password = ""

  private var globalSettings: GlobalSettings { settings.settings.global }
  private var theme: ABarTheme { ThemeManager.currentTheme(for: settings.settings.theme) }
  private var wifiSettings: WifiWidgetSettings { settings.settings.widgets.wifi }
  private var isPending: Bool { wifi.pendingSSIDs.contains(network.id) }
  private var isPrompting: Bool { promptingSSID == network.id }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      row
      if isPrompting {
        passwordField
      }
    }
    .padding(.horizontal, 6)
    .padding(.vertical, 4)
    .background(
      RoundedRectangle(cornerRadius: 4)
        .fill(isHovering ? theme.foreground.opacity(0.1) : Color.clear)
    )
  }

  private var row: some View {
    HStack(spacing: 6) {
      Image(systemName: network.security.isSecured ? "lock.fill" : "lock.open")
        .font(.system(size: 10))
        .frame(width: 16)
        .foregroundColor(network.isCurrent ? theme.accent : theme.foreground.opacity(0.65))

      Text(network.ssid)
        .font(globalSettings.settingsFont(scaledBy: 0.9))
        .foregroundColor(network.isCurrent ? theme.foreground : theme.foreground.opacity(0.75))
        .lineLimit(1)
        .truncationMode(.tail)

      Spacer(minLength: 4)

      if isPending {
        ProgressView()
          .scaleEffect(0.5)
          .frame(width: 16, height: 16)
      } else if wifiSettings.showSignalStrength {
        signalBars
      }
    }
    .contentShape(Rectangle())
    .onTapGesture(perform: handleTap)
    .onHover { hovering in
      isHovering = hovering
      if hovering {
        NSCursor.pointingHand.push()
      } else {
        NSCursor.pop()
      }
    }
  }

  private var passwordField: some View {
    HStack(spacing: 6) {
      SecureField("Password", text: $password)
        .textFieldStyle(RoundedBorderTextFieldStyle())
        .font(globalSettings.settingsFont(scaledBy: 0.85))
        .onSubmit(join)
      Button("Join", action: join)
        .font(globalSettings.settingsFont(scaledBy: 0.85))
        .disabled(password.isEmpty)
    }
    .padding(.leading, 22)
  }

  private var signalBars: some View {
    HStack(alignment: .bottom, spacing: 1) {
      ForEach(1...4, id: \.self) { bar in
        RoundedRectangle(cornerRadius: 0.5)
          .fill(
            bar <= network.signalBars
              ? (network.isCurrent ? theme.accent : theme.foreground.opacity(0.7))
              : theme.foreground.opacity(0.2)
          )
          .frame(width: 2, height: CGFloat(bar) * 2.5 + 1)
      }
    }
    .frame(height: 11, alignment: .bottom)
  }

  private func handleTap() {
    if network.isCurrent {
      wifi.disconnect()
      return
    }
    // Enterprise networks need an identity this popover does not collect; the service
    // routes those to System Settings.
    if network.needsPassword && !network.security.isEnterprise {
      promptingSSID = isPrompting ? nil : network.id
      return
    }
    wifi.join(network)
  }

  private func join() {
    guard !password.isEmpty else { return }
    wifi.join(network, password: password)
    password = ""
    promptingSSID = nil
  }
}
