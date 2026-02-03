import SwiftUI
import UniformTypeIdentifiers

/// Main entry point for the layout builder - shows list of configured displays
struct LayoutBuilderView: View {
  @EnvironmentObject var settings: SettingsManager

  @State private var selectedDisplayWrapper: DisplayIndexWrapper? = nil
  @State private var showingAddDisplaySheet = false

  private var layout: MultiDisplayLayout {
    settings.draftSettings.multiDisplayLayout
  }

  private var connectedScreenCount: Int {
    NSScreen.screens.count
  }

  var body: some View {
    VStack(spacing: 20) {
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

        if layout.displays.isEmpty {
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
            ForEach(layout.displays) { displayConfig in
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
          settings.draftSettings.multiDisplayLayout = .defaultLayout
        }
        .foregroundColor(.red)

        Spacer()
      }
    }
    .padding()
    .sheet(isPresented: $showingAddDisplaySheet) {
      AddDisplaySheet(
        existingIndices: Set(layout.displays.map { $0.displayIndex }),
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
  }

  private func addDisplay(index: Int, name: String) {
    let config = DisplayConfiguration(
      displayIndex: index,
      name: name,
      topBar: nil,
      bottomBar: nil
    )
    settings.draftSettings.multiDisplayLayout.setConfiguration(config, forDisplay: index)
  }

  private func removeDisplay(_ index: Int) {
    settings.draftSettings.multiDisplayLayout.removeConfiguration(forDisplay: index)
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
    settings.draftSettings.multiDisplayLayout.configuration(forDisplay: displayIndex)
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
    settings.draftSettings.multiDisplayLayout.setConfiguration(config, forDisplay: displayIndex)
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
    settings.draftSettings.multiDisplayLayout.setConfiguration(config, forDisplay: displayIndex)
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
    settings.draftSettings.multiDisplayLayout.barLayout(
      forDisplay: displayIndex, position: position)
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

          // Bar sections
          VStack(spacing: 16) {
            WidgetSectionView(
              title: "Left",
              widgets: $leftWidgets,
              onWidgetsChanged: saveLayout
            )

            WidgetSectionView(
              title: "Center",
              widgets: $centerWidgets,
              onWidgetsChanged: saveLayout
            )

            WidgetSectionView(
              title: "Right",
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
        settings.draftSettings.multiDisplayLayout.configuration(forDisplay: displayIndex)
        ?? DisplayConfiguration(displayIndex: displayIndex, name: "Display \(displayIndex + 1)")

      switch position {
      case .top:
        displayConfig.topBar = layout
      case .bottom:
        displayConfig.bottomBar = layout
      }

      settings.draftSettings.multiDisplayLayout.setConfiguration(
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