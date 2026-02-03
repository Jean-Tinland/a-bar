import SwiftUI

struct AccessibilityPromptView: View {
    @StateObject private var helper = AccessibilityHelper.shared

    var body: some View {
        GroupBox(label: Label("Accessibility", systemImage: "lock.shield")) {
            VStack(alignment: .leading, spacing: 12) {
                if helper.isTrusted {
                    HStack {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.green)
                        Text("Accessibility access is enabled — no action needed.")
                    }
                } else {
                    Text("This app needs Accessibility permission to observe window focus and other events.\n\nWe only ask for this to provide reliable window tracking across apps and when switching between windows of the same application.")
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Button(action: {
                            helper.requestAuthorization(prompt: true)
                        }) {
                            Text("Request Accessibility")
                        }
                        Button(action: {
                            helper.openAccessibilityPreferences()
                        }) {
                            Text("Open Settings")
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }

                    Text("After enabling, you may need to restart the app for changes to take effect.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.top, 6)
        }
        .padding(.bottom, 8)
    }
}
