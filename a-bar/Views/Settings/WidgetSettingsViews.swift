import AppKit
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

struct YabaiSettingsView: View, ABarSettingsBindable {
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

struct ProcessSettingsView: View, ABarSettingsBindable {
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
}

struct BatterySettingsView: View, ABarSettingsBindable {
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
}

struct WeatherSettingsView: View, ABarSettingsBindable {
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
}

struct DateTimeSettingsView: View, ABarSettingsBindable {
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
}

struct NetworkSettingsView: View, ABarSettingsBindable {
  @EnvironmentObject var settings: SettingsManager

  var body: some View {
    Form {
      VStack(alignment: .leading, spacing: 16) {
        // WiFi
        Section {
          Text("WiFi").font(.headline)
          Toggle("Show icon", isOn: binding(\.widgets.wifi.showIcon))
          Toggle("Hide network name", isOn: binding(\.widgets.wifi.hideNetworkName))
          Toggle("Show signal strength", isOn: binding(\.widgets.wifi.showSignalStrength))
          Toggle("Hide when disabled", isOn: binding(\.widgets.wifi.hideWhenDisabled))

          VStack(alignment: .leading) {
            Text("Network device")
            TextField("Leave empty to auto-detect", text: binding(\.widgets.wifi.networkDevice))
              .textFieldStyle(RoundedBorderTextFieldStyle())
          }

          HStack(spacing: 4) {
            Text("Scan interval")
            TextField(
              "", value: binding(\.widgets.wifi.scanInterval), formatter: NumberFormatter()
            )
            .frame(width: 60)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            Text("seconds")
          }

          ThemeColorPicker(
            label: "Background color",
            selectedColor: Binding(
              get: { settings.draftSettings.widgets.wifi.backgroundColor },
              set: { settings.draftSettings.widgets.wifi.backgroundColor = $0 }
            )
          )
        }

        Divider()

        // Bluetooth
        Section {
          Text("Bluetooth").font(.headline)
          Toggle("Show icon", isOn: binding(\.widgets.bluetooth.showIcon))
          Toggle(
            "Show connected device name",
            isOn: binding(\.widgets.bluetooth.showConnectedDeviceName))
          Toggle(
            "Show connected device count", isOn: binding(\.widgets.bluetooth.showConnectedCount))
          Toggle("Show battery level in the bar", isOn: binding(\.widgets.bluetooth.showBatteryInBar))
          Toggle("Hide when disabled", isOn: binding(\.widgets.bluetooth.hideWhenDisabled))

          HStack(spacing: 4) {
            Text("Refresh interval")
            TextField(
              "", value: binding(\.widgets.bluetooth.refreshInterval), formatter: NumberFormatter()
            )
            .frame(width: 60)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            Text("seconds")
          }

          HStack(spacing: 4) {
            Text("Battery refresh interval")
            TextField(
              "", value: binding(\.widgets.bluetooth.batteryRefreshInterval),
              formatter: NumberFormatter()
            )
            .frame(width: 60)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            Text("seconds")
          }

          ThemeColorPicker(
            label: "Background color",
            selectedColor: Binding(
              get: { settings.draftSettings.widgets.bluetooth.backgroundColor },
              set: { settings.draftSettings.widgets.bluetooth.backgroundColor = $0 }
            )
          )
        }
      }
      .padding()
    }
    .navigationTitle("Network")
  }
}

struct AudioSettingsView: View, ABarSettingsBindable {
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
}

struct SystemStatsSettingsView: View, ABarSettingsBindable {
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
}

struct GitHubSettingsView: View, ABarSettingsBindable {
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
}

struct HackerNewsSettingsView: View, ABarSettingsBindable {
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
                Image(systemName: "terminal")
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

  /// Deleting a custom widget shifts every later one down, so placed instances have to follow
  /// or they end up running a different script.
  private func updateUserWidgetIndicesInLayout(removedIndex: Int) {
    settings.draftLayout = UserWidgetIndexRemapper.removing(
      removedIndex, from: settings.draftLayout)
  }

  private func updateUserWidgetIndicesAfterMove(oldToNewIndex: [Int: Int]) {
    settings.draftLayout = UserWidgetIndexRemapper.remapping(
      oldToNewIndex, in: settings.draftLayout)
  }
}

struct CustomWidgetEditorView: View {
  let widget: UserWidgetDefinition?
  let existingWidgets: [UserWidgetDefinition]
  let onSave: (UserWidgetDefinition) -> Void

  @Environment(\.presentationMode) private var presentationMode
  @EnvironmentObject var settings: SettingsManager

  @State private var name: String = ""
  @State private var command: String = ""
  @State private var refreshInterval: Double = 60.0
  @State private var cycleDuration: Double = 4.0
  @State private var backgroundColor: String = ""
  @State private var isActive: Bool = true
  @State private var hideWhenEmpty: Bool = false
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
      Text(widget == nil ? "Add Widget" : "Edit Widget")
        .font(.headline)
        .padding(10)

      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          // Status
          GroupBox {
            Toggle("Active", isOn: $isActive)
              .toggleStyle(SwitchToggleStyle())
          }

          // Basic Info
          GroupBox(label: Text("Basic Information").font(.subheadline).fontWeight(.medium)) {
            VStack(alignment: .leading, spacing: 14) {
              VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                  .font(.caption)
                  .foregroundColor(.secondary)
                TextField("My Widget", text: $name)
                  .textFieldStyle(RoundedBorderTextFieldStyle())
              }

              Toggle("Hide when script output is empty", isOn: $hideWhenEmpty)
                .toggleStyle(SwitchToggleStyle())
            }
            .padding(.vertical, 8)
          }

          // Appearance
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

          // Command
          GroupBox(label: Text("Command Configuration").font(.subheadline).fontWeight(.medium)) {
            VStack(alignment: .leading, spacing: 14) {
              VStack(alignment: .leading, spacing: 6) {
                Text("Command / script path")
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
                Text(
                  "Script output uses xbar format: lines before --- cycle in the bar, lines after --- appear in a dropdown menu. Use | to add parameters (color, href, shell, etc.)."
                )
                .font(.caption2)
                .foregroundColor(.secondary)
              }

              HStack(spacing: 8) {
                Text("Refresh interval")
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

              HStack(spacing: 8) {
                Text("Cycle duration")
                  .font(.caption)
                  .foregroundColor(.secondary)
                Spacer()
                TextField("", value: $cycleDuration, formatter: NumberFormatter())
                  .frame(width: 60)
                  .textFieldStyle(RoundedBorderTextFieldStyle())
                  .multilineTextAlignment(.trailing)
                Text("seconds")
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
              Text("How long each header line is displayed before cycling to the next one.")
                .font(.caption2)
                .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
          }

          // xbar Format Reference
          GroupBox(label: Text("xbar Format Reference").font(.subheadline).fontWeight(.medium)) {
            VStack(alignment: .leading, spacing: 8) {
              Text("Lines before `---` cycle in the menu bar. Lines after `---` appear in the dropdown.")
                .font(.caption)
                .foregroundColor(.secondary)
              Text("Add parameters with pipe: `text | color=red | href=https://...`")
                .font(.caption)
                .foregroundColor(.secondary)
              Text("Submenus: prefix with `--` (two dashes per level).")
                .font(.caption)
                .foregroundColor(.secondary)
              Group {
                Text("Supported parameters:")
                  .font(.caption)
                  .foregroundColor(.secondary)
                  .fontWeight(.medium)
                Text(
                  "color, font, size, href, shell, param1…paramN, terminal, refresh, dropdown, length, trim, alternate, image, templateImage, disabled, key"
                )
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.secondary)
              }
            }
            .padding(.vertical, 8)
          }
        }
        .padding(20)
      }

      Divider()

      HStack(spacing: 12) {
        Button("Cancel") {
          presentationMode.wrappedValue.dismiss()
        }

        Spacer()

        Button("Save") {
          let nameTaken = existingWidgets.contains { existingWidget in
            existingWidget.name == name && existingWidget.id != widget?.id
          }

          if nameTaken {
            errorMessage =
              "A widget with the name '\(name)' already exists. Widget names must be unique as they are used for AppleScript targeting."
            showErrorAlert = true
            return
          }

          let newWidget = UserWidgetDefinition(
            id: widget?.id ?? UUID(),
            name: name,
            command: command,
            refreshInterval: max(1, refreshInterval),
            isActive: isActive,
            backgroundColor: backgroundColor.isEmpty ? nil : backgroundColor,
            hideWhenEmpty: hideWhenEmpty,
            cycleDuration: max(1, cycleDuration)
          )
          onSave(newWidget)
          presentationMode.wrappedValue.dismiss()
        }
        .disabled(name.isEmpty)
        .keyboardShortcut(.defaultAction)
      }
      .padding(20)
    }
    .frame(minWidth: 520, minHeight: 620)
    .onAppear {
      if let widget = widget {
        name = widget.name
        command = widget.command
        refreshInterval = widget.refreshInterval
        cycleDuration = widget.cycleDuration
        backgroundColor = widget.backgroundColor ?? ""
        isActive = widget.isActive
        hideWhenEmpty = widget.hideWhenEmpty

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
    .alert("Invalid Widget Name", isPresented: $showErrorAlert) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(errorMessage)
    }
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

      Text("Version 1.6.0")
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
