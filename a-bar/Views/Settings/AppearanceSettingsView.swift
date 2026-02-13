import SwiftUI

/// Theme and appearance settings
struct AppearanceSettingsView: View {
  @EnvironmentObject var settings: SettingsManager

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {

        // Bar settings
        Section {
          VStack(alignment: .leading, spacing: 8) {
            Text("Bar settings")
              .font(.headline)

            HStack {
              Text("Bar height")
              Spacer()
              TextField("", value: binding(\.global.barHeight), formatter: NumberFormatter())
                .frame(width: 60)
                .textFieldStyle(RoundedBorderTextFieldStyle())
              Text("px")
            }
            
            HStack {
              Text("Bar horizontal padding")
              Spacer()
              TextField("", value: binding(\.global.barHorizontalPadding), formatter: NumberFormatter())
                .frame(width: 60)
                .textFieldStyle(RoundedBorderTextFieldStyle())
              Text("px")
            }
            
            HStack {
              Text("Bar vertical padding")
              Spacer()
              TextField("", value: binding(\.global.barVerticalPadding), formatter: NumberFormatter())
                .frame(width: 60)
                .textFieldStyle(RoundedBorderTextFieldStyle())
              Text("px")
            }
            
            HStack {
              Text("Bar distance from edges")
              Spacer()
              TextField("", value: binding(\.global.barDistanceFromEdges), formatter: NumberFormatter())
                .frame(width: 60)
                .textFieldStyle(RoundedBorderTextFieldStyle())
              Text("px")
            }
            
            
            HStack {
              Text("Bar radius")
              Spacer()
              TextField(
                "",
                value: binding(\.global.barCornerRadius),
                formatter: NumberFormatter()
              )
                .frame(width: 60)
                .textFieldStyle(RoundedBorderTextFieldStyle())
              Text("px")
            }
            
            Text("Bar radius will only take effect if 'Bar distance from edges' is higher than 0.")
              .font(.caption)
              .foregroundColor(.secondary)
            
            HStack {
              Text("Bar background opacity")
              Spacer()
              TextField(
                "",
                value: binding(\.global.barOpacity),
                formatter: NumberFormatter()
              )
                .frame(width: 60)
                .textFieldStyle(RoundedBorderTextFieldStyle())
              Text("%")
            }
            
            Toggle("Blur bar background", isOn: binding(\.global.barBackgroundBlur))
            
            Text("This setting will show a plain background color if you enable 'Reduce transparency' in macOS system settings.")
              .font(.caption)
              .foregroundColor(.secondary)
            
            Toggle("Show border", isOn: binding(\.global.showBorder))
            
            Divider()
            
            Text("Bar elements settings")
              .font(.headline)
            
            HStack {
              Text("Gap between elements")
              Spacer()
              TextField("", value: binding(\.global.barElementGap), formatter: NumberFormatter())
                .frame(width: 60)
                .textFieldStyle(RoundedBorderTextFieldStyle())
              Text("px")
            }
            
            HStack {
              Text("Elements border radius")
              Spacer()
              TextField("", value: binding(\.global.barElementsCornerRadius), formatter: NumberFormatter())
                .frame(width: 60)
                .textFieldStyle(RoundedBorderTextFieldStyle())
              Text("px")
            }
            
            HStack {
              Text("Elements background opacity")
              Spacer()
              TextField("", value: binding(\.global.barElementsBackgroundOpacity), formatter: NumberFormatter())
                .frame(width: 60)
                .textFieldStyle(RoundedBorderTextFieldStyle())
              Text("%")
            }

            Text("A value closer to 0 will make difficult to distinguish focused/active elements in the spaces & processes widgets.")
              .font(.caption)
              .foregroundColor(.secondary)
            
            Toggle("Show elements border", isOn: binding(\.global.showElementsBorder))
            
            Divider()

            Text("Data widgets settings")
              .font(.headline)
            
            
            Toggle("No color in data widgets", isOn: binding(\.global.noColorInDataWidgets))
            
            
            Divider()

            Text("Font settings")
              .font(.headline)

            HStack {
              Text("Font size")
              Spacer()
              TextField("", value: binding(\.global.fontSize), formatter: NumberFormatter())
                .frame(width: 60)
                .textFieldStyle(RoundedBorderTextFieldStyle())
              Text("px")
            }

            HStack {
              Text("Font")
              Spacer()
              FontPicker(selectedFont: binding(\.global.fontName))
            }

            Divider()

            Text("Icons settings")
              .font(.headline)

            Toggle("Grayscale app icons", isOn: binding(\.global.grayscaleAppIcons))
            
            Text("Icons are automatically following your system preferences regarding their style but you can enforce them to always be in grayscale.")
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }

        Divider()

        // Appearance mode
        Section {
          VStack(alignment: .leading, spacing: 8) {
            Text("Appearance")
              .font(.headline)

            Picker("Appearance", selection: binding(\.theme.appearance)) {
              ForEach(ThemeSettings.Appearance.allCases, id: \.self) { appearance in
                Text(appearance.displayName).tag(appearance)
              }
            }
            .pickerStyle(SegmentedPickerStyle())
            .labelsHidden()
          }
        }

        Divider()

        // Dark theme selection
        Section {
          VStack(alignment: .leading, spacing: 8) {
            Text("Dark Theme")
              .font(.headline)

            Picker("Dark Theme", selection: binding(\.theme.darkTheme)) {
              ForEach(ThemePreset.allCases, id: \.self) { preset in
                Text(preset.displayName).tag(preset)
              }
            }
            .pickerStyle(MenuPickerStyle())
            .labelsHidden()

            // Theme preview
            ThemePreviewView(theme: settings.draftSettings.theme.darkTheme.theme)
              .frame(height: 40)
              .cornerRadius(6)
          }
        }

        Divider()

        // Light theme selection
        Section {
          VStack(alignment: .leading, spacing: 8) {
            Text("Light Theme")
              .font(.headline)

            Picker("Light Theme", selection: binding(\.theme.lightTheme)) {
              ForEach(ThemePreset.allCases, id: \.self) { preset in
                Text(preset.displayName).tag(preset)
              }
            }
            .pickerStyle(MenuPickerStyle())
            .labelsHidden()

            // Theme preview
            ThemePreviewView(theme: settings.draftSettings.theme.lightTheme.theme)
              .frame(height: 40)
              .cornerRadius(6)
          }
        }

        Divider()

        // Color overrides
        Section {
          VStack(alignment: .leading, spacing: 8) {
            HStack {
              Text("Color Overrides")
                .font(.headline)

              Spacer()

              Button("Reset") {
                resetCustomColors()
              }
              .buttonStyle(BorderlessButtonStyle())
            }

            Text("Optional hex color overrides for the current theme")
              .font(.caption)
              .foregroundColor(.secondary)

            LazyVGrid(
              columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
              ], spacing: 12
            ) {
              ColorOverrideRow(
                label: "Background", hexString: binding(\.theme.colorOverrides.background))
              ColorOverrideRow(
                label: "Foreground", hexString: binding(\.theme.colorOverrides.foreground))
              ColorOverrideRow(label: "Main", hexString: binding(\.theme.colorOverrides.main))
              ColorOverrideRow(
                label: "Main Alt", hexString: binding(\.theme.colorOverrides.mainAlt))
              ColorOverrideRow(label: "Minor", hexString: binding(\.theme.colorOverrides.minor))
              ColorOverrideRow(label: "Accent", hexString: binding(\.theme.colorOverrides.accent))
              ColorOverrideRow(label: "Red", hexString: binding(\.theme.colorOverrides.red))
              ColorOverrideRow(label: "Green", hexString: binding(\.theme.colorOverrides.green))
              ColorOverrideRow(label: "Yellow", hexString: binding(\.theme.colorOverrides.yellow))
              ColorOverrideRow(label: "Orange", hexString: binding(\.theme.colorOverrides.orange))
              ColorOverrideRow(label: "Blue", hexString: binding(\.theme.colorOverrides.blue))
              ColorOverrideRow(label: "Magenta", hexString: binding(\.theme.colorOverrides.magenta))
              ColorOverrideRow(label: "Cyan", hexString: binding(\.theme.colorOverrides.cyan))
            }
          }
        }
      }
      .padding()
    }
    .navigationTitle("Appearance")
  }

  private func binding<T>(_ keyPath: WritableKeyPath<ABarSettings, T>) -> Binding<T> {
    Binding(
      get: { settings.draftSettings[keyPath: keyPath] },
      set: { settings.draftSettings[keyPath: keyPath] = $0 }
    )
  }

  private func resetCustomColors() {
    settings.draftSettings.theme.colorOverrides = ColorOverrides()
  }
}

struct ColorOverrideRow: View {
  let label: String
  @Binding var hexString: String?

  var body: some View {
    HStack {
      Text(label)
        .frame(width: 70, alignment: .leading)
        .font(.caption)

      if let hex = hexString, !hex.isEmpty {
        Rectangle()
          .fill(Color(hex: hex))
          .frame(width: 20, height: 20)
          .cornerRadius(4)
          .overlay(
            RoundedRectangle(cornerRadius: 4)
              .stroke(Color.gray.opacity(0.3), lineWidth: 1)
          )
      }

      TextField(
        "#RRGGBB",
        text: Binding(
          get: { hexString ?? "" },
          set: { newValue in
            hexString = newValue.isEmpty ? nil : newValue
          }
        )
      )
      .textFieldStyle(RoundedBorderTextFieldStyle())
      .font(.system(.caption, design: .monospaced))
    }
  }
}

struct ThemePreviewView: View {
  let theme: ABarTheme

  var body: some View {
    HStack(spacing: 0) {
      Rectangle()
        .fill(theme.background)
      Rectangle()
        .fill(theme.foreground)
      Rectangle()
        .fill(theme.accent)
      Rectangle()
        .fill(theme.minor)
      Rectangle()
        .fill(theme.red)
      Rectangle()
        .fill(theme.green)
      Rectangle()
        .fill(theme.yellow)
      Rectangle()
        .fill(theme.blue)
      Rectangle()
        .fill(theme.magenta)
      Rectangle()
        .fill(theme.cyan)
    }
  }
}

struct FontPicker: View {
  @Binding var selectedFont: String
  private var fontNames: [String] {
    NSFontManager.shared.availableFontFamilies.sorted()
  }
  var body: some View {
    Picker("", selection: $selectedFont) {
      Text("System Default").tag("")
      ForEach(fontNames, id: \.self) { font in
        Text(font).font(.custom(font, size: 13)).tag(font)
      }
    }
    .pickerStyle(MenuPickerStyle())
    .frame(width: 180)
  }
}
