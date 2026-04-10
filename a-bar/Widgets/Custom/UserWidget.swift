import AppKit
import SwiftUI

/// Error types for user widget operations
enum UserWidgetError: LocalizedError {
  case duplicateName(String)
  case widgetNotFound(String)

  var errorDescription: String? {
    switch self {
    case .duplicateName(let name):
      return "A widget with the name '\(name)' already exists. Widget names must be unique."
    case .widgetNotFound(let name):
      return "No widget found with the name '\(name)'."
    }
  }
}

/// Captures a reference to the hosting NSView for menu positioning
struct ViewAnchor: NSViewRepresentable {
  @Binding var nsView: NSView?

  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    DispatchQueue.main.async { self.nsView = view }
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {}
}

/// User-defined custom widget with xbar-compatible output parsing.
///
/// Scripts write to stdout:
/// - Lines before `---` cycle in the bar
/// - Lines after `---` appear in a dropdown menu on click
/// - Parameters are specified via pipe: `text | color=red | href=...`
struct UserWidget: View {
  let config: UserWidgetDefinition
  var position: BarPosition = .top

  @EnvironmentObject var settings: SettingsManager

  @State private var parsedOutput: XBarParsedOutput = .empty
  @State private var isLoading = true
  @State private var errorMessage: String? = nil
  @State private var currentHeaderIndex = 0
  @State private var anchorView: NSView?
  @State private var menuActionHandler = XBarMenuActionHandler()

  /// Maximum script output size that will be parsed (512 KB).
  /// Output exceeding this is treated as a script error to prevent memory issues.
  private static let maxOutputBytes = 512 * 1024

  private var globalSettings: GlobalSettings {
    settings.settings.global
  }

  private var theme: ABarTheme {
    ThemeManager.currentTheme(for: settings.settings.theme)
  }

  /// Parse backgroundColor string to SwiftUI Color
  private var customBackgroundColor: Color? {
    guard let bg = config.backgroundColor, !bg.isEmpty else { return nil }

    switch bg.lowercased() {
    case "main": return theme.main
    case "mainalt": return theme.mainAlt
    case "minor": return theme.minor
    case "accent": return theme.accent
    case "red": return theme.red
    case "green": return theme.green
    case "yellow": return theme.yellow
    case "orange": return theme.orange
    case "blue": return theme.blue
    case "magenta": return theme.magenta
    case "cyan": return theme.cyan
    default: return Color(cssString: bg)
    }
  }

  /// Get contrasted foreground color based on background
  private var foregroundColor: Color {
    if let bgColor = customBackgroundColor {
      return bgColor.contrastingForeground(
        from: theme,
        opacity: globalSettings.barElementsBackgroundOpacity,
        barBackground: theme.background
      )
    }
    return theme.foreground
  }

  private var errorBackgroundColor: Color { theme.red }

  private var errorForegroundColor: Color {
    theme.red.contrastingForeground(
      from: theme,
      opacity: globalSettings.barElementsBackgroundOpacity,
      barBackground: theme.background
    )
  }

  /// The currently displayed header item (cycles through header lines)
  private var currentHeaderItem: XBarLineItem? {
    let headers = parsedOutput.headerLines
    guard !headers.isEmpty else { return nil }
    let index = currentHeaderIndex % headers.count
    return headers[index]
  }

  /// Whether there are dropdown items to show
  private var hasDropdown: Bool {
    if !parsedOutput.menuItems.isEmpty { return true }
    return parsedOutput.headerLines.filter({ $0.params.dropdown }).count > 1
  }

  var body: some View {
    Group {
      if config.isActive {
        if errorMessage != nil {
          // Error state: always visible regardless of hideWhenEmpty
          BaseWidgetView(
            backgroundColor: errorBackgroundColor,
            onClick: showErrorMenu
          ) {
            HStack(spacing: 4) {
              Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9))
                .foregroundColor(errorForegroundColor)
              Text(config.name)
                .foregroundColor(errorForegroundColor)
                .lineLimit(1)
            }
          }
          .background(ViewAnchor(nsView: $anchorView))
        } else if !(config.hideWhenEmpty && parsedOutput.headerLines.isEmpty && !isLoading) {
          BaseWidgetView(
            backgroundColor: customBackgroundColor,
            onClick: hasDropdown ? showDropdownMenu : nil
          ) {
            if isLoading {
              ProgressView()
                .scaleEffect(0.4)
                .frame(width: 12, height: 12)
            } else if let item = currentHeaderItem {
              headerItemView(item)
            } else {
              Text(config.name)
                .foregroundColor(foregroundColor)
                .lineLimit(1)
            }
          }
          .background(ViewAnchor(nsView: $anchorView))
        }
      }
    }
    .onAppear {
      menuActionHandler.onRefresh = { refreshOutput() }
      if config.isActive {
        refreshOutput()
      }
    }
    .onReceive(
      Timer.publish(every: config.refreshInterval, on: .main, in: .common).autoconnect()
    ) { _ in
      if config.isActive {
        refreshOutput()
      }
    }
    .onReceive(
      Timer.publish(every: max(1, config.cycleDuration), on: .main, in: .common).autoconnect()
    ) { _ in
      if parsedOutput.headerLines.count > 1 {
        currentHeaderIndex = (currentHeaderIndex + 1) % parsedOutput.headerLines.count
      }
    }
    .onReceive(
      NotificationCenter.default.publisher(for: NSNotification.Name("RefreshUserWidget"))
    ) { notification in
      if let widgetId = notification.userInfo?["widgetId"] as? UUID, widgetId == config.id {
        refreshOutput()
      }
    }
  }

  @ViewBuilder
  private func headerItemView(_ item: XBarLineItem) -> some View {
    HStack(spacing: 4) {
      if let imageData = item.params.templateImage ?? item.params.image,
        let data = Data(base64Encoded: imageData),
        let nsImage = NSImage(data: data)
      {
        Image(nsImage: nsImage)
          .resizable()
          .scaledToFit()
          .frame(height: 14)
      }

      if !item.title.isEmpty {
        let displayText = truncatedTitle(item)
        Text(displayText)
          .foregroundColor(itemColor(item))
          .lineLimit(1)
          .if(item.params.font != nil || item.params.size != nil) { view in
            view.font(
              .custom(
                item.params.font ?? globalSettings.fontName,
                size: item.params.size ?? CGFloat(globalSettings.fontSize)
              )
            )
          }
      }
    }
  }

  private func itemColor(_ item: XBarLineItem) -> Color {
    if let colorStr = item.params.color,
      let nsColor = NSColor(xbarString: colorStr)
    {
      return Color(nsColor)
    }
    return foregroundColor
  }

  private func truncatedTitle(_ item: XBarLineItem) -> String {
    guard let maxLen = item.params.length, item.title.count > maxLen else {
      return item.title
    }
    return String(item.title.prefix(maxLen)) + "…"
  }

  private func showDropdownMenu() {
    guard let view = anchorView else { return }

    let menu = XBarMenuBuilder.buildMenu(from: parsedOutput, handler: menuActionHandler)
    guard menu.items.count > 0 else { return }

    objc_setAssociatedObject(menu, "handler", menuActionHandler, .OBJC_ASSOCIATION_RETAIN)

    let anchorPoint = position == .bottom
      ? NSPoint(x: 0, y: view.bounds.height)
      : NSPoint(x: 0, y: 0)
    menu.popUp(positioning: nil, at: anchorPoint, in: view)
  }

  private func showErrorMenu() {
    guard let view = anchorView, let errMsg = errorMessage else { return }

    let menu = NSMenu()
    menu.autoenablesItems = false

    let titleItem = NSMenuItem(title: "Script error — \(config.name)", action: nil, keyEquivalent: "")
    titleItem.isEnabled = false
    titleItem.attributedTitle = NSAttributedString(
      string: "Script error — \(config.name)",
      attributes: [
        .foregroundColor: NSColor.systemRed,
        .font: NSFont.menuFont(ofSize: NSFont.menuFont(ofSize: 0).pointSize),
      ]
    )
    menu.addItem(titleItem)
    menu.addItem(.separator())

    // Show each line of stderr as a disabled item
    let lines = errMsg
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .components(separatedBy: "\n")
    for line in lines where !line.isEmpty {
      let item = NSMenuItem(title: line, action: nil, keyEquivalent: "")
      item.isEnabled = false
      menu.addItem(item)
    }

    menu.addItem(.separator())

    let retryItem = NSMenuItem(title: "Retry", action: #selector(NSObject.doesNotRecognizeSelector(_:)), keyEquivalent: "")
    retryItem.isEnabled = true
    let handler = menuActionHandler
    handler.onRefresh = { refreshOutput() }
    let retryWrapper = NSMenuItem()
    retryWrapper.title = "Retry"
    retryWrapper.target = handler
    retryWrapper.action = #selector(XBarMenuActionHandler.retryAction(_:))
    retryWrapper.isEnabled = true
    objc_setAssociatedObject(menu, "handler", handler, .OBJC_ASSOCIATION_RETAIN)
    menu.addItem(retryWrapper)

    let anchorPoint = position == .bottom
      ? NSPoint(x: 0, y: view.bounds.height)
      : NSPoint(x: 0, y: 0)
    menu.popUp(positioning: nil, at: anchorPoint, in: view)
  }

  private func refreshOutput() {
    let command = config.command
    if command.isEmpty {
      isLoading = false
      return
    }

    Task {
      let result = await ShellExecutor.runWidget(command)
      await MainActor.run {
        if !result.succeeded {
          // Build an informative error message from stderr and exit code
          let stderrTrimmed = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
          if result.exitCode == -1 {
            // Process launch failure — stderr already contains the description
            errorMessage = stderrTrimmed.isEmpty
              ? "Script could not be started."
              : stderrTrimmed
          } else {
            let codeNote = "Exit code: \(result.exitCode)"
            errorMessage = stderrTrimmed.isEmpty ? codeNote : "\(codeNote)\n\(stderrTrimmed)"
          }
          parsedOutput = .empty
          currentHeaderIndex = 0
          isLoading = false
          return
        }

        // Guard against excessively large output before parsing
        let rawOutput = result.stdout
        guard rawOutput.utf8.count <= Self.maxOutputBytes else {
          errorMessage =
            "Script output too large (\(rawOutput.utf8.count / 1024) KB). Maximum is \(Self.maxOutputBytes / 1024) KB."
          parsedOutput = .empty
          currentHeaderIndex = 0
          isLoading = false
          return
        }

        errorMessage = nil
        let newOutput = XBarParser.parse(rawOutput)
        if newOutput.headerLines.count != parsedOutput.headerLines.count {
          currentHeaderIndex = 0
        }
        parsedOutput = newOutput
        isLoading = false
      }
    }
  }
}

class UserWidgetManager: ObservableObject {
  static let shared = UserWidgetManager()

  private let settingsManager = SettingsManager.shared

  var widgets: [UserWidgetDefinition] {
    get { settingsManager.settings.userWidgets }
    set { settingsManager.settings.userWidgets = newValue }
  }

  private init() {}

  private func isNameTaken(_ name: String, excludingId: UUID? = nil) -> Bool {
    return widgets.contains { widget in
      widget.name == name && widget.id != excludingId
    }
  }

  func addWidget(_ config: UserWidgetDefinition) throws {
    if isNameTaken(config.name) {
      throw UserWidgetError.duplicateName(config.name)
    }
    settingsManager.settings.userWidgets.append(config)
  }

  func removeWidget(id: UUID) {
    settingsManager.settings.userWidgets.removeAll { $0.id == id }
  }

  func updateWidget(_ config: UserWidgetDefinition) throws {
    if isNameTaken(config.name, excludingId: config.id) {
      throw UserWidgetError.duplicateName(config.name)
    }

    if let index = settingsManager.settings.userWidgets.firstIndex(where: { $0.id == config.id }) {
      settingsManager.settings.userWidgets[index] = config
    }
  }

  func moveWidget(from source: IndexSet, to destination: Int) {
    settingsManager.settings.userWidgets.move(fromOffsets: source, toOffset: destination)
  }

  @discardableResult
  func refreshWidget(named name: String) -> Bool {
    guard let widget = widgets.first(where: { $0.name == name }) else {
      return false
    }

    NotificationCenter.default.post(
      name: NSNotification.Name("RefreshUserWidget"),
      object: nil,
      userInfo: ["widgetId": widget.id]
    )

    return true
  }

  func toggleWidget(named name: String) -> Result<Bool, UserWidgetError> {
    guard
      let index = settingsManager.settings.userWidgets.firstIndex(where: { $0.name == name })
    else {
      return .failure(.widgetNotFound(name))
    }

    settingsManager.settings.userWidgets[index].isActive.toggle()
    let newState = settingsManager.settings.userWidgets[index].isActive
    return .success(newState)
  }

  func hideWidget(named name: String) -> Result<Bool, UserWidgetError> {
    guard
      let index = settingsManager.settings.userWidgets.firstIndex(where: { $0.name == name })
    else {
      return .failure(.widgetNotFound(name))
    }

    if settingsManager.settings.userWidgets[index].isActive {
      settingsManager.settings.userWidgets[index].isActive = false
      return .success(true)
    } else {
      return .success(false)
    }
  }

  func showWidget(named name: String) -> Result<Bool, UserWidgetError> {
    guard
      let index = settingsManager.settings.userWidgets.firstIndex(where: { $0.name == name })
    else {
      return .failure(.widgetNotFound(name))
    }

    if !settingsManager.settings.userWidgets[index].isActive {
      settingsManager.settings.userWidgets[index].isActive = true
      return .success(true)
    } else {
      return .success(false)
    }
  }
}
