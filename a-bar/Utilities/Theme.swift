import SwiftUI

/// Represents a color theme for the bar
struct ABarTheme {
  let name: String
  let kind: ThemeKind

  // Main colors
  let main: Color
  let mainAlt: Color
  let minor: Color
  let accent: Color

  // Semantic colors
  let red: Color
  let green: Color
  let yellow: Color
  let orange: Color
  let blue: Color
  let magenta: Color
  let cyan: Color

  // Base colors
  let foreground: Color
  let background: Color
  let highlight: Color

  enum ThemeKind {
    case dark
    case light
  }
}

enum ThemePreset: String, Codable, CaseIterable, Identifiable {
  case nightShift = "night-shift"
  case dayShift = "day-shift"

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .nightShift: return "Night Shift"
    case .dayShift: return "Day Shift"
    }
  }

  var kind: ABarTheme.ThemeKind {
    switch self {
    case .nightShift:
      return .dark
    case .dayShift:
      return .light
    }
  }

  var theme: ABarTheme {
    switch self {
    case .nightShift:
      return ABarTheme(
        name: displayName, kind: .dark,
        main: Color(hex: "#1b222d"),
        mainAlt: Color(hex: "#98a8c5"),
        minor: Color(hex: "#39465e"),
        accent: Color(hex: "#ffd484"),
        red: Color(hex: "#e78482"),
        green: Color(hex: "#8fc8bb"),
        yellow: Color(hex: "#ffd484"),
        orange: Color(hex: "#ffb374"),
        blue: Color(hex: "#6db3ce"),
        magenta: Color(hex: "#ad82cb"),
        cyan: Color(hex: "#7eddde"),
        foreground: Color(hex: "#ffffff"),
        background: Color(hex: "#1b222d"),
        highlight: Color(hex: "#39465e")
      )

    case .dayShift:
      return ABarTheme(
        name: displayName, kind: .light,
        main: Color(hex: "#f5f5f5"),
        mainAlt: Color(hex: "#98a8c5"),
        minor: Color(hex: "#ffffff"),
        accent: Color(hex: "#d1ab66"),
        red: Color(hex: "#e78482"),
        green: Color(hex: "#8fc8bb"),
        yellow: Color(hex: "#d1ab66"),
        orange: Color(hex: "#ffb374"),
        blue: Color(hex: "#6db3ce"),
        magenta: Color(hex: "#ad82cb"),
        cyan: Color(hex: "#2fc2c3"),
        foreground: Color(hex: "#1b222d"),
        background: Color(hex: "#f7f7f7"),
        highlight: Color(hex: "#e0e0e0")
      )
    }
  }

  static var darkThemes: [ThemePreset] {
    allCases.filter { $0.kind == .dark }
  }

  static var lightThemes: [ThemePreset] {
    allCases.filter { $0.kind == .light }
  }
}

enum ThemeManager {
  /// Get the current theme based on settings
  static func currentTheme(for settings: ThemeSettings) -> ABarTheme {
    let preset: ThemePreset

    switch settings.appearance {
    case .auto:
      let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      preset = isDark ? settings.darkTheme : settings.lightTheme
    case .dark:
      preset = settings.darkTheme
    case .light:
      preset = settings.lightTheme
    }

    return applyOverrides(to: preset.theme, overrides: settings.colorOverrides)
  }

  /// Apply color overrides to a theme
  private static func applyOverrides(to theme: ABarTheme, overrides: ColorOverrides) -> ABarTheme {
    return ABarTheme(
      name: theme.name,
      kind: theme.kind,
      main: overrides.main.flatMap { Color(hex: $0) } ?? theme.main,
      mainAlt: overrides.mainAlt.flatMap { Color(hex: $0) } ?? theme.mainAlt,
      minor: overrides.minor.flatMap { Color(hex: $0) } ?? theme.minor,
      accent: overrides.accent.flatMap { Color(hex: $0) } ?? theme.accent,
      red: overrides.red.flatMap { Color(hex: $0) } ?? theme.red,
      green: overrides.green.flatMap { Color(hex: $0) } ?? theme.green,
      yellow: overrides.yellow.flatMap { Color(hex: $0) } ?? theme.yellow,
      orange: overrides.orange.flatMap { Color(hex: $0) } ?? theme.orange,
      blue: overrides.blue.flatMap { Color(hex: $0) } ?? theme.blue,
      magenta: overrides.magenta.flatMap { Color(hex: $0) } ?? theme.magenta,
      cyan: overrides.cyan.flatMap { Color(hex: $0) } ?? theme.cyan,
      foreground: overrides.foreground.flatMap { Color(hex: $0) } ?? theme.foreground,
      background: overrides.background.flatMap { Color(hex: $0) } ?? theme.background,
      highlight: theme.highlight
    )
  }
}

extension Color {
  init(hex: String) {
    let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var int: UInt64 = 0
    Scanner(string: hex).scanHexInt64(&int)
    let a: UInt64
    let r: UInt64
    let g: UInt64
    let b: UInt64
    switch hex.count {
    case 3:  // RGB (12-bit)
      (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
    case 6:  // RGB (24-bit)
      (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
    case 8:  // ARGB (32-bit)
      (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
    default:
      (a, r, g, b) = (255, 0, 0, 0)
    }

    self.init(
      .sRGB,
      red: Double(r) / 255,
      green: Double(g) / 255,
      blue: Double(b) / 255,
      opacity: Double(a) / 255
    )
  }

  var hexString: String {
    guard let components = NSColor(self).cgColor.components else { return "#000000" }
    let r = Int(components[0] * 255)
    let g = Int(components[1] * 255)
    let b = Int(components[2] * 255)
    return String(format: "#%02X%02X%02X", r, g, b)
  }

  /// Calculate relative luminance using WCAG formula
  var luminance: Double {
    let components = NSColor(self).cgColor.components ?? [0, 0, 0]
    let r = components[0]
    let g = components[1]
    let b = components[2]

    // Convert to linear RGB
    func toLinear(_ c: CGFloat) -> Double {
      let value = Double(c)
      if value <= 0.03928 {
        return value / 12.92
      } else {
        return pow((value + 0.055) / 1.055, 2.4)
      }
    }

    return 0.2126 * toLinear(r) + 0.7152 * toLinear(g) + 0.0722 * toLinear(b)
  }

  /// Blend this color with a bar background color based on element opacity
  /// When opacity is low, the bar background shows through more
  /// - Parameters:
  ///   - opacity: The bar element background opacity (0-100)
  ///   - barBackground: The bar's background color to blend with
  /// - Returns: The effective visible color after blending
  func blendedWithBarBackground(_ barBackground: Color, opacity: CGFloat) -> Color {
    let normalizedOpacity = max(0, min(100, opacity)) / 100.0
    
    // Get RGBA components for both colors
    guard let selfComponents = NSColor(self).cgColor.components,
          let barComponents = NSColor(barBackground).cgColor.components,
          selfComponents.count >= 3,
          barComponents.count >= 3 else {
      return self
    }
    
    // Blend: final = (element * opacity) + (bar * (1 - opacity))
    let r = selfComponents[0] * normalizedOpacity + barComponents[0] * (1 - normalizedOpacity)
    let g = selfComponents[1] * normalizedOpacity + barComponents[1] * (1 - normalizedOpacity)
    let b = selfComponents[2] * normalizedOpacity + barComponents[2] * (1 - normalizedOpacity)
    
    return Color(
      red: Double(r),
      green: Double(g),
      blue: Double(b)
    )
  }

  /// Convenience method to blend with theme's bar background
  func withBarElementOpacity(_ opacity: CGFloat, barBackground: Color? = nil) -> Color {
    // If no bar background provided, just return self (for backward compatibility)
    guard let barBg = barBackground else { return self }
    
    // For high opacity (>= 70%), the widget background dominates, use it directly
    if opacity >= 70 {
      return self
    }
    
    // For lower opacity, blend to get the effective visible color
    return blendedWithBarBackground(barBg, opacity: opacity)
  }

  /// Get a contrasting foreground color based on luminance
  /// - Parameters:
  ///   - theme: The current theme
  ///   - opacity: Optional bar element opacity (0-100). When provided and low, uses bar background instead
  ///   - barBackground: Optional bar background color override
  /// - Returns: A contrasting foreground color
  func contrastingForeground(from theme: ABarTheme, opacity: CGFloat? = nil, barBackground: Color? = nil) -> Color {
    let effectiveBackground: Color
    
    if let opacity = opacity, opacity < 70 {
      // For low opacity, blend with bar background to get effective color
      let barBg = barBackground ?? theme.background
      effectiveBackground = blendedWithBarBackground(barBg, opacity: opacity)
    } else {
      effectiveBackground = self
    }
    
    // If background is light (high luminance), use dark foreground
    // If background is dark (low luminance), use light foreground
    return effectiveBackground.luminance > 0.5 ? Color.black.opacity(0.85) : Color.white.opacity(0.95)
  }
}
