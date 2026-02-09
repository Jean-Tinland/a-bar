import SwiftUI

/// Main settings view
struct SettingsView: View {
  @EnvironmentObject var settings: SettingsManager
  @StateObject private var userWidgetManager = UserWidgetManager.shared

  @State private var selectedTab = SettingsTab.general

  var body: some View {
    HStack(spacing: 0) {
      // Sidebar with tabs (fixed width)
      List(selection: $selectedTab) {
        Section("General") {
          Label("General", systemImage: "gear").tag(SettingsTab.general)
          Label("Appearance", systemImage: "paintbrush").tag(SettingsTab.appearance)
          Label("Layout", systemImage: "rectangle.3.group").tag(SettingsTab.layout)
        }
        Section("Window Manager") {
          Label("Yabai", systemImage: "squares.below.rectangle").tag(SettingsTab.yabai)
          Label("AeroSpace", systemImage: "rectangle.3.group.fill").tag(SettingsTab.aerospace)
          Label("Process", systemImage: "app.dashed").tag(SettingsTab.process)
        }
        Section("Widgets") {
          Label("Battery", systemImage: "battery.100").tag(SettingsTab.battery)
          Label("Weather", systemImage: "cloud.sun").tag(SettingsTab.weather)
          Label("Date & Time", systemImage: "clock").tag(SettingsTab.dateTime)
          Label("Network", systemImage: "wifi").tag(SettingsTab.network)
          Label("Input / Output", systemImage: "speaker.wave.2").tag(SettingsTab.audio)
          Label("System Stats", systemImage: "chart.bar").tag(SettingsTab.systemStats)
          Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right").tag(
            SettingsTab.github)
          Label("Hacker News", systemImage: "newspaper").tag(SettingsTab.hackerNews)
          Label("Custom", systemImage: "star").tag(SettingsTab.custom)
        }
        Section {
          Label("About", systemImage: "info.circle").tag(SettingsTab.about)
        }
      }
      .listStyle(SidebarListStyle())
      .background(
        Color(NSColor.windowBackgroundColor)
          .ignoresSafeArea(edges: .top)
      )
      .frame(width: 200)

      Divider()

      // Detail view
      VStack(spacing: 0) {
        ScrollView {
          Group {
            switch selectedTab {
            case .general:
              GeneralSettingsView()
            case .appearance:
              AppearanceSettingsView()
            case .layout:
              LayoutBuilderView()
            case .yabai:
              YabaiSettingsView()
            case .aerospace:
              AerospaceSettingsView()
            case .process:
              ProcessSettingsView()
            case .battery:
              BatterySettingsView()
            case .weather:
              WeatherSettingsView()
            case .dateTime:
              DateTimeSettingsView()
            case .network:
              NetworkSettingsView()
            case .audio:
              AudioSettingsView()
            case .systemStats:
              SystemStatsSettingsView()
            case .github:
              GitHubSettingsView()
            case .hackerNews:
              HackerNewsSettingsView()
            case .custom:
              CustomWidgetSettingsView()
            case .about:
              AboutView()
            }
          }
          .padding()
        }

        // Save button footer
        Divider()
        HStack {
          if settings.hasUnsavedChanges {
            Text("You have unsaved changes")
              .font(.caption)
              .foregroundColor(.secondary)
          }
          Spacer()
          Button(action: {
            settings.saveSettings()
          }) {
            Text("Save Changes")
              .frame(minWidth: 100)
          }
          .buttonStyle(.borderedProminent)
          .disabled(!settings.hasUnsavedChanges)
          .keyboardShortcut("s", modifiers: .command)
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
      }
    }
    .frame(minWidth: 800, minHeight: 500)
    .environmentObject(userWidgetManager)
  }
}

enum SettingsTab: String, CaseIterable {
  case general
  case appearance
  case layout
  case yabai
  case aerospace
  case process
  case battery
  case weather
  case dateTime
  case network
  case audio
  case systemStats
  case github
  case hackerNews
  case custom
  case about
}
