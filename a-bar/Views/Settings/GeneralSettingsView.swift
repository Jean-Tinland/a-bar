import AppKit
import ServiceManagement
import SwiftUI

/// General settings view
struct GeneralSettingsView: View {
  @EnvironmentObject var settings: SettingsManager

  @State private var launchAtLogin = false

  private var globalSettings: GlobalSettings {
    settings.draftSettings.global
  }

  var body: some View {
    Form {
      Section {
        VStack(alignment: .leading, spacing: 16) {
          // Launch at Login
          Toggle("Launch at login", isOn: $launchAtLogin)
            .onChange(of: launchAtLogin) { newValue in
              setLaunchAtLogin(newValue)
            }
            .onAppear {
              launchAtLogin = getLaunchAtLogin()
            }

          // Window Manager
          VStack(alignment: .leading, spacing: 4) {
            Text("Window manager")
              .font(.headline)
            Picker("", selection: binding(\.global.windowManager)) {
              ForEach(WindowManager.allCases) { wm in
                Text(wm.displayName).tag(wm)
              }
            }
            .pickerStyle(SegmentedPickerStyle())
            .labelsHidden()
            Text("Select which window manager to use. yabai is the default.")
              .font(.caption)
              .foregroundColor(.secondary)
          }

          // Yabai Path
          VStack(alignment: .leading, spacing: 4) {
            Text("Yabai binary path")
              .font(.headline)
            TextField("Path to yabai", text: binding(\.global.yabaiPath))
              .textFieldStyle(RoundedBorderTextFieldStyle())
            Text("Default: /opt/homebrew/bin/yabai")
              .font(.caption)
              .foregroundColor(.secondary)
          }

          // AeroSpace Path
          VStack(alignment: .leading, spacing: 4) {
            Text("AeroSpace binary path")
              .font(.headline)
            TextField("Path to aerospace", text: binding(\.global.aerospacePath))
              .textFieldStyle(RoundedBorderTextFieldStyle())
            Text("Default: /opt/homebrew/bin/aerospace")
              .font(.caption)
              .foregroundColor(.secondary)
          }

        }
        .padding()
      }
    }
    .navigationTitle("General")
  }

  private func binding<T>(_ keyPath: WritableKeyPath<ABarSettings, T>) -> Binding<T> {
    Binding(
      get: { settings.draftSettings[keyPath: keyPath] },
      set: { settings.draftSettings[keyPath: keyPath] = $0 }
    )
  }

  private func setLaunchAtLogin(_ enabled: Bool) {
    if #available(macOS 13.0, *) {
      do {
        if enabled {
          try SMAppService.mainApp.register()
        } else {
          try SMAppService.mainApp.unregister()
        }
      } catch {
        print("Failed to update launch at login: \(error)")
      }
    } else {
      // Fallback for older macOS versions
      let identifier = Bundle.main.bundleIdentifier ?? "com.a-bar"
      if enabled {
        _ = ShellExecutor.runSync(
          "osascript -e 'tell application \"System Events\" to make login item at end with properties {path:\"/Applications/a-bar.app\", hidden:true}'"
        )
      } else {
        _ = ShellExecutor.runSync(
          "osascript -e 'tell application \"System Events\" to delete login item \"\(identifier)\"'"
        )
      }
    }
  }

  private func getLaunchAtLogin() -> Bool {
    if #available(macOS 13.0, *) {
      return SMAppService.mainApp.status == .enabled
    } else {
      return false
    }
  }
}
