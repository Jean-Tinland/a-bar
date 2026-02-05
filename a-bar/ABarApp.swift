import Combine
import SwiftUI

/// Main entry point for the a-bar application
@main
struct ABarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // The main scene of the application, which is the settings window
    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.settingsManager)
                .environmentObject(appDelegate.yabaiService)
                .environmentObject(appDelegate.layoutManager)
        }
    }
}
