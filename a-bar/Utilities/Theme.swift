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

  enum ThemeKind {
    case dark
    case light
  }
}

enum ThemePreset: String, Codable, CaseIterable, Identifiable {
  case nightShift = "night-shift"
  case dayShift = "day-shift"
  case nightOwl = "night-owl"
  case oneDark = "one-dark"
  case gruvboxDark = "gruvbox-dark"
  case draculaPro = "dracula-pro"
  case tokyoNight = "tokyo-night"
  case catppuccinMocha = "catppuccin-mocha"
  case nordDark = "nord-dark"
  case materialOcean = "material-ocean"
  case solarizedDark = "solarized-dark"
  case oneLight = "one-light"
  case gruvboxLight = "gruvbox-light"
  case solarizedLight = "solarized-light"
  case nordLight = "nord-light"
  case catppuccinLatte = "catppuccin-latte"

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .nightShift: return "Night Shift"
    case .dayShift: return "Day Shift"
    case .nightOwl: return "Night Owl"
    case .oneDark: return "One Dark"
    case .gruvboxDark: return "Gruvbox Dark"
    case .draculaPro: return "Dracula Pro"
    case .tokyoNight: return "Tokyo Night"
    case .catppuccinMocha: return "Catppuccin Mocha"
    case .nordDark: return "Nord Dark"
    case .materialOcean: return "Material Ocean"
    case .solarizedDark: return "Solarized Dark"
    case .oneLight: return "One Light"
    case .gruvboxLight: return "Gruvbox Light"
    case .solarizedLight: return "Solarized Light"
    case .nordLight: return "Nord Light"
    case .catppuccinLatte: return "Catppuccin Latte"
    }
  }

  var kind: ABarTheme.ThemeKind {
    switch self {
    case .nightShift, .oneDark, .gruvboxDark, .draculaPro, .tokyoNight, .catppuccinMocha, .nordDark, .materialOcean, .solarizedDark, .nightOwl:
      return .dark
    case .dayShift, .oneLight, .gruvboxLight, .solarizedLight, .nordLight, .catppuccinLatte:
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
      )

    case .nightOwl:
      return ABarTheme(
        name: displayName, kind: .dark,
        main: Color(hex: "#011627"),
        mainAlt: Color(hex: "#0b2942"),
        minor: Color(hex: "#1d3b53"),
        accent: Color(hex: "#82aaff"),
        red: Color(hex: "#ef5350"),
        green: Color(hex: "#22da6e"),
        yellow: Color(hex: "#ffeb95"),
        orange: Color(hex: "#f78c6c"),
        blue: Color(hex: "#82aaff"),
        magenta: Color(hex: "#c792ea"),
        cyan: Color(hex: "#7fdbca"),
        foreground: Color(hex: "#d6deeb"),
        background: Color(hex: "#011627")
      )
          
    case .oneDark:
      return ABarTheme(
        name: displayName, kind: .dark,
        main: Color(hex: "#282c34"),
        mainAlt: Color(hex: "#21252b"),
        minor: Color(hex: "#3e4451"),
        accent: Color(hex: "#61afef"),
        red: Color(hex: "#e06c75"),
        green: Color(hex: "#98c379"),
        yellow: Color(hex: "#e5c07b"),
        orange: Color(hex: "#d19a66"),
        blue: Color(hex: "#61afef"),
        magenta: Color(hex: "#c678dd"),
        cyan: Color(hex: "#56b6c2"),
        foreground: Color(hex: "#abb2bf"),
        background: Color(hex: "#282c34")
      )
        
    case .gruvboxDark:
      return ABarTheme(
        name: displayName, kind: .dark,
        main: Color(hex: "#282828"),
        mainAlt: Color(hex: "#1d2021"),
        minor: Color(hex: "#3c3836"),
        accent: Color(hex: "#fe8019"),
        red: Color(hex: "#fb4934"),
        green: Color(hex: "#b8bb26"),
        yellow: Color(hex: "#fabd2f"),
        orange: Color(hex: "#fe8019"),
        blue: Color(hex: "#83a598"),
        magenta: Color(hex: "#d3869b"),
        cyan: Color(hex: "#8ec07c"),
        foreground: Color(hex: "#ebdbb2"),
        background: Color(hex: "#282828")
      )
        
    case .draculaPro:
      return ABarTheme(
        name: displayName, kind: .dark,
        main: Color(hex: "#22212c"),
        mainAlt: Color(hex: "#17161d"),
        minor: Color(hex: "#454158"),
        accent: Color(hex: "#ff80bf"),
        red: Color(hex: "#ff9580"),
        green: Color(hex: "#8aff80"),
        yellow: Color(hex: "#ffff80"),
        orange: Color(hex: "#ffca80"),
        blue: Color(hex: "#80bfff"),
        magenta: Color(hex: "#ff80bf"),
        cyan: Color(hex: "#80ffea"),
        foreground: Color(hex: "#f8f8f2"),
        background: Color(hex: "#22212c")
      )
        
    case .tokyoNight:
      return ABarTheme(
        name: displayName, kind: .dark,
        main: Color(hex: "#1a1b26"),
        mainAlt: Color(hex: "#16161e"),
        minor: Color(hex: "#292e42"),
        accent: Color(hex: "#7aa2f7"),
        red: Color(hex: "#f7768e"),
        green: Color(hex: "#9ece6a"),
        yellow: Color(hex: "#e0af68"),
        orange: Color(hex: "#ff9e64"),
        blue: Color(hex: "#7aa2f7"),
        magenta: Color(hex: "#bb9af7"),
        cyan: Color(hex: "#7dcfff"),
        foreground: Color(hex: "#c0caf5"),
        background: Color(hex: "#1a1b26")
      )
        
    case .catppuccinMocha:
      return ABarTheme(
        name: displayName, kind: .dark,
        main: Color(hex: "#1e1e2e"),
        mainAlt: Color(hex: "#181825"),
        minor: Color(hex: "#313244"),
        accent: Color(hex: "#cba6f7"),
        red: Color(hex: "#f38ba8"),
        green: Color(hex: "#a6e3a1"),
        yellow: Color(hex: "#f9e2af"),
        orange: Color(hex: "#fab387"),
        blue: Color(hex: "#89b4fa"),
        magenta: Color(hex: "#cba6f7"),
        cyan: Color(hex: "#94e2d5"),
        foreground: Color(hex: "#cdd6f4"),
        background: Color(hex: "#1e1e2e")
      )
        
    case .nordDark:
      return ABarTheme(
        name: displayName, kind: .dark,
        main: Color(hex: "#2e3440"),
        mainAlt: Color(hex: "#242933"),
        minor: Color(hex: "#3b4252"),
        accent: Color(hex: "#88c0d0"),
        red: Color(hex: "#bf616a"),
        green: Color(hex: "#a3be8c"),
        yellow: Color(hex: "#ebcb8b"),
        orange: Color(hex: "#d08770"),
        blue: Color(hex: "#81a1c1"),
        magenta: Color(hex: "#b48ead"),
        cyan: Color(hex: "#88c0d0"),
        foreground: Color(hex: "#eceff4"),
        background: Color(hex: "#2e3440")
      )
        
    case .materialOcean:
      return ABarTheme(
        name: displayName, kind: .dark,
        main: Color(hex: "#0f111a"),
        mainAlt: Color(hex: "#090b10"),
        minor: Color(hex: "#1a1c25"),
        accent: Color(hex: "#84ffff"),
        red: Color(hex: "#ff5370"),
        green: Color(hex: "#c3e88d"),
        yellow: Color(hex: "#ffcb6b"),
        orange: Color(hex: "#f78c6c"),
        blue: Color(hex: "#82aaff"),
        magenta: Color(hex: "#c792ea"),
        cyan: Color(hex: "#84ffff"),
        foreground: Color(hex: "#8f93a2"),
        background: Color(hex: "#0f111a")
      )
        
    case .solarizedDark:
      return ABarTheme(
        name: displayName, kind: .dark,
        main: Color(hex: "#002b36"),
        mainAlt: Color(hex: "#001e26"),
        minor: Color(hex: "#073642"),
        accent: Color(hex: "#268bd2"),
        red: Color(hex: "#dc322f"),
        green: Color(hex: "#859900"),
        yellow: Color(hex: "#b58900"),
        orange: Color(hex: "#cb4b16"),
        blue: Color(hex: "#268bd2"),
        magenta: Color(hex: "#d33682"),
        cyan: Color(hex: "#2aa198"),
        foreground: Color(hex: "#839496"),
        background: Color(hex: "#002b36")
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
      )
        
    case .oneLight:
      return ABarTheme(
        name: displayName, kind: .light,
        main: Color(hex: "#fafafa"),
        mainAlt: Color(hex: "#f0f0f0"),
        minor: Color(hex: "#d4d4d4"),
        accent: Color(hex: "#4078f2"),
        red: Color(hex: "#e45649"),
        green: Color(hex: "#50a14f"),
        yellow: Color(hex: "#c18401"),
        orange: Color(hex: "#986801"),
        blue: Color(hex: "#4078f2"),
        magenta: Color(hex: "#a626a4"),
        cyan: Color(hex: "#0184bc"),
        foreground: Color(hex: "#383a42"),
        background: Color(hex: "#fafafa")
      )
        
    case .gruvboxLight:
      return ABarTheme(
        name: displayName, kind: .light,
        main: Color(hex: "#fbf1c7"),
        mainAlt: Color(hex: "#f2e5bc"),
        minor: Color(hex: "#d5c4a1"),
        accent: Color(hex: "#af3a03"),
        red: Color(hex: "#cc241d"),
        green: Color(hex: "#98971a"),
        yellow: Color(hex: "#d79921"),
        orange: Color(hex: "#af3a03"),
        blue: Color(hex: "#458588"),
        magenta: Color(hex: "#b16286"),
        cyan: Color(hex: "#689d6a"),
        foreground: Color(hex: "#3c3836"),
        background: Color(hex: "#fbf1c7")
      )
        
    case .solarizedLight:
      return ABarTheme(
        name: displayName, kind: .light,
        main: Color(hex: "#fdf6e3"),
        mainAlt: Color(hex: "#eee8d5"),
        minor: Color(hex: "#93a1a1"),
        accent: Color(hex: "#268bd2"),
        red: Color(hex: "#dc322f"),
        green: Color(hex: "#859900"),
        yellow: Color(hex: "#b58900"),
        orange: Color(hex: "#cb4b16"),
        blue: Color(hex: "#268bd2"),
        magenta: Color(hex: "#d33682"),
        cyan: Color(hex: "#2aa198"),
        foreground: Color(hex: "#657b83"),
        background: Color(hex: "#fdf6e3")
      )
        
    case .nordLight:
      return ABarTheme(
        name: displayName, kind: .light,
        main: Color(hex: "#eceff4"),
        mainAlt: Color(hex: "#e5e9f0"),
        minor: Color(hex: "#d8dee9"),
        accent: Color(hex: "#5e81ac"),
        red: Color(hex: "#bf616a"),
        green: Color(hex: "#a3be8c"),
        yellow: Color(hex: "#ebcb8b"),
        orange: Color(hex: "#d08770"),
        blue: Color(hex: "#5e81ac"),
        magenta: Color(hex: "#b48ead"),
        cyan: Color(hex: "#88c0d0"),
        foreground: Color(hex: "#2e3440"),
        background: Color(hex: "#eceff4")
      )
        
    case .catppuccinLatte:
      return ABarTheme(
        name: displayName, kind: .light,
        main: Color(hex: "#eff1f5"),
        mainAlt: Color(hex: "#e6e9ef"),
        minor: Color(hex: "#ccd0da"),
        accent: Color(hex: "#8839ef"),
        red: Color(hex: "#d20f39"),
        green: Color(hex: "#40a02b"),
        yellow: Color(hex: "#df8e1d"),
        orange: Color(hex: "#fe640b"),
        blue: Color(hex: "#1e66f5"),
        magenta: Color(hex: "#8839ef"),
        cyan: Color(hex: "#179299"),
        foreground: Color(hex: "#4c4f69"),
        background: Color(hex: "#eff1f5")
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
