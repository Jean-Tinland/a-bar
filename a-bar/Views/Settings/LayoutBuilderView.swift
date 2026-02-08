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
          settings.draftLayout = profile.multiDisplayLayout
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
        settings.draftLayout = profile.multiDisplayLayout
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
          settings.draftLayout = profile.multiDisplayLayout
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
            settings.draftLayout = profile.multiDisplayLayout
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

          if config.leftBar != nil {
            Label("Left", systemImage: "rectangle.leadingthird.inset.filled")
              .font(.caption2)
              .foregroundColor(.orange)
          }

          if config.rightBar != nil {
            Label("Right", systemImage: "rectangle.trailingthird.inset.filled")
              .font(.caption2)
              .foregroundColor(.purple)
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
            // Horizontal bars
            Text("Horizontal Bars")
              .font(.subheadline)
              .fontWeight(.semibold)
              .foregroundColor(.secondary)
              .frame(maxWidth: .infinity, alignment: .leading)

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

            Divider()

            // Vertical bars
            Text("Vertical Bars")
              .font(.subheadline)
              .fontWeight(.semibold)
              .foregroundColor(.secondary)
              .frame(maxWidth: .infinity, alignment: .leading)

            BarConfigurationRow(
              title: "Left Bar",
              position: .left,
              barLayout: displayConfig.leftBar,
              onToggle: { toggleBar(.left) },
              onEdit: { editingBarPosition = .left }
            )

            BarConfigurationRow(
              title: "Right Bar",
              position: .right,
              barLayout: displayConfig.rightBar,
              onToggle: { toggleBar(.right) },
              onEdit: { editingBarPosition = .right }
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
    case .left:
      if config.leftBar == nil {
        config.leftBar = SingleBarLayout()
      } else {
        config.leftBar = nil
      }
    case .right:
      if config.rightBar == nil {
        config.rightBar = SingleBarLayout()
      } else {
        config.rightBar = nil
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

      // Middle row with left bar, screen area, right bar
      HStack(spacing: 0) {
        // Left bar indicator
        if config.leftBar != nil {
          Rectangle()
            .fill(Color.orange.opacity(0.3))
            .frame(width: 30)
            .overlay(
              Text("L")
                .font(.caption2)
                .foregroundColor(.orange)
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

        // Right bar indicator
        if config.rightBar != nil {
          Rectangle()
            .fill(Color.purple.opacity(0.3))
            .frame(width: 30)
            .overlay(
              Text("R")
                .font(.caption2)
                .foregroundColor(.purple)
            )
        }
      }

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

  private var iconName: String {
    switch position {
    case .top: return "rectangle.topthird.inset.filled"
    case .bottom: return "rectangle.bottomthird.inset.filled"
    case .left: return "rectangle.leadingthird.inset.filled"
    case .right: return "rectangle.trailingthird.inset.filled"
    }
  }

  private var iconColor: Color {
    switch position {
    case .top: return .green
    case .bottom: return .blue
    case .left: return .orange
    case .right: return .purple
    }
  }

  var body: some View {
    HStack(spacing: 12) {
      // Icon
      Image(systemName: iconName)
      .font(.system(size: 20))
      .foregroundColor(isEnabled ? iconColor : .secondary)
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

  /// Section labels based on bar orientation
  private var firstSectionTitle: String {
    position.sectionDisplayName(for: .left)
  }

  private var middleSectionTitle: String {
    position.sectionDisplayName(for: .center)
  }

  private var lastSectionTitle: String {
    position.sectionDisplayName(for: .right)
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

      ScrollView {
        VStack(spacing: 20) {
          Text("Drag widgets to sections below. Widgets can appear multiple times.")
            .font(.subheadline)
            .foregroundColor(.secondary)

          if position.isVertical {
            Text("Vertical bar: sections flow from top to bottom")
              .font(.caption)
              .foregroundColor(.secondary)
          }

          // Bar sections
          VStack(spacing: 16) {
            WidgetSectionView(
              title: firstSectionTitle,
              widgets: $leftWidgets,
              onWidgetsChanged: saveLayout
            )

            WidgetSectionView(
              title: middleSectionTitle,
              widgets: $centerWidgets,
              onWidgetsChanged: saveLayout
            )

            WidgetSectionView(
              title: lastSectionTitle,
              widgets: $rightWidgets,
              onWidgetsChanged: saveLayout
            )
          }

          Divider()

          // Available widgets
          AvailableWidgetsView()
        }
        .padding()
      }
    }
    .frame(width: 650, height: 600)
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
      case .left:
        displayConfig.leftBar = layout
      case .right:
        displayConfig.rightBar = layout
      }

      settings.draftLayout.setConfiguration(
        displayConfig, forDisplay: displayIndex)
    }
  }
}

struct WidgetSectionView: View {
  let title: String
  @Binding var widgets: [WidgetInstance]
  var onWidgetsChanged: (() -> Void)? = nil

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
              NSItemProvider(object: "reorder:\(index)" as NSString)
            }
            .onDrop(
              of: [UTType.text, UTType.plainText],
              delegate: WidgetInstanceDropDelegate(
                widgets: $widgets,
                currentIndex: index,
                dropIndex: $dropIndex,
                onWidgetsChanged: onWidgetsChanged
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
  @Binding var widgets: [WidgetInstance]
  let currentIndex: Int
  @Binding var dropIndex: Int?
  var onWidgetsChanged: (() -> Void)?

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
    // Check if it's a reorder
    if payload.hasPrefix("reorder:") {
      let indexStr = payload.replacingOccurrences(of: "reorder:", with: "")
      if let fromIndex = Int(indexStr), widgets.indices.contains(fromIndex) {
        withAnimation {
          let moved = widgets.remove(at: fromIndex)
          let toIndex = insertAt > fromIndex ? insertAt - 1 : insertAt
          let safeIndex = min(max(0, toIndex), widgets.count)
          widgets.insert(moved, at: safeIndex)
        }
        onWidgetsChanged?()
        return
      }
    }

    // Check if it's a user widget
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

    // Standard widget
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

        Text("Drag to add (can add multiple times)")
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

// MARK: - Profile Views

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