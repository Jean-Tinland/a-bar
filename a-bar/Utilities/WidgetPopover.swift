import AppKit
import SwiftUI

/// Shared borderless-panel popover used by bar widgets.
///
/// Extracted from the near-identical private managers in SoundWidget,
/// MicWidget and HackerNewsWidget. The behaviour is intentionally unchanged
/// from those copies; the only additions are the `minWidth`, `maxHeight` and
/// `alignment` knobs needed to cover all three call sites.
final class WidgetPopoverManager: NSObject, ObservableObject {
  /// How the panel lines up horizontally with its anchor.
  enum HorizontalAlignment {
    /// Centered on the anchor (Sound / Mic / Bluetooth).
    case centered
    /// Right edge flush with the anchor's right edge (Hacker News).
    case trailing
  }

  /// Every live manager, weakly held. Used to enforce that at most one widget
  /// popover is open across the whole app: bar windows are torn down and
  /// rebuilt on any settings change, so without this a panel whose manager was
  /// deallocated stays visible on screen and the rebuilt widget opens a second
  /// one on top of it.
  private static let liveManagers = NSHashTable<WidgetPopoverManager>.weakObjects()
  private static let outsideClickMonitor = OutsideClickMonitor()

  /// Whether the panel is currently shown. This is the single source of truth:
  /// widgets must drive their UI from it rather than keeping their own flag,
  /// which would desync as soon as the panel is closed by anything else.
  @Published private(set) var isOpen = false

  private let minWidth: CGFloat
  private let maxHeight: CGFloat?
  private let alignment: HorizontalAlignment

  private weak var anchorView: NSView?
  private var panel: NSPanel?
  private var host: NSHostingController<AnyView>?
  private var contentProvider: (() -> AnyView)?
  private var closeWorkItem: DispatchWorkItem?
  private var barPosition: BarPosition = .top

  init(
    minWidth: CGFloat = 180,
    maxHeight: CGFloat? = nil,
    alignment: HorizontalAlignment = .centered
  ) {
    self.minWidth = minWidth
    self.maxHeight = maxHeight
    self.alignment = alignment
    super.init()
    WidgetPopoverManager.liveManagers.add(self)
  }

  /// Order the panel out if this manager is torn down while still showing —
  /// otherwise the panel outlives its owner and lingers on screen.
  deinit {
    let orphan = panel
    if Thread.isMainThread {
      orphan?.orderOut(nil)
    } else {
      DispatchQueue.main.async { orphan?.orderOut(nil) }
    }
  }

  // MARK: - Open / close

  /// Toggle the panel. Widgets should call this rather than `showPanel()` so
  /// exclusivity and outside-click dismissal are handled for them.
  func toggle() {
    isOpen ? close() : open()
  }

  func open() {
    // Without an anchor `showPanel()` bails, so opening would flip `isOpen`
    // with nothing on screen and the next click would silently do nothing.
    guard anchorView != nil else { return }
    // Close any other popover first, including one orphaned by a bar rebuild.
    WidgetPopoverManager.closeAll(except: self)
    showPanel()
    isOpen = true
    // Listen for outside clicks only while open.
    DispatchQueue.main.async {
      guard self.isOpen else { return }
      WidgetPopoverManager.outsideClickMonitor.start {
        WidgetPopoverManager.closeAll()
      }
    }
  }

  func close() {
    guard isOpen else { return }
    isOpen = false
    scheduleClose()
    WidgetPopoverManager.outsideClickMonitor.stop()
  }

  /// Hide immediately, without the dismissal delay. Used when another popover
  /// takes over, so two panels are never visible at the same time.
  private func closeNow() {
    cancelClose()
    panel?.orderOut(nil)
    if isOpen { isOpen = false }
  }

  /// Close every open popover. Passing `except` keeps that one untouched.
  static func closeAll(except survivor: WidgetPopoverManager? = nil) {
    for manager in liveManagers.allObjects where manager !== survivor {
      manager.closeNow()
    }
    if survivor == nil {
      outsideClickMonitor.stop()
    }
  }

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

  private func showPanel() {
    guard anchorView != nil else { return }
    makePanelIfNeeded()
    guard let panel = panel else { return }

    DispatchQueue.main.async {
      guard self.isOpen else { return }
      // ensure we have hosting controller, create fresh content each show to pick up latest environment
      if let provider = self.contentProvider {
        let view = provider()
        if self.host == nil {
          let h = Self.makeHost(view)
          h.view.layer?.masksToBounds = false
          self.host = h
          panel.contentView = h.view
        } else if let host = self.host {
          host.rootView = view
        }
      }

      guard self.layoutPanel() else { return }
      // The bar may have been raised above the hidden menu bar since the panel was made.
      if let barLevel = self.anchorView?.window?.level.rawValue {
        panel.level = NSWindow.Level(BarWindowLevel.popoverLevel(above: barLevel))
      }
      panel.orderFrontRegardless()

      self.cancelClose()
    }
  }

  /// Re-fit the panel to its content while it stays open.
  ///
  /// The panel keeps whatever frame it was given when it was shown, so content
  /// that grows or shrinks on its own — a device list that appears when a radio
  /// is switched back on — either leaves dead space or gets squeezed into a
  /// sliver with a scroller. Widgets call this when the state their popover
  /// renders changes.
  func refreshSize() {
    guard isOpen else { return }
    DispatchQueue.main.async {
      self.layoutPanel()
    }
  }

  /// Size the panel to its hosted content and place it against its anchor.
  /// Returns false when it cannot be placed yet (no anchor, no window, no host).
  @discardableResult
  private func layoutPanel() -> Bool {
    guard let panel = panel, let anchor = anchorView, let hostView = host?.view else { return false }

    // Flush any pending SwiftUI layout first: right after the content changed,
    // `fittingSize` still reports the size it had a layout pass ago.
    hostView.layoutSubtreeIfNeeded()

    // compute size
    let desiredSize = hostView.fittingSize
    let height = maxHeight.map { min($0, desiredSize.height) } ?? desiredSize.height
    let size = NSSize(width: max(minWidth, desiredSize.width), height: height)
    guard size.height > 0 else { return false }

    // compute screen position below/above anchor based on bar position
    guard let win = anchor.window else { return false }
    let rectInWindow = anchor.convert(anchor.bounds, to: win.contentView)
    let screenRect = win.convertToScreen(rectInWindow)

    // Get screen bounds to prevent drawing outside
    guard let screen = win.screen else { return false }
    let screenFrame = screen.visibleFrame

    // Calculate horizontal position, aligned to the widget but clamped to screen
    var x =
      alignment == .centered
      ? screenRect.midX - (size.width / 2)
      : screenRect.maxX - size.width
    x = max(screenFrame.minX + 6, min(x, screenFrame.maxX - size.width - 6))

    // Position popover below widget for top bar, above for bottom bar
    let y = barPosition == .top
      ? screenRect.minY - size.height - 6
      : screenRect.maxY + 6
    let origin = NSPoint(x: x, y: y)

    panel.setFrame(NSRect(origin: origin, size: size), display: true)
    return true
  }

  private func scheduleClose(after delay: TimeInterval = 0.6) {
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

  /// Set the SwiftUI content shown in the panel.
  func setContent<Content: View>(_ provider: @escaping () -> Content) {
    contentProvider = {
      AnyView(provider())
    }
    // if panel already exists, refresh host
    if let panel = panel, let provider = contentProvider {
      let h = Self.makeHost(provider())
      host = h
      panel.contentView = h.view
    }
  }

  /// `layoutPanel()` owns the panel frame. The default `.standardBounds` also installs
  /// required min/max constraints, which resize the window back to the content on the
  /// next layout pass and undo `minWidth` and `maxHeight`. Intrinsic size alone still
  /// lets `fittingSize` measure the content.
  private static func makeHost(_ view: AnyView) -> NSHostingController<AnyView> {
    let host = NSHostingController(rootView: view)
    host.sizingOptions = .intrinsicContentSize
    host.view.wantsLayer = true
    return host
  }
}

/// Small helper to get an NSView anchor for a SwiftUI view.
struct WidgetPopoverAnchor: NSViewRepresentable {
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
