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

/// User-defined custom widget
struct UserWidget: View {
  let config: UserWidgetDefinition

  @EnvironmentObject var settings: SettingsManager

  @State private var output: String = ""
  @State private var isLoading = true
  
  
  private var globalSettings: GlobalSettings {
      settings.settings.global
  }

  private var theme: ABarTheme {
    ThemeManager.currentTheme(for: settings.settings.theme)
  }

  /// Parse backgroundColor string to SwiftUI Color
  /// Supports theme color names (main, red, etc.) and CSS color strings
  private var customBackgroundColor: Color? {
    guard let bg = config.backgroundColor, !bg.isEmpty else { return nil }
    
    // Check if it's a theme color name
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

  var body: some View {
    if config.isActive && !(config.hideWhenEmpty && output.isEmpty && !isLoading) {
      BaseWidgetView(
        backgroundColor: customBackgroundColor,
        onClick: config.clickCommand != nil ? executeClick : nil,
      ) {
        HStack(spacing: 4) {
          if !config.hideIcon {
            Image(systemName: config.icon)
              .font(.system(size: 10))
              .foregroundColor(foregroundColor)
          }

          if isLoading {
            ProgressView()
              .scaleEffect(0.4)
              .frame(width: 12, height: 12)
          } else if !output.isEmpty {
            Text(output)
              .foregroundColor(foregroundColor)
              .lineLimit(1)
          }
        }
      }
      .task(id: config.refreshInterval) {
        // Initial refresh
        refreshOutput()
        
        // Continuous refresh loop
        while !Task.isCancelled {
          try? await Task.sleep(nanoseconds: UInt64(config.refreshInterval * 1_000_000_000))
          if !Task.isCancelled {
            refreshOutput()
          }
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
  }

  private func refreshOutput() {
    let command = config.command

    if command.isEmpty {
      isLoading = false
      return
    }

    Task {
      do {
        let result = try await ShellExecutor.run(command)
        await MainActor.run {
          output = result.trimmingCharacters(in: .whitespacesAndNewlines)
          isLoading = false
        }
      } catch {
        print("User widget error: \(error)")
        await MainActor.run {
          output = "Error"
          isLoading = false
        }
      }
    }
  }

  private func executeClick() {
    guard let command = config.clickCommand, !command.isEmpty else { return }

    Task {
      _ = try? await ShellExecutor.run(command)
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

  /// Check if a widget name is already in use (excluding a specific widget ID)
  private func isNameTaken(_ name: String, excludingId: UUID? = nil) -> Bool {
    return widgets.contains { widget in
      widget.name == name && widget.id != excludingId
    }
  }

  func addWidget(_ config: UserWidgetDefinition) throws {
    // Ensure unique name
    if isNameTaken(config.name) {
      throw UserWidgetError.duplicateName(config.name)
    }
    settingsManager.settings.userWidgets.append(config)
  }

  func removeWidget(id: UUID) {
    settingsManager.settings.userWidgets.removeAll { $0.id == id }
  }

  func updateWidget(_ config: UserWidgetDefinition) throws {
    // Ensure unique name (excluding current widget)
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

  /// Refresh a specific user widget by name
  /// - Parameter name: The name of the widget to refresh
  /// - Returns: true if the widget was found and can be refreshed, false otherwise
  @discardableResult
  func refreshWidget(named name: String) -> Bool {
    guard let widget = widgets.first(where: { $0.name == name }) else {
      return false
    }

    // Post notification to trigger refresh
    NotificationCenter.default.post(
      name: NSNotification.Name("RefreshUserWidget"),
      object: nil,
      userInfo: ["widgetId": widget.id]
    )

    return true
  }

  /// Toggle visibility of a specific user widget by name
  /// - Parameter name: The name of the widget to toggle
  /// - Returns: Result with the new isActive state, or error if not found
  func toggleWidget(named name: String) -> Result<Bool, UserWidgetError> {
    guard let index = settingsManager.settings.userWidgets.firstIndex(where: { $0.name == name }) else {
      return .failure(.widgetNotFound(name))
    }

    settingsManager.settings.userWidgets[index].isActive.toggle()
    let newState = settingsManager.settings.userWidgets[index].isActive
    return .success(newState)
  }

  /// Hide a specific user widget by name
  /// - Parameter name: The name of the widget to hide
  /// - Returns: Result with true if the widget was hidden, false if already hidden, or error if not found
  func hideWidget(named name: String) -> Result<Bool, UserWidgetError> {
    guard let index = settingsManager.settings.userWidgets.firstIndex(where: { $0.name == name }) else {
      return .failure(.widgetNotFound(name))
    }

    if settingsManager.settings.userWidgets[index].isActive {
      settingsManager.settings.userWidgets[index].isActive = false
      return .success(true)
    } else {
      return .success(false)
    }
  }

  /// Show a specific user widget by name
  /// - Parameter name: The name of the widget to show
  /// - Returns: Result with true if the widget was shown, false if already shown, or error if not found
  func showWidget(named name: String) -> Result<Bool, UserWidgetError> {
    guard let index = settingsManager.settings.userWidgets.firstIndex(where: { $0.name == name }) else {
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
