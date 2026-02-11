import SwiftUI
import UniformTypeIdentifiers

/// Main entry point for the layout builder - shows list of configured displays
struct LayoutBuilderView: View {
  @EnvironmentObject var settings: SettingsManager
  @StateObject private var profileManager = ProfileManager.shared

  /// The profile currently being edited in settings (synced with SettingsManager)
  private var editingProfileId: Binding<UUID?> {
    Binding(
      get: { settings.editingProfileId },
      set: { settings.editingProfileId = $0 }
    )
  }

  @State private var selectedDisplayWrapper: DisplayIndexWrapper? = nil
  @State private var showingAddDisplaySheet = false
  @State private var showingNewProfileSheet = false
  @State private var showingRenameProfileSheet = false
  @State private var showingDeleteProfileAlert = false

  /// The layout being edited (from the editing profile, stored in draftLayout)
  private var editingLayout: MultiDisplayLayout {
    settings.draftLayout
  }

  /// The profile currently being edited
  private var editingProfile: LayoutProfile? {
    guard let id = settings.editingProfileId else { return profileManager.activeProfile }
    return profileManager.profile(withId: id)
  }

  private var connectedScreenCount: Int {
    NSScreen.screens.count
  }

  var body: some View {
    VStack(spacing: 20) {
      // Profile selector
      ProfileSelectorView(
        profileManager: profileManager,
        editingProfileId: editingProfileId,
        onProfileSelected: { profile in
          // Load the selected profile's layout into draft for editing
          settings.loadLayoutForEditing(profile.multiDisplayLayout)
        },
        showingNewProfileSheet: $showingNewProfileSheet,
        showingRenameProfileSheet: $showingRenameProfileSheet,
        showingDeleteProfileAlert: $showingDeleteProfileAlert
      )

      Divider()

      // Header
      VStack(spacing: 8) {
        Text("Layout Builder")
          .font(.headline)

        Text("Configure bars for each display. Click a display to edit its bars.")
          .font(.subheadline)
          .foregroundColor(.secondary)

        HStack(spacing: 4) {
          Image(systemName: "display")
          Text("\(connectedScreenCount) display\(connectedScreenCount == 1 ? "" : "s") connected")
        }
        .font(.caption)
        .foregroundColor(.secondary)
      }

      Divider()

      // Configured displays list
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text("Configured Displays")
            .font(.subheadline)
            .fontWeight(.semibold)

          Spacer()

          Button(action: { showingAddDisplaySheet = true }) {
            Label("Add Display", systemImage: "plus")
              .font(.caption)
          }
          .buttonStyle(.borderless)
        }

        if editingLayout.displays.isEmpty {
          VStack(spacing: 12) {
            Image(systemName: "rectangle.on.rectangle.slash")
              .font(.system(size: 32))
              .foregroundColor(.secondary)

            Text("No displays configured")
              .font(.subheadline)
              .foregroundColor(.secondary)

            Text("Add a display to start configuring bars")
              .font(.caption)
              .foregroundColor(.secondary)
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 40)
          .background(Color.gray.opacity(0.05))
          .cornerRadius(8)
        } else {
          LazyVStack(spacing: 8) {
            ForEach(editingLayout.displays) { displayConfig in
              DisplayRowView(
                config: displayConfig,
                isConnected: displayConfig.displayIndex < connectedScreenCount,
                onSelect: {
                  selectedDisplayWrapper = DisplayIndexWrapper(id: displayConfig.displayIndex)
                },
                onDelete: {
                  removeDisplay(displayConfig.displayIndex)
                }
              )
            }
          }
        }
      }

      Spacer()

      // Actions
      HStack {
        Button("Reset to Default") {
          settings.draftLayout = .defaultLayout
        }
        .foregroundColor(.red)

        Spacer()
      }
    }
    .padding()
    .onAppear {
      // Initialize editing profile to active profile if not already set
      if settings.editingProfileId == nil {
        settings.editingProfileId = profileManager.activeProfileId
      }
      // Load the editing profile's layout into draft
      if let id = settings.editingProfileId,
         let profile = profileManager.profile(withId: id) {
        settings.loadLayoutForEditing(profile.multiDisplayLayout)
      }
    }
    .sheet(isPresented: $showingAddDisplaySheet) {
      AddDisplaySheet(
        existingIndices: Set(editingLayout.displays.map { $0.displayIndex }),
        connectedCount: connectedScreenCount,
        onAdd: { index, name in
          addDisplay(index: index, name: name)
        }
      )
    }
    .sheet(item: $selectedDisplayWrapper) { wrapper in
      DisplayConfigurationSheet(
        displayIndex: wrapper.displayIndex,
        onDismiss: { selectedDisplayWrapper = nil }
      )
      .environmentObject(settings)
    }
    .sheet(isPresented: $showingNewProfileSheet) {
      NewProfileSheet(
        profileManager: profileManager,
        editingProfileId: editingProfileId,
        onCreated: { profile in
          // Start editing the new profile
          settings.editingProfileId = profile.id
          settings.loadLayoutForEditing(profile.multiDisplayLayout)
        }
      )
    }
    .sheet(isPresented: $showingRenameProfileSheet) {
      RenameProfileSheet(
        profileManager: profileManager,
        editingProfileId: settings.editingProfileId
      )
    }
    .alert("Delete Profile", isPresented: $showingDeleteProfileAlert) {
      Button("Cancel", role: .cancel) {}
      Button("Delete", role: .destructive) {
        if let id = settings.editingProfileId {
          _ = profileManager.deleteProfile(id: id)
          // Switch to editing the active profile
          settings.editingProfileId = profileManager.activeProfileId
          if let profile = profileManager.activeProfile {
            settings.loadLayoutForEditing(profile.multiDisplayLayout)
          }
        }
      }
    } message: {
      Text(
        "Are you sure you want to delete the profile \"\(editingProfile?.name ?? "")\"? This action cannot be undone."
      )
    }
  }

  private func addDisplay(index: Int, name: String) {
    let config = DisplayConfiguration(
      displayIndex: index,
      name: name,
      topBar: nil,
      bottomBar: nil
    )
    settings.draftLayout.setConfiguration(config, forDisplay: index)
  }

  private func removeDisplay(_ index: Int) {
    settings.draftLayout.removeConfiguration(forDisplay: index)
  }
}

// Wrapper for display index to use as sheet item
struct DisplayIndexWrapper: Identifiable {
  let id: Int
  var displayIndex: Int { id }
}

struct DisplayRowView: View {
  let config: DisplayConfiguration
  let isConnected: Bool
  let onSelect: () -> Void
  let onDelete: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      // Display icon
      VStack(spacing: 2) {
        Image(systemName: config.displayIndex == 0 ? "laptopcomputer" : "display")
          .font(.system(size: 20))

        if !isConnected {
          Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 10))
            .foregroundColor(.orange)
        }
      }
      .frame(width: 32)

      // Display info
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text(config.name)
            .font(.subheadline)
            .fontWeight(.medium)

          if !isConnected {
            Text("(Disconnected)")
              .font(.caption)
              .foregroundColor(.orange)
          }
        }

        HStack(spacing: 8) {
          if config.topBar != nil {
            Label("Top", systemImage: "rectangle.topthird.inset.filled")
              .font(.caption2)
              .foregroundColor(.green)
          }

          if config.bottomBar != nil {
            Label("Bottom", systemImage: "rectangle.bottomthird.inset.filled")
              .font(.caption2)
              .foregroundColor(.blue)
          }

          if !config.hasBars {
            Text("No bars configured")
              .font(.caption2)
              .foregroundColor(.secondary)
          }
        }
      }

      Spacer()

      // Actions
      HStack(spacing: 8) {
        Button(action: onSelect) {
          Text("Edit")
            .font(.caption)
        }
        .buttonStyle(.bordered)

        Button(action: onDelete) {
          Image(systemName: "trash")
            .font(.caption)
            .foregroundColor(.red)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(12)
    .background(Color.gray.opacity(0.05))
    .cornerRadius(8)
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .stroke(isConnected ? Color.clear : Color.orange.opacity(0.3), lineWidth: 1)
    )
  }
}

struct AddDisplaySheet: View {
  let existingIndices: Set<Int>
  let connectedCount: Int
  let onAdd: (Int, String) -> Void

  @Environment(\.dismiss) private var dismiss

  @State private var selectedIndex: Int = 0
  @State private var customName: String = ""

  private var availableIndices: [Int] {
    // Show indices 0-9, filter out already configured ones
    (0..<10).filter { !existingIndices.contains($0) }
  }

  var body: some View {
    VStack(spacing: 20) {
      Text("Add Display Configuration")
        .font(.headline)

      Form {
        Picker("External display Index", selection: $selectedIndex) {
          ForEach(availableIndices, id: \.self) { index in
            HStack {
              Text("External display \(index)")
              if index < connectedCount {
                Text("(Connected)")
                  .foregroundColor(.green)
              }
            }
            .tag(index)
          }
        }

        TextField("Display Name", text: $customName)
          .textFieldStyle(.roundedBorder)
      }
      .padding()

      HStack {
        Button("Cancel") {
          dismiss()
        }
        .keyboardShortcut(.cancelAction)

        Spacer()

        Button("Add") {
          let name = customName.isEmpty ? defaultName(for: selectedIndex) : customName
          onAdd(selectedIndex, name)
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
        .buttonStyle(.borderedProminent)
      }
      .padding()
    }
    .frame(width: 400, height: 220)
    .onAppear {
      if let first = availableIndices.first {
        selectedIndex = first
        customName = defaultName(for: first)
      }
    }
    .onChange(of: selectedIndex) { newIndex in
      customName = defaultName(for: newIndex)
    }
  }

  private func defaultName(for index: Int) -> String {
    switch index {
    case 0: return "Main Display"
    default: return "Display \(index + 1)"
    }
  }
}

struct DisplayConfigurationSheet: View {
  let displayIndex: Int
  let onDismiss: () -> Void

  @EnvironmentObject var settings: SettingsManager

  @State private var editingBarPosition: BarPosition? = nil
  @State private var displayName: String = ""

  private var displayConfig: DisplayConfiguration {
    settings.draftLayout.configuration(forDisplay: displayIndex)
      ?? DisplayConfiguration(displayIndex: displayIndex, name: "Display \(displayIndex + 1)")
  }

  var body: some View {
    VStack(spacing: 0) {
      // Header
      HStack {
        Button(action: onDismiss) {
          Image(systemName: "chevron.left")
          Text("Back")
        }
        .buttonStyle(.plain)

        Spacer()

        Text(displayConfig.name)
          .font(.headline)

        Spacer()

        // Spacer to balance the back button
        Button(action: {}) {
          Text("Back")
        }
        .buttonStyle(.plain)
        .opacity(0)
      }
      .padding()
      .background(Color(NSColor.windowBackgroundColor))

      Divider()

      ScrollView {
        VStack(spacing: 24) {
          // Display name editor
          VStack(alignment: .leading, spacing: 8) {
            Text("Display Name")
              .font(.subheadline)
              .fontWeight(.semibold)
            
            TextField("Display name", text: $displayName)
              .textFieldStyle(.roundedBorder)
              .onChange(of: displayName) { newName in
                updateDisplayName(newName)
              }
          }
          .padding(.horizontal)
          
          // Display preview
          DisplayPreviewView(config: displayConfig)
            .frame(height: 180)

          // Bar configurations
          VStack(spacing: 16) {
            BarConfigurationRow(
              title: "Top Bar",
              position: .top,
              barLayout: displayConfig.topBar,
              onToggle: { toggleBar(.top) },
              onEdit: { editingBarPosition = .top }
            )

            BarConfigurationRow(
              title: "Bottom Bar",
              position: .bottom,
              barLayout: displayConfig.bottomBar,
              onToggle: { toggleBar(.bottom) },
              onEdit: { editingBarPosition = .bottom }
            )
          }
          .padding()
        }
        .padding()
      }
    }
    .frame(width: 600, height: 550)
    .sheet(item: $editingBarPosition) { position in
      BarEditorSheet(
        displayIndex: displayIndex,
        position: position,
        onDismiss: { editingBarPosition = nil }
      )
      .environmentObject(settings)
    }
    .onAppear {
      displayName = displayConfig.name
    }
  }
  
  private func updateDisplayName(_ newName: String) {
    guard !newName.isEmpty else { return }
    var config = displayConfig
    config.name = newName
    settings.draftLayout.setConfiguration(config, forDisplay: displayIndex)
  }

  private func toggleBar(_ position: BarPosition) {
    var config = displayConfig
    switch position {
    case .top:
      if config.topBar == nil {
        config.topBar = SingleBarLayout()
      } else {
        config.topBar = nil
      }
    case .bottom:
      if config.bottomBar == nil {
        config.bottomBar = SingleBarLayout()
      } else {
        config.bottomBar = nil
      }
    }
    settings.draftLayout.setConfiguration(config, forDisplay: displayIndex)
  }
}

extension BarPosition: Identifiable {
  public var id: String { rawValue }
}

struct DisplayPreviewView: View {
  let config: DisplayConfiguration

  var body: some View {
    VStack(spacing: 0) {
      // Top bar indicator
      if config.topBar != nil {
        Rectangle()
          .fill(Color.green.opacity(0.3))
          .frame(height: 20)
          .overlay(
            Text("Top Bar")
              .font(.caption2)
              .foregroundColor(.green)
          )
      }

      // Screen area
      Rectangle()
        .fill(Color.gray.opacity(0.1))
        .overlay(
          VStack {
            Image(systemName: config.displayIndex == 0 ? "laptopcomputer" : "display")
              .font(.system(size: 40))
              .foregroundColor(.secondary)
            Text(config.name)
              .font(.caption)
              .foregroundColor(.secondary)
          }
        )

      // Bottom bar indicator
      if config.bottomBar != nil {
        Rectangle()
          .fill(Color.blue.opacity(0.3))
          .frame(height: 20)
          .overlay(
            Text("Bottom Bar")
              .font(.caption2)
              .foregroundColor(.blue)
          )
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
    )
  }
}

struct BarConfigurationRow: View {
  let title: String
  let position: BarPosition
  let barLayout: SingleBarLayout?
  let onToggle: () -> Void
  let onEdit: () -> Void

  private var isEnabled: Bool {
    barLayout != nil
  }

  private var widgetCount: Int {
    guard let layout = barLayout else { return 0 }
    return layout.left.count + layout.center.count + layout.right.count
  }

  var body: some View {
    HStack(spacing: 12) {
      // Icon
      Image(
        systemName: position == .top
          ? "rectangle.topthird.inset.filled"
          : "rectangle.bottomthird.inset.filled"
      )
      .font(.system(size: 20))
      .foregroundColor(isEnabled ? (position == .top ? .green : .blue) : .secondary)
      .frame(width: 32)

      // Info
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.subheadline)
          .fontWeight(.medium)

        if isEnabled {
          Text("\(widgetCount) widget\(widgetCount == 1 ? "" : "s")")
            .font(.caption)
            .foregroundColor(.secondary)
        } else {
          Text("Not configured")
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }

      Spacer()

      // Actions
      HStack(spacing: 8) {
        Toggle(
          "",
          isOn: Binding(
            get: { isEnabled },
            set: { _ in onToggle() }
          )
        )
        .labelsHidden()

        if isEnabled {
          Button("Edit") {
            onEdit()
          }
          .buttonStyle(.bordered)
        }
      }
    }
    .padding(12)
    .background(Color.gray.opacity(0.05))
    .cornerRadius(8)
  }
}

struct BarEditorSheet: View {
  let displayIndex: Int
  let position: BarPosition
  let onDismiss: () -> Void

  @EnvironmentObject var settings: SettingsManager

  @State private var leftWidgets: [WidgetInstance] = []
  @State private var centerWidgets: [WidgetInstance] = []
  @State private var rightWidgets: [WidgetInstance] = []
  @State private var saveTask: Task<Void, Never>? = nil

  private var barLayout: SingleBarLayout? {
    settings.draftLayout.barLayout(
      forDisplay: displayIndex, position: position)
  }
  
  private func findWidget(id: UUID) -> (widget: WidgetInstance, section: WidgetSection)? {
    if let widget = leftWidgets.first(where: { $0.id == id }) {
      return (widget, .left)
    }
    if let widget = centerWidgets.first(where: { $0.id == id }) {
      return (widget, .center)
    }
    if let widget = rightWidgets.first(where: { $0.id == id }) {
      return (widget, .right)
    }
    return nil
  }
  
  private func removeWidget(id: UUID, from section: WidgetSection?) {
    if let section = section {
      switch section {
      case .left: leftWidgets.removeAll { $0.id == id }
      case .center: centerWidgets.removeAll { $0.id == id }
      case .right: rightWidgets.removeAll { $0.id == id }
      }
    } else {
      // Remove from all sections
      leftWidgets.removeAll { $0.id == id }
      centerWidgets.removeAll { $0.id == id }
      rightWidgets.removeAll { $0.id == id }
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      // Header
      HStack {
        Button(action: onDismiss) {
          Image(systemName: "chevron.left")
          Text("Back")
        }
        .buttonStyle(.plain)

        Spacer()

        Text("\(position.displayName) Bar - Display \(displayIndex)")
          .font(.headline)

        Spacer()

        Button(action: {}) {
          Text("Back")
        }
        .buttonStyle(.plain)
        .opacity(0)
      }
      .padding()
      .background(Color(NSColor.windowBackgroundColor))

      Divider()

      // Scrollable widget sections
      ScrollView {
        VStack(spacing: 20) {
          Text("Drag widgets to sections below. Widgets can appear multiple times.")
            .font(.subheadline)
            .foregroundColor(.secondary)

          // Bar sections
          VStack(spacing: 16) {
            WidgetSectionView(
              title: "Left",
              section: .left,
              widgets: $leftWidgets,
              onWidgetsChanged: saveLayout,
              findWidget: findWidget,
              removeWidget: removeWidget
            )

            WidgetSectionView(
              title: "Center",
              section: .center,
              widgets: $centerWidgets,
              onWidgetsChanged: saveLayout,
              findWidget: findWidget,
              removeWidget: removeWidget
            )

            WidgetSectionView(
              title: "Right",
              section: .right,
              widgets: $rightWidgets,
              onWidgetsChanged: saveLayout,
              findWidget: findWidget,
              removeWidget: removeWidget
            )
          }
        }
        .padding()
      }

      Divider()

      // Fixed available widgets section
      ScrollView {
        AvailableWidgetsView()
          .padding()
      }
      .frame(height: 220)
    }
    .frame(width: 650, height: 750)
    .onAppear {
      loadLayout()
    }
  }

  private func loadLayout() {
    DispatchQueue.main.async {
      guard let layout = barLayout else { return }
      leftWidgets = layout.left
      centerWidgets = layout.center
      rightWidgets = layout.right
    }
  }

  private func saveLayout() {
    // Cancel previous save task
    saveTask?.cancel()

    // Debounce saves to avoid too frequent updates
    saveTask = Task { @MainActor in
      try? await Task.sleep(nanoseconds: 150_000_000)  // 150ms

      guard !Task.isCancelled else { return }

      let layout = SingleBarLayout(
        left: leftWidgets,
        center: centerWidgets,
        right: rightWidgets
      )

      var displayConfig =
        settings.draftLayout.configuration(forDisplay: displayIndex)
        ?? DisplayConfiguration(displayIndex: displayIndex, name: "Display \(displayIndex + 1)")

      switch position {
      case .top:
        displayConfig.topBar = layout
      case .bottom:
        displayConfig.bottomBar = layout
      }

      settings.draftLayout.setConfiguration(
        displayConfig, forDisplay: displayIndex)
    }
  }
}

struct WidgetSectionView: View {
  let title: String
  let section: WidgetSection
  @Binding var widgets: [WidgetInstance]
  var onWidgetsChanged: (() -> Void)? = nil
  var findWidget: ((UUID) -> (widget: WidgetInstance, section: WidgetSection)?)? = nil
  var removeWidget: ((UUID, WidgetSection?) -> Void)? = nil

  @State private var dropIndex: Int? = nil

  @EnvironmentObject var settings: SettingsManager

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(title)
          .font(.subheadline)
          .fontWeight(.semibold)
          .foregroundColor(.secondary)
        Spacer()
        Text("\(widgets.count) widget\(widgets.count == 1 ? "" : "s")")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      if widgets.isEmpty {
        emptyDropZone
      } else {
        VStack(spacing: 0) {
          ForEach(widgets.indices, id: \.self) { index in
            DropIndicatorView(isVisible: dropIndex == index)

            let widget = widgets[index]
            WidgetInstanceRowView(
              widget: binding(for: widget),
              onDelete: {
                widgets.removeAll { $0.id == widget.id }
                onWidgetsChanged?()
              },
              onChanged: onWidgetsChanged
            )
            .onDrag {
              NSItemProvider(object: "widget:\(widget.id.uuidString)" as NSString)
            }
            .onDrop(
              of: [UTType.text, UTType.plainText],
              delegate: WidgetInstanceDropDelegate(
                section: section,
                widgets: $widgets,
                currentIndex: index,
                dropIndex: $dropIndex,
                onWidgetsChanged: onWidgetsChanged,
                findWidget: findWidget,
                removeWidget: removeWidget
              )
            )
          }
          DropIndicatorView(isVisible: dropIndex == widgets.count)
        }
      }
    }
    .padding()
    .background(Color.gray.opacity(0.05))
    .cornerRadius(8)
  }

  @ViewBuilder
  private var emptyDropZone: some View {
    Text("Drag widgets here")
      .font(.caption)
      .foregroundColor(.secondary)
      .frame(maxWidth: .infinity)
      .padding()
      .background(Color.gray.opacity(0.1))
      .cornerRadius(4)
      .onDrop(
        of: [UTType.text, UTType.plainText],
        isTargeted: nil,
        perform: { providers in
          if let provider = providers.first {
            provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { data, _ in
              DispatchQueue.main.async {
                if let data = data as? Data, let payload = String(data: data, encoding: .utf8) {
                  handleWidgetDrop(payload: payload)
                } else if let payload = data as? String {
                  handleWidgetDrop(payload: payload)
                }
              }
            }
            return true
          }
          return false
        }
      )
  }

  private func binding(for widget: WidgetInstance) -> Binding<WidgetInstance> {
    Binding(
      get: { widgets.first { $0.id == widget.id } ?? widget },
      set: { newValue in
        if let index = widgets.firstIndex(where: { $0.id == widget.id }) {
          widgets[index] = newValue
        }
      }
    )
  }

  private func handleWidgetDrop(payload: String) {
    // Check if it's a user widget
    if payload.hasPrefix("userWidget:") {
      let indexStr = payload.replacingOccurrences(of: "userWidget:", with: "")
      if let userWidgetIndex = Int(indexStr) {
        let instance = WidgetInstance(
          identifier: .userWidget,
          userWidgetIndex: userWidgetIndex
        )
        widgets.append(instance)
        onWidgetsChanged?()
      }
    } else if let identifier = WidgetIdentifier(rawValue: payload) {
      let instance = WidgetInstance(identifier: identifier)
      widgets.append(instance)
      onWidgetsChanged?()
    }
  }
}

struct WidgetInstanceRowView: View {
  @Binding var widget: WidgetInstance
  let onDelete: () -> Void
  var onChanged: (() -> Void)? = nil

  @EnvironmentObject var settings: SettingsManager

  var body: some View {
    HStack(spacing: 8) {
      // Enabled toggle
      Toggle("", isOn: $widget.enabled)
        .labelsHidden()
        .help("Enable/disable widget")
        .onChange(of: widget.enabled) { _ in
          onChanged?()
        }

      // Widget info
      HStack(spacing: 6) {
        Image(systemName: widgetIcon)
          .font(.system(size: 12))
        Text(widgetDisplayName)
          .font(.caption)
      }
      .frame(width: 120, alignment: .leading)

      Spacer()

      // Delete button
      Button(action: onDelete) {
        Image(systemName: "trash")
          .font(.system(size: 10))
          .foregroundColor(.red)
      }
      .buttonStyle(PlainButtonStyle())
      .help("Remove widget")
    }
    .padding(8)
    .background(Color.gray.opacity(0.1))
    .cornerRadius(4)
  }

  private var widgetDisplayName: String {
    if widget.identifier == .userWidget,
      let index = widget.userWidgetIndex,
      index < settings.draftSettings.userWidgets.count
    {
      return settings.draftSettings.userWidgets[index].name
    }
    return widget.identifier.displayName
  }

  private var widgetIcon: String {
    if widget.identifier == .userWidget,
      let index = widget.userWidgetIndex,
      index < settings.draftSettings.userWidgets.count
    {
      return settings.draftSettings.userWidgets[index].icon
    }
    return widget.identifier.symbolName
  }
}

struct WidgetInstanceDropDelegate: DropDelegate {
  let section: WidgetSection
  @Binding var widgets: [WidgetInstance]
  let currentIndex: Int
  @Binding var dropIndex: Int?
  var onWidgetsChanged: (() -> Void)?
  var findWidget: ((UUID) -> (widget: WidgetInstance, section: WidgetSection)?)? = nil
  var removeWidget: ((UUID, WidgetSection?) -> Void)? = nil

  func performDrop(info: DropInfo) -> Bool {
    let insertAt = currentIndex
    dropIndex = nil

    guard let provider = info.itemProviders(for: [UTType.plainText, UTType.text]).first else {
      return false
    }

    provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { data, _ in
      DispatchQueue.main.async {
        if let data = data as? Data, let string = String(data: data, encoding: .utf8) {
          handlePayload(string, insertAt: insertAt)
        } else if let string = data as? String {
          handlePayload(string, insertAt: insertAt)
        }
      }
    }
    return true
  }

  private func handlePayload(_ payload: String, insertAt: Int) {
    // Check if it's a widget move (from within same section or another section)
    if payload.hasPrefix("widget:") {
      let idStr = payload.replacingOccurrences(of: "widget:", with: "")
      if let id = UUID(uuidString: idStr) {
        // Check if widget is in current section
        if let currentIndex = widgets.firstIndex(where: { $0.id == id }) {
          // Reorder within same section
          withAnimation {
            let moved = widgets.remove(at: currentIndex)
            let toIndex = insertAt > currentIndex ? insertAt - 1 : insertAt
            let safeIndex = min(max(0, toIndex), widgets.count)
            widgets.insert(moved, at: safeIndex)
          }
        } else if let findWidget = findWidget,
                  let (widget, sourceSection) = findWidget(id),
                  let removeWidget = removeWidget {
          // Move from another section
          withAnimation {
            removeWidget(id, sourceSection)
            widgets.insert(widget, at: min(max(0, insertAt), widgets.count))
          }
        }
        onWidgetsChanged?()
        return
      }
    }

    // Check if it's a user widget from the available widgets list
    if payload.hasPrefix("userWidget:") {
      let indexStr = payload.replacingOccurrences(of: "userWidget:", with: "")
      if let userWidgetIndex = Int(indexStr) {
        let instance = WidgetInstance(
          identifier: .userWidget,
          userWidgetIndex: userWidgetIndex
        )
        widgets.insert(instance, at: min(max(0, insertAt), widgets.count))
        onWidgetsChanged?()
        return
      }
    }

    // Standard widget from the available widgets list
    if let identifier = WidgetIdentifier(rawValue: payload) {
      let instance = WidgetInstance(identifier: identifier)
      widgets.insert(instance, at: min(max(0, insertAt), widgets.count))
      onWidgetsChanged?()
    }
  }

  func dropEntered(info: DropInfo) {
    dropIndex = currentIndex
  }

  func dropExited(info: DropInfo) {
    dropIndex = nil
  }
}

struct AvailableWidgetsView: View {
  @EnvironmentObject var settings: SettingsManager

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Available Widgets")
          .font(.headline)

        Spacer()

        Text("Drag to add")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 130))],
        spacing: 10
      ) {
        // Standard widgets
        ForEach(WidgetIdentifier.allCases.filter { $0 != .userWidget }, id: \.self) { identifier in
          DraggableWidgetView(
            identifier: identifier,
            name: identifier.displayName,
            icon: identifier.symbolName,
            color: Color.accentColor
          )
        }

        // User widgets
        ForEach(Array(settings.draftSettings.userWidgets.enumerated()), id: \.offset) {
          index, widget in
          DraggableWidgetView(
            identifier: .userWidget,
            name: widget.name,
            icon: widget.icon,
            color: Color.purple,
            userWidgetIndex: index
          )
        }
      }
    }
  }
}

struct DraggableWidgetView: View {
  let identifier: WidgetIdentifier
  let name: String
  let icon: String
  let color: Color
  var userWidgetIndex: Int? = nil

  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: icon)
        .font(.system(size: 10))
      Text(name)
        .font(.caption)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .frame(maxWidth: .infinity)
    .background(color.opacity(0.1))
    .cornerRadius(4)
    .onDrag {
      let payload: String
      if let index = userWidgetIndex {
        payload = "userWidget:\(index)"
      } else {
        payload = identifier.rawValue
      }
      let provider = NSItemProvider(object: payload as NSString)
      provider.suggestedName = name
      return provider
    }
  }
}

struct DropIndicatorView: View {
  var isVisible: Bool = true

  var body: some View {
    Rectangle()
      .fill(Color.accentColor)
      .frame(height: isVisible ? 3 : 0)
      .cornerRadius(1.5)
      .padding(.horizontal, 2)
      .animation(.easeInOut(duration: 0.2), value: isVisible)
  }
}

/// Profile selector view displayed at the top of LayoutBuilderView
/// This selects which profile to EDIT, not which profile is globally active
struct ProfileSelectorView: View {
  @ObservedObject var profileManager: ProfileManager
  @Binding var editingProfileId: UUID?
  var onProfileSelected: (LayoutProfile) -> Void
  @Binding var showingNewProfileSheet: Bool
  @Binding var showingRenameProfileSheet: Bool
  @Binding var showingDeleteProfileAlert: Bool

  /// The profile currently being edited
  private var editingProfile: LayoutProfile? {
    guard let id = editingProfileId else { return profileManager.activeProfile }
    return profileManager.profile(withId: id)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Edit Profile")
          .font(.subheadline)
          .fontWeight(.semibold)

        Spacer()

        // Profile picker for selecting which profile to edit
        Picker("", selection: Binding(
          get: { editingProfileId },
          set: { newValue in
            if newValue == nil {
              // "Create new profile" selected
              showingNewProfileSheet = true
            } else if let id = newValue, let profile = profileManager.profile(withId: id) {
              editingProfileId = id
              onProfileSelected(profile)
            }
          }
        )) {
          // Create new profile option
          Text("Create a new profile")
            .tag(nil as UUID?)

          Divider()

          // Existing profiles
          ForEach(profileManager.profiles) { profile in
            HStack {
              Text(profile.name)
              if profile.id == profileManager.activeProfileId {
                Text("(Active)")
              }
              if profile.isDefault {
                Text("• Default")
              }
            }
            .tag(profile.id as UUID?)
          }
        }
        .pickerStyle(.menu)
        .frame(width: 220)
      }

      // Info and actions
      if let profile = editingProfile {
        HStack(spacing: 12) {
          if profile.id == profileManager.activeProfileId {
            Label("Currently active", systemImage: "checkmark.circle.fill")
              .font(.caption)
              .foregroundColor(.green)
          } else {
            Button(action: {
              _ = profileManager.switchToProfile(id: profile.id)
            }) {
              Label("Make active", systemImage: "power")
                .font(.caption)
            }
            .buttonStyle(.borderless)
          }

          Spacer()

          Button(action: { showingRenameProfileSheet = true }) {
            Label("Rename", systemImage: "pencil")
              .font(.caption)
          }
          .buttonStyle(.borderless)

          Button(action: {
            if let newProfile = profileManager.duplicateProfile(id: profile.id) {
              editingProfileId = newProfile.id
              onProfileSelected(newProfile)
            }
          }) {
            Label("Duplicate", systemImage: "doc.on.doc")
              .font(.caption)
          }
          .buttonStyle(.borderless)

          if !profile.isDefault {
            Button(action: { showingDeleteProfileAlert = true }) {
              Label("Delete", systemImage: "trash")
                .font(.caption)
                .foregroundColor(.red)
            }
            .buttonStyle(.borderless)
          }
        }
      }
    }
    .padding()
    .background(Color.gray.opacity(0.05))
    .cornerRadius(8)
  }
}

/// Sheet for creating a new profile
struct NewProfileSheet: View {
  @ObservedObject var profileManager: ProfileManager
  @Binding var editingProfileId: UUID?
  var onCreated: ((LayoutProfile) -> Void)?

  @Environment(\.dismiss) private var dismiss
  @State private var profileName = ""
  @State private var copyFromCurrent = true

  private var isNameValid: Bool {
    !profileName.trimmingCharacters(in: .whitespaces).isEmpty
  }

  private var isNameUnique: Bool {
    !profileManager.profiles.contains { $0.name.lowercased() == profileName.lowercased() }
  }

  /// The profile to copy from (the one being edited)
  private var sourceProfile: LayoutProfile? {
    guard let id = editingProfileId else { return profileManager.activeProfile }
    return profileManager.profile(withId: id)
  }

  var body: some View {
    VStack(spacing: 20) {
      Text("Create New Profile")
        .font(.headline)

      Form {
        TextField("Profile Name", text: $profileName)
          .textFieldStyle(.roundedBorder)

        if !isNameUnique && !profileName.isEmpty {
          Text("A profile with this name already exists")
            .font(.caption)
            .foregroundColor(.red)
        }

        Toggle("Copy layout from \"\(sourceProfile?.name ?? "current")\"", isOn: $copyFromCurrent)
      }
      .padding()

      HStack {
        Button("Cancel") {
          dismiss()
        }
        .keyboardShortcut(.cancelAction)

        Spacer()

        Button("Create") {
          let layout: MultiDisplayLayout? =
            copyFromCurrent ? sourceProfile?.multiDisplayLayout : nil
          let newProfile = profileManager.createProfile(
            name: profileName.trimmingCharacters(in: .whitespaces),
            layout: layout
          )
          onCreated?(newProfile)
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
        .buttonStyle(.borderedProminent)
        .disabled(!isNameValid || !isNameUnique)
      }
      .padding()
    }
    .frame(width: 400, height: 220)
    .onAppear {
      profileName = "Profile \(profileManager.profiles.count + 1)"
    }
  }
}

/// Sheet for renaming an existing profile
struct RenameProfileSheet: View {
  @ObservedObject var profileManager: ProfileManager
  var editingProfileId: UUID?

  @Environment(\.dismiss) private var dismiss
  @State private var newName = ""

  private var editingProfile: LayoutProfile? {
    guard let id = editingProfileId else { return nil }
    return profileManager.profile(withId: id)
  }

  private var isNameValid: Bool {
    !newName.trimmingCharacters(in: .whitespaces).isEmpty
  }

  private var isNameUnique: Bool {
    let trimmedName = newName.trimmingCharacters(in: .whitespaces).lowercased()
    let currentName = editingProfile?.name.lowercased() ?? ""
    return trimmedName == currentName
      || !profileManager.profiles.contains { $0.name.lowercased() == trimmedName }
  }

  var body: some View {
    VStack(spacing: 20) {
      Text("Rename Profile")
        .font(.headline)

      Form {
        TextField("Profile Name", text: $newName)
          .textFieldStyle(.roundedBorder)

        if !isNameUnique && !newName.isEmpty {
          Text("A profile with this name already exists")
            .font(.caption)
            .foregroundColor(.red)
        }
      }
      .padding()

      HStack {
        Button("Cancel") {
          dismiss()
        }
        .keyboardShortcut(.cancelAction)

        Spacer()

        Button("Rename") {
          if let id = editingProfileId {
            _ = profileManager.renameProfile(
              id: id,
              newName: newName.trimmingCharacters(in: .whitespaces)
            )
          }
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
        .buttonStyle(.borderedProminent)
        .disabled(!isNameValid || !isNameUnique)
      }
      .padding()
    }
    .frame(width: 400, height: 180)
    .onAppear {
      newName = editingProfile?.name ?? ""
    }
  }
}
