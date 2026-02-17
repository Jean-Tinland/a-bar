import AppKit
import ApplicationServices
import Combine
import SwiftUI

/// Reusable color picker component for theme colors
struct ThemeColorPicker: View {
  let label: String
  @Binding var selectedColor: ThemeColor
  @EnvironmentObject var settings: SettingsManager

  private var theme: ABarTheme {
    ThemeManager.currentTheme(for: settings.draftSettings.theme)
  }

  var body: some View {
    HStack(spacing: 4) {
      Text(label)
      Picker("", selection: $selectedColor) {
        ForEach(ThemeColor.allCases) { color in
          HStack {
            Circle()
              .fill(color.color(from: theme))
              .frame(width: 12, height: 12)
            Text(color.displayName)
          }
          .tag(color)
        }
      }
      .pickerStyle(MenuPickerStyle())
      .labelsHidden()
    }
  }
}

struct YabaiSettingsView: View {
  @EnvironmentObject var settings: SettingsManager

  var body: some View {
    Form {
      VStack(alignment: .leading, spacing: 16) {
        Section {
          Toggle("Hide empty spaces", isOn: binding(\.widgets.spaces.hideEmptySpaces))
          Toggle(
            "Display sticky windows separately",
            isOn: binding(\.widgets.spaces.displayStickyWindowsSeparately))
          Toggle("Hide duplicate apps", isOn: binding(\.widgets.spaces.hideDuplicateApps))
          Toggle(
            "Show all spaces on all screens",
            isOn: binding(\.widgets.spaces.showAllSpacesOnAllScreens))

          Divider()

          VStack(alignment: .leading) {
            Text("Excluded spaces")
            TextField(
              "Space indices (comma-separated)",
              text: binding(\.widgets.spaces.exclusions)
            )
            .textFieldStyle(RoundedBorderTextFieldStyle())
          }

          VStack(alignment: .leading) {
            Text("Title exclusions")
            TextField(
              "Window title patterns (comma-separated)",
              text: binding(\.widgets.spaces.titleExclusions)
            )
            .textFieldStyle(RoundedBorderTextFieldStyle())
          }

          Toggle(
            "Use regex for exclusions",
            isOn: binding(\.widgets.spaces.exclusionsAsRegex))
          Toggle(
            "Hide 'Add space' button",
            isOn: binding(\.widgets.spaces.hideCreateSpaceButton))
          Toggle(
            "Switch spaces without Yabai",
            isOn: binding(\.widgets.spaces.switchSpacesWithoutYabai))
        }
      }
      .padding()
    }
    .navigationTitle("Yabai")
  }

  private func binding<T>(_ keyPath: WritableKeyPath<ABarSettings, T>) -> Binding<T> {
    Binding(
      get: { settings.draftSettings[keyPath: keyPath] },
      set: { settings.draftSettings[keyPath: keyPath] = $0 }
    )
  }
}

struct AerospaceSettingsView: View {
  @EnvironmentObject var settings: SettingsManager

  var body: some View {
    Form {
      VStack(alignment: .leading, spacing: 16) {
        Section {
          Text("AeroSpace spaces & process widgets share the same settings as yabai ones (exclusions, hide empty spaces, etc.). Configure them in the \"Yabai\" and \"Process\" tabs.")
            .font(.subheadline)
            .foregroundColor(.secondary)
            .padding(.bottom, 8)

          Text("AeroSpace uses named workspaces (e.g., \"1\", \"2\", \"web\") instead of indexed spaces. The spaces widget will display workspace names and the apps running on each.")
            .font(.subheadline)
            .foregroundColor(.secondary)
            .padding(.bottom, 8)

          VStack(alignment: .leading, spacing: 8) {
            Text("Tip").font(.headline)
            Text("To use AeroSpace, add the \"Spaces (AeroSpace)\" and \"Process (AeroSpace)\" widgets to your layout using the Layout Builder. Make sure to set the window manager to \"AeroSpace\" in the General tab.")
              .font(.subheadline)
              .foregroundColor(.secondary)
          }
        }
      }
      .padding()
    }
    .navigationTitle("AeroSpace")
  }
}

struct ProcessSettingsView: View {
  @EnvironmentObject var settings: SettingsManager

  var body: some View {
    Form {
      VStack(alignment: .leading, spacing: 16) {
        Section {
          VStack(alignment: .leading, spacing: 12) {
            Toggle("Hide window title", isOn: binding(\.widgets.process.hideWindowTitle))
            Toggle("Display only icon", isOn: binding(\.widgets.process.displayOnlyIcon))
            Toggle("Show layout type indicator", isOn: binding(\.widgets.process.showLayoutMode))
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      .padding()
    }
    .navigationTitle("Process")
  }

  private func binding<T>(_ keyPath: WritableKeyPath<ABarSettings, T>) -> Binding<T> {
    Binding(
      get: { settings.draftSettings[keyPath: keyPath] },
      set: { settings.draftSettings[keyPath: keyPath] = $0 }
    )
  }
}

struct BatterySettingsView: View {
  @EnvironmentObject var settings: SettingsManager

  var body: some View {
    Form {
      VStack(alignment: .leading, spacing: 16) {
        Section {
          Toggle("Show icon", isOn: binding(\.widgets.battery.showIcon))

          Toggle(
            "Toggle caffeinate on click",
            isOn: binding(\.widgets.battery.toggleCaffeinateOnClick))

          VStack(alignment: .leading) {
            Text("Caffeinate option")
            Picker("", selection: caffeinateOptionBinding) {
              Text("Prevent display sleep (-d)").tag(
                BatteryWidgetSettings.CaffeinateOption.displaySleep)
              Text("Prevent system sleep (-i)").tag(
                BatteryWidgetSettings.CaffeinateOption.systemSleep)
              Text("Prevent disk sleep (-m)").tag(
                BatteryWidgetSettings.CaffeinateOption.diskSleep)
              Text("Prevent all sleep (-disu)").tag(
                BatteryWidgetSettings.CaffeinateOption.all)
            }
            .pickerStyle(MenuPickerStyle())
            .labelsHidden()
          }
          .frame(maxWidth: .infinity, alignment: .leading)

          Divider()

          ThemeColorPicker(
            label: "Background color",
            selectedColor: Binding(
              get: { settings.draftSettings.widgets.battery.backgroundColor },
              set: { settings.draftSettings.widgets.battery.backgroundColor = $0 }
            )
          )
        }
      }
      .padding()
    }
    .navigationTitle("Battery")
  }

  private var caffeinateOptionBinding: Binding<BatteryWidgetSettings.CaffeinateOption> {
    Binding(
      get: {
        BatteryWidgetSettings.CaffeinateOption(
          rawValue: settings.draftSettings.widgets.battery.caffeinateOption) ?? .systemSleep
      },
      set: { settings.draftSettings.widgets.battery.caffeinateOption = $0.rawValue }
    )
  }

  private func binding<T>(_ keyPath: WritableKeyPath<ABarSettings, T>) -> Binding<T> {
    Binding(
      get: { settings.draftSettings[keyPath: keyPath] },
      set: { settings.draftSettings[keyPath: keyPath] = $0 }
    )
  }
}

struct WeatherSettingsView: View {
  @EnvironmentObject var settings: SettingsManager

  var body: some View {
    Form {
      VStack(alignment: .leading, spacing: 16) {
        Section {
          Toggle("Show icon", isOn: binding(\.widgets.weather.showIcon))
          Toggle("Hide location", isOn: binding(\.widgets.weather.hideLocation))

          VStack(alignment: .leading) {
            Text("Custom location")
            TextField(
              "City or ZIP code (leave empty for auto)",
              text: binding(\.widgets.weather.customLocation)
            )
            .textFieldStyle(RoundedBorderTextFieldStyle())
          }

          VStack(alignment: .leading) {
            Text("Temperature unit")
            Picker("", selection: unitBinding) {
              Text("Celsius").tag(WeatherWidgetSettings.TemperatureUnit.celsius)
              Text("Fahrenheit").tag(WeatherWidgetSettings.TemperatureUnit.fahrenheit)
            }
            .pickerStyle(SegmentedPickerStyle())
            .labelsHidden()
          }

          HStack(spacing: 4) {
            Text("Refresh interval")
            TextField(
              "", value: binding(\.widgets.weather.refreshInterval),
              formatter: NumberFormatter()
            )
            .frame(width: 60)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            Text("seconds")
          }
        }
      }
      .padding()
    }
    .navigationTitle("Weather")
  }

  private var unitBinding: Binding<WeatherWidgetSettings.TemperatureUnit> {
    Binding(
      get: {
        settings.draftSettings.widgets.weather.unit
      },
      set: { settings.draftSettings.widgets.weather.unit = $0 }
    )
  }

  private func binding<T>(_ keyPath: WritableKeyPath<ABarSettings, T>) -> Binding<T> {
    Binding(
      get: { settings.draftSettings[keyPath: keyPath] },
      set: { settings.draftSettings[keyPath: keyPath] = $0 }
    )
  }
}

struct DateTimeSettingsView: View {
  @EnvironmentObject var settings: SettingsManager

  var body: some View {
    Form {
      VStack(alignment: .leading, spacing: 16) {
        // Time
        Section {
          Text("Time").font(.headline)
          Toggle("Show icon", isOn: binding(\.widgets.time.showIcon))
          Toggle("12-hour format", isOn: binding(\.widgets.time.hour12))
          Toggle("Show seconds", isOn: binding(\.widgets.time.showSeconds))
          Toggle("Show day progress", isOn: binding(\.widgets.time.showDayProgress))

          ThemeColorPicker(
            label: "Background color",
            selectedColor: Binding(
              get: { settings.draftSettings.widgets.time.backgroundColor },
              set: { settings.draftSettings.widgets.time.backgroundColor = $0 }
            )
          )
        }

        Divider()

        // Date
        Section {
          Text("Date").font(.headline)
          Toggle("Show icon", isOn: binding(\.widgets.date.showIcon))
          Toggle("Short format", isOn: binding(\.widgets.date.shortFormat))

          VStack(alignment: .leading) {
            Text("Locale")
            TextField("e.g., en_US", text: binding(\.widgets.date.locale))
              .textFieldStyle(RoundedBorderTextFieldStyle())
          }

          VStack(alignment: .leading) {
            Text("Calendar app")
            TextField("App name or path", text: binding(\.widgets.date.calendarApp))
              .textFieldStyle(RoundedBorderTextFieldStyle())
          }

          ThemeColorPicker(
            label: "Background color",
            selectedColor: Binding(
              get: { settings.draftSettings.widgets.date.backgroundColor },
              set: { settings.draftSettings.widgets.date.backgroundColor = $0 }
            )
          )
        }
      }
      .padding()
    }
    .navigationTitle("Date & Time")
  }

  private func binding<T>(_ keyPath: WritableKeyPath<ABarSettings, T>) -> Binding<T> {
    Binding(
      get: { settings.draftSettings[keyPath: keyPath] },
      set: { settings.draftSettings[keyPath: keyPath] = $0 }
    )
  }
}

struct NetworkSettingsView: View {
  @EnvironmentObject var settings: SettingsManager

  var body: some View {
    Form {
      VStack(alignment: .leading, spacing: 16) {
        // WiFi
        Section {
          Text("WiFi").font(.headline)
          Toggle("Show icon", isOn: binding(\.widgets.wifi.showIcon))
          Toggle("Toggle WiFi on click", isOn: binding(\.widgets.wifi.toggleOnClick))
          Toggle("Hide network name", isOn: binding(\.widgets.wifi.hideNetworkName))
          Toggle("Hide when disabled", isOn: binding(\.widgets.wifi.hideWhenDisabled))

          VStack(alignment: .leading) {
            Text("Network device")
            TextField("e.g., en0", text: binding(\.widgets.wifi.networkDevice))
              .textFieldStyle(RoundedBorderTextFieldStyle())
          }

          ThemeColorPicker(
            label: "Background color",
            selectedColor: Binding(
              get: { settings.draftSettings.widgets.wifi.backgroundColor },
              set: { settings.draftSettings.widgets.wifi.backgroundColor = $0 }
            )
          )
        }
      }
      .padding()
    }
    .navigationTitle("Network")
  }

  private func binding<T>(_ keyPath: WritableKeyPath<ABarSettings, T>) -> Binding<T> {
    Binding(
      get: { settings.draftSettings[keyPath: keyPath] },
      set: { settings.draftSettings[keyPath: keyPath] = $0 }
    )
  }
}

struct AudioSettingsView: View {
  @EnvironmentObject var settings: SettingsManager

  var body: some View {
    Form {
      VStack(alignment: .leading, spacing: 16) {
        // Sound
        Section {
          Text("Sound").font(.headline)
          Toggle("Show icon", isOn: binding(\.widgets.sound.showIcon))

          HStack(spacing: 4) {
            Text("Refresh interval")
            TextField(
              "", value: binding(\.widgets.sound.refreshInterval), formatter: NumberFormatter()
            )
            .frame(width: 60)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            Text("seconds")
          }

          ThemeColorPicker(
            label: "Background color",
            selectedColor: Binding(
              get: { settings.draftSettings.widgets.sound.backgroundColor },
              set: { settings.draftSettings.widgets.sound.backgroundColor = $0 }
            )
          )
        }

        Divider()

        // Mic
        Section {
          Text("Microphone").font(.headline)
          Toggle("Show icon", isOn: binding(\.widgets.mic.showIcon))

          HStack(spacing: 4) {
            Text("Refresh interval")
            TextField(
              "", value: binding(\.widgets.mic.refreshInterval), formatter: NumberFormatter()
            )
            .frame(width: 60)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            Text("seconds")
          }

          ThemeColorPicker(
            label: "Background color",
            selectedColor: Binding(
              get: { settings.draftSettings.widgets.mic.backgroundColor },
              set: { settings.draftSettings.widgets.mic.backgroundColor = $0 }
            )
          )
        }

        Divider()

        // Keyboard
        Section {
          Text("Keyboard").font(.headline)
          Toggle("Show icon", isOn: binding(\.widgets.keyboard.showIcon))

          HStack(spacing: 4) {
            Text("Refresh interval")
            TextField(
              "", value: binding(\.widgets.keyboard.refreshInterval), formatter: NumberFormatter()
            )
            .frame(width: 60)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            Text("seconds")
          }

          ThemeColorPicker(
            label: "Background color",
            selectedColor: Binding(
              get: { settings.draftSettings.widgets.keyboard.backgroundColor },
              set: { settings.draftSettings.widgets.keyboard.backgroundColor = $0 }
            )
          )
        }
      }
      .padding()
    }
    .navigationTitle("Input / Output")
  }

  private func binding<T>(_ keyPath: WritableKeyPath<ABarSettings, T>) -> Binding<T> {
    Binding(
      get: { settings.draftSettings[keyPath: keyPath] },
      set: { settings.draftSettings[keyPath: keyPath] = $0 }
    )
  }
}

struct SystemStatsSettingsView: View {
  @EnvironmentObject var settings: SettingsManager

  var body: some View {
    Form {
      VStack(alignment: .leading, spacing: 16) {
        // CPU
        Section {
          Text("CPU").font(.headline)
          Toggle("Show icon", isOn: binding(\.widgets.cpu.showIcon))

          HStack(spacing: 4) {
            Text("Refresh interval")
            TextField(
              "", value: binding(\.widgets.cpu.refreshInterval), formatter: NumberFormatter()
            )
            .frame(width: 60)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            Text("seconds")
          }

          HStack(spacing: 4) {
            Text("Monitor app")
            Picker("", selection: cpuMonitorAppBinding) {
              ForEach(CPUWidgetSettings.MonitorApp.allCases, id: \.self) { app in
                Text(app.rawValue).tag(app)
              }
            }
            .pickerStyle(MenuPickerStyle())
            .frame(width: 180)
          }

          ThemeColorPicker(
            label: "Graph color",
            selectedColor: Binding(
              get: { settings.draftSettings.widgets.cpu.graphColor },
              set: { settings.draftSettings.widgets.cpu.graphColor = $0 }
            )
          )
        }

        Divider()

        // Memory
        Section {
          Text("Memory").font(.headline)

          HStack(spacing: 4) {
            Text("Refresh interval")
            TextField(
              "", value: binding(\.widgets.memory.refreshInterval), formatter: NumberFormatter()
            )
            .frame(width: 60)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            Text("seconds")
          }

          HStack(spacing: 4) {
            Text("Monitor app")
            Picker("", selection: memoryMonitorAppBinding) {
              ForEach(CPUWidgetSettings.MonitorApp.allCases, id: \.self) { app in
                Text(app.rawValue).tag(app)
              }
            }
            .pickerStyle(MenuPickerStyle())
            .frame(width: 180)
          }
        }

        Divider()

        // GPU
        Section {
          Text("GPU").font(.headline)
          Toggle("Show icon", isOn: binding(\.widgets.gpu.showIcon))

          HStack(spacing: 4) {
            Text("Refresh interval")
            TextField(
              "", value: binding(\.widgets.gpu.refreshInterval), formatter: NumberFormatter()
            )
            .frame(width: 60)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            Text("seconds")
          }

          ThemeColorPicker(
            label: "Graph color",
            selectedColor: Binding(
              get: { settings.draftSettings.widgets.gpu.graphColor },
              set: { settings.draftSettings.widgets.gpu.graphColor = $0 }
            )
          )
        }

        Divider()

        // Storage
        Section {
          Text("Storage").font(.headline)

          HStack(spacing: 4) {
            Text("Refresh interval")
            TextField(
              "", value: binding(\.widgets.storage.refreshInterval), formatter: NumberFormatter()
            )
            .frame(width: 60)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            Text("seconds")
          }
        }

        Divider()

        // Network Stats
        Section {
          Text("Network Stats").font(.headline)
          Toggle("Show icon", isOn: binding(\.widgets.netstats.showIcon))

          HStack(spacing: 4) {
            Text("Refresh interval")
            TextField(
              "", value: binding(\.widgets.netstats.refreshInterval), formatter: NumberFormatter()
            )
            .frame(width: 60)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            Text("seconds")
          }

          ThemeColorPicker(
            label: "Download graph color",
            selectedColor: Binding(
              get: { settings.draftSettings.widgets.netstats.downloadColor },
              set: { settings.draftSettings.widgets.netstats.downloadColor = $0 }
            )
          )

          ThemeColorPicker(
            label: "Upload graph color",
            selectedColor: Binding(
              get: { settings.draftSettings.widgets.netstats.uploadColor },
              set: { settings.draftSettings.widgets.netstats.uploadColor = $0 }
            )
          )
        }

        Divider()

        // Disk Activity
        Section {
          Text("Disk Activity").font(.headline)
          Toggle("Show icon", isOn: binding(\.widgets.diskActivity.showIcon))

          HStack(spacing: 4) {
            Text("Refresh interval")
            TextField(
              "", value: binding(\.widgets.diskActivity.refreshInterval), formatter: NumberFormatter()
            )
            .frame(width: 60)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            Text("seconds")
          }

          ThemeColorPicker(
            label: "Read graph color",
            selectedColor: Binding(
              get: { settings.draftSettings.widgets.diskActivity.readColor },
              set: { settings.draftSettings.widgets.diskActivity.readColor = $0 }
            )
          )

          ThemeColorPicker(
            label: "Write graph color",
            selectedColor: Binding(
              get: { settings.draftSettings.widgets.diskActivity.writeColor },
              set: { settings.draftSettings.widgets.diskActivity.writeColor = $0 }
            )
          )
        }
      }
      .padding()
    }
    .navigationTitle("System Stats")
  }

  private var cpuMonitorAppBinding: Binding<CPUWidgetSettings.MonitorApp> {
    Binding(
      get: { settings.draftSettings.widgets.cpu.monitorApp },
      set: { settings.draftSettings.widgets.cpu.monitorApp = $0 }
    )
  }

  private var memoryMonitorAppBinding: Binding<CPUWidgetSettings.MonitorApp> {
    Binding(
      get: { settings.draftSettings.widgets.memory.monitorApp },
      set: { settings.draftSettings.widgets.memory.monitorApp = $0 }
    )
  }

  private func binding<T>(_ keyPath: WritableKeyPath<ABarSettings, T>) -> Binding<T> {
    Binding(
      get: { settings.draftSettings[keyPath: keyPath] },
      set: { settings.draftSettings[keyPath: keyPath] = $0 }
    )
  }
}

struct GitHubSettingsView: View {
  @EnvironmentObject var settings: SettingsManager

  var body: some View {
    Form {
      VStack(alignment: .leading, spacing: 16) {
        Section {
          Toggle("Show icon", isOn: binding(\.widgets.github.showIcon))

          VStack(alignment: .leading) {
            Text("GitHub CLI path")
            TextField("Path to gh binary", text: binding(\.widgets.github.ghBinaryPath))
              .textFieldStyle(RoundedBorderTextFieldStyle())
          }

          VStack(alignment: .leading) {
            Text("Notifications URL")
            TextField("URL to open", text: binding(\.widgets.github.notificationUrl))
              .textFieldStyle(RoundedBorderTextFieldStyle())
          }

          Toggle(
            "Hide when no notifications",
            isOn: binding(\.widgets.github.hideWhenNoNotifications))

          HStack(spacing: 4) {
            Text("Refresh interval")
            TextField(
              "", value: binding(\.widgets.github.refreshInterval),
              formatter: NumberFormatter()
            )
            .frame(width: 60)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            Text("seconds")
          }
        }
      }
      .padding()
    }
    .navigationTitle("GitHub")
  }

  private func binding<T>(_ keyPath: WritableKeyPath<ABarSettings, T>) -> Binding<T> {
    Binding(
      get: { settings.draftSettings[keyPath: keyPath] },
      set: { settings.draftSettings[keyPath: keyPath] = $0 }
    )
  }
}

struct HackerNewsSettingsView: View {
  @EnvironmentObject var settings: SettingsManager

  var body: some View {
    Form {
      VStack(alignment: .leading, spacing: 16) {
        Section {
          Toggle("Show icon", isOn: binding(\.widgets.hackerNews.showIcon))

          Toggle("Show points", isOn: binding(\.widgets.hackerNews.showPoints))

          HStack(spacing: 4) {
            Text("Max title length")
            TextField(
              "", value: binding(\.widgets.hackerNews.maxTitleLength),
              formatter: NumberFormatter()
            )
            .frame(width: 60)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            Text("characters")
          }

          HStack(spacing: 4) {
            Text("Refresh interval")
            TextField(
              "", value: binding(\.widgets.hackerNews.refreshInterval),
              formatter: NumberFormatter()
            )
            .frame(width: 60)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            Text("seconds")
          }

          HStack(spacing: 4) {
            Text("Rotation interval")
            TextField(
              "", value: binding(\.widgets.hackerNews.rotationInterval),
              formatter: NumberFormatter()
            )
            .frame(width: 60)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            Text("seconds")
          }

          Text("Stories rotate automatically and clicking opens them in your browser")
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }
      .padding()
    }
    .navigationTitle("Hacker News")
  }

  private func binding<T>(_ keyPath: WritableKeyPath<ABarSettings, T>) -> Binding<T> {
    Binding(
      get: { settings.draftSettings[keyPath: keyPath] },
      set: { settings.draftSettings[keyPath: keyPath] = $0 }
    )
  }
}

struct CustomWidgetSettingsView: View {
  @EnvironmentObject var settings: SettingsManager

  @State private var showAddSheet = false
  @State private var editingWidget: UserWidgetDefinition?
  @State private var refreshID = UUID()

  var body: some View {
    let widgets = settings.draftSettings.userWidgets

    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text("Custom Widgets")
          .font(.headline)

        Spacer()

        Button(action: {
          showAddSheet = true
        }) {
          HStack(spacing: 4) {
            Image(systemName: "plus")
            Text("Add a custom widget")
          }
        }
      }

      Group {
        if widgets.isEmpty {
          Text("No custom widgets configured.")
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding()
        } else {
          List {
            ForEach(widgets) { widget in
              HStack {
                Image(systemName: widget.icon)
                  .foregroundColor(widget.isActive ? .primary : .secondary)
                Text(widget.name)
                  .foregroundColor(widget.isActive ? .primary : .secondary)
                if !widget.isActive {
                  Text("(inactive)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                Spacer()
                Button("Edit") {
                  editingWidget = widget
                }
                .buttonStyle(BorderlessButtonStyle())

                Button("Remove") {
                  settings.objectWillChange.send()

                  // Find the index being removed
                  if let removedIndex = settings.draftSettings.userWidgets.firstIndex(where: {
                    $0.id == widget.id
                  }) {
                    settings.draftSettings.userWidgets.remove(at: removedIndex)

                    // Remove corresponding widget instances from all bars and update indices
                    updateUserWidgetIndicesInLayout(removedIndex: removedIndex)
                  }

                  refreshID = UUID()
                }
                .buttonStyle(BorderlessButtonStyle())
                .foregroundColor(.red)
              }
            }
            .onDelete { indexSet in
              settings.objectWillChange.send()

              // Remove from userWidgets and update layout
              for index in indexSet.sorted(by: >) {
                settings.draftSettings.userWidgets.remove(at: index)

                // Update user widget indices in the layout
                updateUserWidgetIndicesInLayout(removedIndex: index)
              }

              refreshID = UUID()
            }
            .onMove { source, destination in
              settings.objectWillChange.send()

              // Create index mapping for the move
              var oldToNewIndex: [Int: Int] = [:]
              var tempWidgets = settings.draftSettings.userWidgets
              tempWidgets.move(fromOffsets: source, toOffset: destination)

              for (newIndex, widget) in tempWidgets.enumerated() {
                if let oldIndex = settings.draftSettings.userWidgets.firstIndex(where: {
                  $0.id == widget.id
                }) {
                  oldToNewIndex[oldIndex] = newIndex
                }
              }

              settings.draftSettings.userWidgets.move(fromOffsets: source, toOffset: destination)

              // Update user widget indices in the multi-display layout
              updateUserWidgetIndicesAfterMove(oldToNewIndex: oldToNewIndex)

              refreshID = UUID()
            }
          }
          .frame(minHeight: 200, maxHeight: .infinity)
        }
      }
      .id(refreshID)

      Spacer()
    }
    .padding()
    .sheet(isPresented: $showAddSheet) {
      CustomWidgetEditorView(
        widget: nil,
        existingWidgets: settings.draftSettings.userWidgets
      ) { newWidget in
        settings.objectWillChange.send()
        settings.draftSettings.userWidgets.append(newWidget)
        refreshID = UUID()
      }
    }
    .sheet(item: $editingWidget) { widget in
      CustomWidgetEditorView(
        widget: widget,
        existingWidgets: settings.draftSettings.userWidgets
      ) { updatedWidget in
        if let index = settings.draftSettings.userWidgets.firstIndex(where: {
          $0.id == updatedWidget.id
        }
        ) {
          settings.objectWillChange.send()
          settings.draftSettings.userWidgets[index] = updatedWidget
          refreshID = UUID()
        }
      }
    }
    .navigationTitle("Custom Widgets")
  }

  // Helper function to update user widget indices after removal
  private func updateUserWidgetIndicesInLayout(removedIndex: Int) {
    var layout = settings.draftLayout

    for displayIndex in 0..<layout.displays.count {
      // Update top bar
      if var topBar = layout.displays[displayIndex].topBar {
        topBar.left = updateUserWidgetIndices(in: topBar.left, removedIndex: removedIndex)
        topBar.center = updateUserWidgetIndices(in: topBar.center, removedIndex: removedIndex)
        topBar.right = updateUserWidgetIndices(in: topBar.right, removedIndex: removedIndex)
        layout.displays[displayIndex].topBar = topBar
      }

      // Update bottom bar
      if var bottomBar = layout.displays[displayIndex].bottomBar {
        bottomBar.left = updateUserWidgetIndices(in: bottomBar.left, removedIndex: removedIndex)
        bottomBar.center = updateUserWidgetIndices(in: bottomBar.center, removedIndex: removedIndex)
        bottomBar.right = updateUserWidgetIndices(in: bottomBar.right, removedIndex: removedIndex)
        layout.displays[displayIndex].bottomBar = bottomBar
      }
    }

    settings.draftLayout = layout
  }

  private func updateUserWidgetIndices(in widgets: [WidgetInstance], removedIndex: Int)
    -> [WidgetInstance]
  {
    return widgets.compactMap { widget in
      guard widget.identifier == .userWidget else { return widget }
      guard let index = widget.userWidgetIndex else { return widget }

      if index == removedIndex {
        return nil  // Remove this widget
      } else if index > removedIndex {
        var updated = widget
        updated.userWidgetIndex = index - 1
        return updated
      }
      return widget
    }
  }

  // Helper function to update user widget indices after move/reorder
  private func updateUserWidgetIndicesAfterMove(oldToNewIndex: [Int: Int]) {
    var layout = settings.draftLayout

    for displayIndex in 0..<layout.displays.count {
      // Update top bar
      if var topBar = layout.displays[displayIndex].topBar {
        topBar.left = updateUserWidgetIndicesForMove(in: topBar.left, oldToNewIndex: oldToNewIndex)
        topBar.center = updateUserWidgetIndicesForMove(
          in: topBar.center, oldToNewIndex: oldToNewIndex)
        topBar.right = updateUserWidgetIndicesForMove(
          in: topBar.right, oldToNewIndex: oldToNewIndex)
        layout.displays[displayIndex].topBar = topBar
      }

      // Update bottom bar
      if var bottomBar = layout.displays[displayIndex].bottomBar {
        bottomBar.left = updateUserWidgetIndicesForMove(
          in: bottomBar.left, oldToNewIndex: oldToNewIndex)
        bottomBar.center = updateUserWidgetIndicesForMove(
          in: bottomBar.center, oldToNewIndex: oldToNewIndex)
        bottomBar.right = updateUserWidgetIndicesForMove(
          in: bottomBar.right, oldToNewIndex: oldToNewIndex)
        layout.displays[displayIndex].bottomBar = bottomBar
      }
    }

    settings.draftLayout = layout
  }

  private func updateUserWidgetIndicesForMove(
    in widgets: [WidgetInstance], oldToNewIndex: [Int: Int]
  ) -> [WidgetInstance] {
    return widgets.map { widget in
      guard widget.identifier == .userWidget,
        let oldIndex = widget.userWidgetIndex,
        let newIndex = oldToNewIndex[oldIndex]
      else {
        return widget
      }
      var updated = widget
      updated.userWidgetIndex = newIndex
      return updated
    }
  }
}

struct CustomWidgetEditorView: View {
  let widget: UserWidgetDefinition?
  let existingWidgets: [UserWidgetDefinition]
  let onSave: (UserWidgetDefinition) -> Void

  @Environment(\.presentationMode) private var presentationMode
  @EnvironmentObject var settings: SettingsManager

  @State private var name: String = ""
  @State private var icon: String = "gear"
  @State private var command: String = ""
  @State private var clickCommand: String = ""
  @State private var refreshInterval: Double = 60.0
  @State private var backgroundColor: String = ""
  @State private var isActive: Bool = true
  @State private var hideIcon: Bool = false
  @State private var hideWhenEmpty: Bool = false
  @State private var showIconPicker = false
  @State private var selectedColorPreset: String = "none"
  @State private var showErrorAlert = false
  @State private var errorMessage = ""

  private var theme: ABarTheme {
    ThemeManager.currentTheme(for: settings.draftSettings.theme)
  }

  private var colorPresets: [(name: String, value: String, color: Color?)] {
    [
      ("None", "none", nil),
      ("Main", "main", theme.main),
      ("Main Alt", "mainAlt", theme.mainAlt),
      ("Minor", "minor", theme.minor),
      ("Accent", "accent", theme.accent),
      ("Red", "red", theme.red),
      ("Green", "green", theme.green),
      ("Yellow", "yellow", theme.yellow),
      ("Orange", "orange", theme.orange),
      ("Blue", "blue", theme.blue),
      ("Magenta", "magenta", theme.magenta),
      ("Cyan", "cyan", theme.cyan),
      ("Custom...", "custom", nil),
    ]
  }

  var body: some View {
    VStack(spacing: 0) {
      // Header
      Text(widget == nil ? "Add Widget" : "Edit Widget")
        .font(.headline)
        .padding(10)
      
      Divider()

      // Form content
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          // Status Section
          GroupBox {
            Toggle("Active", isOn: $isActive)
              .toggleStyle(SwitchToggleStyle())
          }

          // Basic Info Section
          GroupBox(label: Text("Basic Information").font(.subheadline).fontWeight(.medium)) {
            VStack(alignment: .leading, spacing: 14) {
              VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                  .font(.caption)
                  .foregroundColor(.secondary)
                TextField("Message", text: $name)
                  .textFieldStyle(RoundedBorderTextFieldStyle())
              }

              VStack(alignment: .leading, spacing: 6) {
                Text("Icon")
                  .font(.caption)
                  .foregroundColor(.secondary)
                HStack(spacing: 12) {
                  Image(systemName: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)

                  Text(icon)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                  Spacer()

                  Button("Choose...") {
                    showIconPicker = true
                  }
                }
              }

              Toggle("Hide icon", isOn: $hideIcon)
                .toggleStyle(SwitchToggleStyle())

              Toggle("Hide when script output is empty", isOn: $hideWhenEmpty)
                .toggleStyle(SwitchToggleStyle())
            }
            .padding(.vertical, 8)
          }

          // Appearance Section
          GroupBox(label: Text("Appearance").font(.subheadline).fontWeight(.medium)) {
            VStack(alignment: .leading, spacing: 6) {
              Text("Background color")
                .font(.caption)
                .foregroundColor(.secondary)
              Picker("", selection: $selectedColorPreset) {
                ForEach(colorPresets, id: \.value) { preset in
                  HStack {
                    if let color = preset.color {
                      RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: 16, height: 16)
                    }
                    Text(preset.name)
                  }
                  .tag(preset.value)
                }
              }
              .pickerStyle(MenuPickerStyle())
              .labelsHidden()
              .onChange(of: selectedColorPreset) { newValue in
                if newValue == "none" {
                  backgroundColor = ""
                } else if newValue != "custom" {
                  backgroundColor = newValue
                }
              }

              if selectedColorPreset == "custom" {
                TextField("CSS color (e.g., #FF5733, rgb(255,87,51))", text: $backgroundColor)
                  .textFieldStyle(RoundedBorderTextFieldStyle())
                  .font(.system(.body, design: .monospaced))
              }
            }
            .padding(.vertical, 8)
          }

          // Command Section
          GroupBox(label: Text("Command Configuration").font(.subheadline).fontWeight(.medium)) {
            VStack(alignment: .leading, spacing: 14) {
              VStack(alignment: .leading, spacing: 6) {
                Text("Command/script path")
                  .font(.caption)
                  .foregroundColor(.secondary)
                TextEditor(text: $command)
                  .font(.system(.body, design: .monospaced))
                  .frame(height: 80)
                  .background(Color(NSColor.textBackgroundColor))
                  .cornerRadius(4)
                  .overlay(
                    RoundedRectangle(cornerRadius: 4)
                      .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                  )
                Text("e.g., echo 'Hello' or bash ~/my-script.sh")
                  .font(.caption2)
                  .foregroundColor(.secondary)
              }

              HStack(spacing: 8) {
                Text("Refresh frequency")
                  .font(.caption)
                  .foregroundColor(.secondary)
                Spacer()
                TextField("", value: $refreshInterval, formatter: NumberFormatter())
                  .frame(width: 60)
                  .textFieldStyle(RoundedBorderTextFieldStyle())
                  .multilineTextAlignment(.trailing)
                Text("seconds")
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
            }
            .padding(.vertical, 8)
          }

          // Interaction Section
          GroupBox(label: Text("On Click Action").font(.subheadline).fontWeight(.medium)) {
            VStack(alignment: .leading, spacing: 6) {
              Text("Command to run on click (optional)")
                .font(.caption)
                .foregroundColor(.secondary)
              TextEditor(text: $clickCommand)
                .font(.system(.body, design: .monospaced))
                .frame(height: 60)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(4)
                .overlay(
                  RoundedRectangle(cornerRadius: 4)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )
            }
            .padding(.vertical, 8)
          }
        }
        .padding(20)
      }

      Divider()

      // Action Buttons
      HStack(spacing: 12) {
        Button("Cancel") {
          presentationMode.wrappedValue.dismiss()
        }

        Spacer()

        Button("Save") {
          // Validate unique name (exclude current widget if editing)
          let nameTaken = existingWidgets.contains { existingWidget in
            existingWidget.name == name && existingWidget.id != widget?.id
          }

          if nameTaken {
            errorMessage =
              "A widget with the name '\(name)' already exists. Widget names must be unique as they are used for AppleScript targeting."
            showErrorAlert = true
            return
          }

          // Construct the UserWidgetDefinition
          let newWidget = UserWidgetDefinition(
            id: widget?.id ?? UUID(),
            name: name,
            icon: icon,
            command: command,
            refreshInterval: refreshInterval,
            clickCommand: clickCommand.isEmpty ? nil : clickCommand,
            backgroundColor: backgroundColor.isEmpty ? nil : backgroundColor,
            isActive: isActive,
            hideIcon: hideIcon,
            hideWhenEmpty: hideWhenEmpty
          )
          onSave(newWidget)
          presentationMode.wrappedValue.dismiss()
        }
        .disabled(name.isEmpty || icon.isEmpty)
        .keyboardShortcut(.defaultAction)
      }
      .padding(20)
    }
    .frame(minWidth: 520, minHeight: 620)
    .onAppear {
      if let widget = widget {
        name = widget.name
        icon = widget.icon
        command = widget.command
        clickCommand = widget.clickCommand ?? ""
        refreshInterval = widget.refreshInterval
        backgroundColor = widget.backgroundColor ?? ""
        isActive = widget.isActive
        hideIcon = widget.hideIcon
        hideWhenEmpty = widget.hideWhenEmpty

        // Determine color preset
        if let bg = widget.backgroundColor, !bg.isEmpty {
          if colorPresets.contains(where: { $0.value == bg }) {
            selectedColorPreset = bg
          } else {
            selectedColorPreset = "custom"
          }
        } else {
          selectedColorPreset = "none"
        }
      }
    }
    .sheet(isPresented: $showIconPicker) {
      IconPickerView(selectedIcon: $icon)
    }
    .alert("Invalid Widget Name", isPresented: $showErrorAlert) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(errorMessage)
    }
  }

}

struct IconPickerView: View {
  @Binding var selectedIcon: String
  @Environment(\.presentationMode) private var presentationMode
  @State private var searchText: String = ""

  @State private var symbols: [String] = []

  private var filteredSymbols: [String] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return symbols }
    return symbols.filter { $0.localizedCaseInsensitiveContains(query) }
  }

  private let columns = [GridItem(.adaptive(minimum: 80, maximum: 160), spacing: 12)]

  var body: some View {
    VStack(spacing: 0) {
      // Header
      HStack {
        Text("Icons")
          .font(.headline)
        Spacer()
        Button("Cancel") {
          presentationMode.wrappedValue.dismiss()
        }
      }
      .padding()

      Divider()

      // Search
      HStack {
        TextField("Search icons", text: $searchText)
          .textFieldStyle(RoundedBorderTextFieldStyle())
        Button("Refresh") { loadSymbols() }
      }
      .padding([.leading, .trailing, .top])

      // Grid
      ScrollView {
        LazyVGrid(columns: columns, spacing: 12) {
          ForEach(filteredSymbols, id: \.self) { symbol in
            Button(action: {
              selectedIcon = symbol
              presentationMode.wrappedValue.dismiss()
            }) {
              VStack(spacing: 6) {
                Image(systemName: symbol)
                  .scaledToFit()
                  .frame(width: 28, height: 28)
                  .padding(8)
                  .background(
                    RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.controlBackgroundColor)))

                Text(symbol)
                  .font(.caption2)
                  .lineLimit(1)
                  .truncationMode(.middle)
              }
              .padding(6)
              .frame(minWidth: 80, maxWidth: .infinity)
            }
            .buttonStyle(PlainButtonStyle())
          }
        }
        .frame(maxWidth: .infinity)
        .padding()
      }
      .onAppear { loadSymbols() }
    }
    .frame(width: 520, height: 420)
    .fixedSize()
  }

  private func loadSymbols() {
    // Try bundle resource first
    if let url = Bundle.main.url(forResource: "sfsymbols", withExtension: "txt") {
      if let contents = try? String(contentsOf: url) {
        let lines = contents.components(separatedBy: .newlines).map {
          $0.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }
        if !lines.isEmpty {
          symbols = lines
          return
        }
      }
    }
    // Fallback: leave default small set
  }
}

struct AboutView: View {
  var body: some View {
    VStack(spacing: 10) {
      Image("AppLogo")
        .resizable()
        .scaledToFit()
        .frame(height: 120)

      Text("a-bar")
        .font(.largeTitle)
        .fontWeight(.bold)

      Text("Yet a(nother) bar")
        .font(.headline)
        .foregroundColor(.secondary)

      Text("Version 1.3.7")
        .font(.caption)

      Divider()

      Text("A native macOS menu bar replacement inspired by simple-bar.")
        .multilineTextAlignment(.center)
        .foregroundColor(.secondary)

      Spacer()

      HStack {
        Button("GitHub") {
          if let url = URL(string: "https://github.com/Jean-Tinland/a-bar") {
            NSWorkspace.shared.open(url)
          }
        }

        Button("Report Issue") {
          if let url = URL(string: "https://github.com/Jean-Tinland/a-bar/issues") {
            NSWorkspace.shared.open(url)
          }
        }
      }
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .navigationTitle("About")
  }
}
