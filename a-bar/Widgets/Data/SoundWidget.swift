import AppKit
import NotificationCenter
import SwiftUI

/// Sound/Volume widget
struct SoundWidget: View {
  let position: BarPosition
  
  @EnvironmentObject var settings: SettingsManager
  @EnvironmentObject var systemInfo: SystemInfoService

  @State private var showPopper: Bool = false
  @State private var tempVolume: Double? = nil
  @StateObject private var popoverManager = SoundPopoverManager()

  private var globalSettings: GlobalSettings {
    settings.settings.global
  }

  private var soundSettings: SoundWidgetSettings {
    settings.settings.widgets.sound
  }

  private var theme: ABarTheme {
    ThemeManager.currentTheme(for: settings.settings.theme)
  }

  var body: some View {
    let bgColor = soundSettings.backgroundColor.color(from: theme)
    let fgColor =
      globalSettings.noColorInDataWidgets
      ? theme.foreground : bgColor.contrastingForeground(from: theme)

    BaseWidgetView(
      backgroundColor: globalSettings.noColorInDataWidgets
        ? theme.minor.opacity(0.95) : bgColor.opacity(0.95),
      onClick: {
        if showPopper {
          showPopper = false
          popoverManager.scheduleClose()
          OutsideClickMonitor.shared.stop()
        } else {
          // Activate abar so the popover can render even if not focused
          NSApp.activate(ignoringOtherApps: true)
          tempVolume = Double(systemInfo.volumeLevel)
          showPopper = true
          popoverManager.showPanel()
          // Listen for outside click only when opening
          DispatchQueue.main.async {
            OutsideClickMonitor.shared.start {
              if showPopper {
                showPopper = false
                popoverManager.scheduleClose()
                OutsideClickMonitor.shared.stop()
              }
            }
          }
        }
      },
      onRightClick: openSoundPreferences
    ) {
      HStack(spacing: 4) {
        if soundSettings.showIcon {
          Image(systemName: volumeIcon)
            .font(.system(size: 11))
            .foregroundColor(fgColor)
        }

        Text(volumeText)
          .foregroundColor(fgColor)
      }
    }
    .background(
      AnchorView(
        onMake: { view in
          popoverManager.attach(anchorView: view, position: position)

          // Set popover content using a dedicated SwiftUI view so it keeps its own state
          let commit: (Double) -> Void = { v in
            if systemInfo.volumeLevel > 1.01 {
              systemInfo.setSystemVolume(Float(v * 100))
            } else {
              systemInfo.setSystemVolume(Float(v))
            }
          }

          let toggle: () -> Void = {
            systemInfo.setSystemMuted(!systemInfo.isMuted)
          }

          let openPrefs: () -> Void = {
            Task {
              _ = try? await ShellExecutor.run(
                "open /System/Library/PreferencePanes/Sound.prefPane/")
            }
          }

          popoverManager.setContent {
            PopoverContent(
              sliderValue: normalizedVolume, theme: theme, globalSettings: globalSettings,
              onCommit: commit, onToggleMute: toggle, onOpenPrefs: openPrefs
            )
            .environmentObject(settings)
            .environmentObject(systemInfo)
          }
        }
      ))
  }

  // Helper for outside click detection
  private class OutsideClickMonitor {
    static let shared = OutsideClickMonitor()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var handler: (() -> Void)?

    func start(_ handler: @escaping () -> Void) {
      stop()
      self.handler = handler
      // Global monitor: catches clicks when app is inactive
      globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown])
      { [weak self] event in
        self?.handle(event: event)
      }
      // Local monitor: catches clicks when app is active
      localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
        [weak self] event in
        self?.handle(event: event)
        return event
      }
    }

    func stop() {
      if let globalMonitor = globalMonitor {
        NSEvent.removeMonitor(globalMonitor)
        self.globalMonitor = nil
      }
      if let localMonitor = localMonitor {
        NSEvent.removeMonitor(localMonitor)
        self.localMonitor = nil
      }
      handler = nil
    }

    private func handle(event: NSEvent) {
      // Only close if click is outside both the widget and the popover panel
      let windowNumber = event.windowNumber
      // Get all windows belonging to this process
      let myWindows = NSApp.windows
      // If the click is in any of our windows, ignore
      if myWindows.contains(where: { $0.windowNumber == windowNumber }) {
        // Click is inside our app, ignore
        return
      }
      // Otherwise, treat as outside click
      self.handler?()
    }
  }

  private var normalizedVolume: Double {
    // If volumeLevel is in 0...1, use as is. If in 0...100, normalize.
    let v = systemInfo.volumeLevel
    if v > 1.01 { return Double(min(1.0, max(0.0, v / 100.0))) }
    return Double(min(1.0, max(0.0, v)))
  }

  private var volumeIcon: String {
    if systemInfo.isMuted {
      return "speaker.slash.fill"
    }
    let level = normalizedVolume
    if level == 0 {
      return "speaker.fill"
    } else if level < 0.33 {
      return "speaker.wave.1.fill"
    } else if level < 0.66 {
      return "speaker.wave.2.fill"
    } else {
      return "speaker.wave.3.fill"
    }
  }

  private var volumeText: String {
    if systemInfo.isMuted {
      return "-%"
    }
    return "\(Int(normalizedVolume * 100))%"
  }

  @ViewBuilder
  private func popperView() -> some View {
    VStack(spacing: 6) {
      HStack(spacing: 8) {
        Button(action: toggleMute) {
          Image(systemName: systemInfo.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
            .font(.system(size: 12, weight: .regular))
            .foregroundColor(theme.foreground)
        }

        Slider(
          value: Binding(
            get: {
              if let t = tempVolume { return t }
              // Use normalized value for slider
              let v = systemInfo.volumeLevel
              return Double(v > 1.01 ? v / 100.0 : v)
            },
            set: { new in tempVolume = new }
          ), in: 0...1,
          onEditingChanged: { editing in
            if !editing {
              commitVolume()
            }
          }
        )
        .frame(minWidth: 120, maxWidth: 200)

        Button(action: openSoundPreferences) {
          Image(systemName: "gearshape")
            .font(.system(size: 12, weight: .regular))
            .foregroundColor(theme.foreground)
        }
      }
      .padding(8)
      .background(
        RoundedRectangle(cornerRadius: 8)
          .fill(globalSettings.noColorInDataWidgets ? theme.minor : theme.background)
          .shadow(color: Color.black.opacity(0.12), radius: 4, x: 0, y: 2)
      )
    }
    .padding(.bottom, 6)
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 6)
  }

  private struct PopoverContent: View {
    @EnvironmentObject var systemInfo: SystemInfoService
    @State var sliderValue: Double
    var theme: ABarTheme
    var globalSettings: GlobalSettings
    let onCommit: (Double) -> Void
    let onToggleMute: () -> Void
    let onOpenPrefs: () -> Void

    // Helper to normalize volume for slider
    private var normalizedVolume: Double {
      let v = systemInfo.volumeLevel
      if v > 1.01 { return Double(min(1.0, max(0.0, v / 100.0))) }
      return Double(min(1.0, max(0.0, v)))
    }

    var body: some View {
      VStack(spacing: 6) {
        // Audio device name
        if !systemInfo.audioOutputDeviceName.isEmpty {
          Text(systemInfo.audioOutputDeviceName)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(theme.foreground.opacity(0.8))
            .padding(.top, 4)
        }
        
        HStack(spacing: 8) {
          Button(action: onToggleMute) {
            Image(systemName: systemInfo.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
              .font(.system(size: 12, weight: .regular))
              .foregroundColor(theme.foreground)
          }

          Slider(
            value: $sliderValue, in: 0...1,
            onEditingChanged: { editing in
              if !editing {
                onCommit(sliderValue)
              }
            }
          )
          .frame(minWidth: 120, maxWidth: 200)

          Button(action: onOpenPrefs) {
            Image(systemName: "gearshape")
              .font(.system(size: 12, weight: .regular))
              .foregroundColor(theme.foreground)
          }
        }
        .padding(8)
        .padding(.top, 2)
      }
      .padding(6)
      .background(
        RoundedRectangle(cornerRadius: 8)
          .fill(globalSettings.noColorInDataWidgets ? theme.minor : theme.background)
          .shadow(color: Color.black.opacity(0.12), radius: 4, x: 0, y: 2)
      )
      .frame(maxWidth: .infinity)
      .padding(.horizontal, 6)
      .onAppear {
        sliderValue = normalizedVolume
      }
      .onReceive(systemInfo.$volumeLevel) { newLevel in
        // update slider while open when system volume changes externally
        let v = newLevel
        sliderValue = Double(v > 1.01 ? v / 100.0 : v)
      }
    }
  }

  private class SoundPopoverManager: NSObject, ObservableObject {
    private weak var anchorView: NSView?
    private var panel: NSPanel?
    private var host: NSHostingController<AnyView>?
    private var contentProvider: (() -> AnyView)?
    private var closeWorkItem: DispatchWorkItem?
    private var barPosition: BarPosition = .top

    func attach(anchorView: NSView, position: BarPosition) {
      self.anchorView = anchorView
      self.barPosition = position
    }

    private func makePanelIfNeeded() {
      guard panel == nil else { return }
      let p = NSPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: true)
      p.isOpaque = false
      p.backgroundColor = .clear
      p.hasShadow = true
      p.level = .statusBar
      p.isMovableByWindowBackground = false
      p.collectionBehavior = [.canJoinAllSpaces, .transient]
      p.ignoresMouseEvents = false
      p.becomesKeyOnlyIfNeeded = true
      // Prevent panel from stealing focus
      p.isReleasedWhenClosed = false
      panel = p
    }

    func showPanel() {
      guard let anchor = anchorView else { return }
      makePanelIfNeeded()
      guard let panel = panel else { return }

      DispatchQueue.main.async {
        // ensure we have hosting controller, create fresh content each show to pick up latest environment
        if let provider = self.contentProvider {
          let view = provider()
          if self.host == nil {
            let h = NSHostingController(rootView: view)
            h.view.wantsLayer = true
            h.view.layer?.masksToBounds = false
            self.host = h
            panel.contentView = h.view
          } else if let host = self.host {
            host.rootView = view
          }
        }

        guard let hostView = self.host?.view else { return }

        // compute size
        let desiredSize = hostView.fittingSize
        let size = NSSize(width: max(180, desiredSize.width), height: desiredSize.height)

        // compute screen position below/above anchor based on bar position
        guard let win = anchor.window else { return }
        let rectInWindow = anchor.convert(anchor.bounds, to: win.contentView)
        let screenRect = win.convertToScreen(rectInWindow)
        
        // Get screen bounds to prevent drawing outside
        guard let screen = win.screen else { return }
        let screenFrame = screen.visibleFrame

        // Calculate horizontal position, centered on widget but clamped to screen
        var x = screenRect.midX - (size.width / 2)
        x = max(screenFrame.minX + 6, min(x, screenFrame.maxX - size.width - 6))
        
        // Position popover below widget for top bar, above for bottom bar
        let y = self.barPosition == .top
          ? screenRect.minY - size.height - 6
          : screenRect.maxY + 6
        let origin = NSPoint(x: x, y: y)

        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()

        // No tracking area needed for click-only popover

        self.cancelClose()
      }
    }

    func scheduleClose(after delay: TimeInterval = 0.6) {
      cancelClose()
      let item = DispatchWorkItem { [weak self] in
        guard let self = self else { return }
        DispatchQueue.main.async {
          self.panel?.orderOut(nil)
        }
      }
      closeWorkItem = item
      DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func cancelClose() {
      closeWorkItem?.cancel()
      closeWorkItem = nil
    }

    // set the SwiftUI content shown in the panel
    func setContent<Content: View>(_ provider: @escaping () -> Content) {
      contentProvider = {
        AnyView(provider())
      }
      // if panel already exists, refresh host
      if let panel = panel, let provider = contentProvider {
        let view = provider()
        let h = NSHostingController(rootView: view)
        h.view.wantsLayer = true
        host = h
        panel.contentView = h.view
      }
    }
  }

  /// Small helper to get an NSView anchor for the SwiftUI view
  private struct AnchorView: NSViewRepresentable {
    var onMake: (NSView) -> Void
    var onHoverChanged: ((Bool) -> Void)? = nil

    func makeNSView(context: Context) -> NSView {
      let v = TrackingNSView()
      v.onHoverChanged = onHoverChanged
      DispatchQueue.main.async {
        onMake(v)
      }
      return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    // Custom NSView subclass to ensure tracking area is always active and forwards mouse events
    private class TrackingNSView: NSView {
      private var trackingArea: NSTrackingArea?
      var onHoverChanged: ((Bool) -> Void)?
      private var isHovering = false

      override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea {
          removeTrackingArea(ta)
        }
        let options: NSTrackingArea.Options = [
          .mouseEnteredAndExited, .activeAlways, .inVisibleRect, .mouseMoved,
        ]
        let ta = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(ta)
        trackingArea = ta
      }

      override func mouseEntered(with event: NSEvent) {
        isHovering = true
        onHoverChanged?(true)
      }
      override func mouseExited(with event: NSEvent) {
        isHovering = false
        onHoverChanged?(false)
      }
      override func mouseMoved(with event: NSEvent) {
        if !isHovering {
          isHovering = true
          onHoverChanged?(true)
        }
      }
    }
  }

  private func commitVolume() {
    guard let v = tempVolume else { return }
    Task {
      systemInfo.setSystemVolume(Float(v))
    }
  }

  private func toggleMute() {
    Task {
      systemInfo.setSystemMuted(!systemInfo.isMuted)
    }
  }
  private func openSoundPreferences() {
    Task {
      _ = try? await ShellExecutor.run("open /System/Library/PreferencePanes/Sound.prefPane/")
    }
  }
}
