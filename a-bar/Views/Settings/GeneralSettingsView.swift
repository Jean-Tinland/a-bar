import AppKit

import SwiftUI

/// General settings view
struct GeneralSettingsView: View, ABarSettingsBindable {
  @EnvironmentObject var settings: SettingsManager

  @State private var launchAtLoginStatus: LaunchAtLogin.Status = .disabled
  @State private var launchAtLoginError: String?

  var body: some View {
    Form {
      Section {
        VStack(alignment: .leading, spacing: 16) {
          // Launch at Login. Applied immediately rather than on Save: a login item that
          // only takes effect after pressing Save is surprising, and macOS can refuse the
          // registration outright, which the user needs to hear about straight away.
          VStack(alignment: .leading, spacing: 4) {
            Toggle(
              "Launch at login",
              isOn: Binding(
                get: { settings.settings.global.launchAtLogin },
                set: { setLaunchAtLogin($0) }
              )
            )

            if launchAtLoginStatus == .requiresApproval {
              Text("macOS needs you to approve a-bar before it can start at login.")
                .font(.caption)
                .foregroundColor(.secondary)
              Button("Open Login Items…") {
                LaunchAtLogin.openSystemSettings()
              }
              .buttonStyle(.link)
              .font(.caption)
            }

            if let launchAtLoginError = launchAtLoginError {
              Text(launchAtLoginError)
                .font(.caption)
                .foregroundColor(.red)
            }
          }
          .onAppear {
            launchAtLoginStatus = LaunchAtLogin.status
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
            if settings.settings.global.windowManager == .yabai {
              Text("Allow Accessibility access to keep window positions and titles up to date.")
                .font(.caption)
                .foregroundColor(.secondary)
              Button("Enable window tracking…") {
                YabaiService.shared.requestWindowObservationAccess()
              }
              .buttonStyle(.link)
              .font(.caption)
            }
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

  private func setLaunchAtLogin(_ enabled: Bool) {
    do {
      try LaunchAtLogin.setEnabled(enabled)
      launchAtLoginError = nil
      settings.update { $0.global.launchAtLogin = enabled }
    } catch {
      // Leave the setting alone, so the toggle snaps back to what macOS actually did.
      launchAtLoginError = "macOS refused to change the login item: \(error.localizedDescription)"
    }

    launchAtLoginStatus = LaunchAtLogin.status
  }
}
