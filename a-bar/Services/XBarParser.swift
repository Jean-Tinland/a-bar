import AppKit
import Foundation
import SwiftUI

/// Parameters that can be attached to an xbar line item via pipe syntax
struct XBarParams: Equatable {
  var href: String?
  var color: String?
  var font: String?
  var size: CGFloat?
  var shell: String?
  var shellParams: [String]
  var terminal: Bool
  var refresh: Bool
  var dropdown: Bool
  var length: Int?
  var trim: Bool
  var alternate: Bool
  var image: String?
  var templateImage: String?
  var disabled: Bool
  var key: String?
  var ansi: Bool
  var emojize: Bool

  static let defaults = XBarParams(
    href: nil, color: nil, font: nil, size: nil,
    shell: nil, shellParams: [], terminal: true,
    refresh: false, dropdown: true, length: nil,
    trim: true, alternate: false, image: nil,
    templateImage: nil, disabled: false, key: nil,
    ansi: true, emojize: true
  )
}

/// A single parsed line from xbar-compatible script output
struct XBarLineItem: Equatable {
  var title: String
  var level: Int
  var isSeparator: Bool
  var params: XBarParams
}

/// Result of parsing xbar-compatible script output
struct XBarParsedOutput: Equatable {
  var headerLines: [XBarLineItem]
  var menuItems: [XBarLineItem]

  static let empty = XBarParsedOutput(headerLines: [], menuItems: [])
}

enum XBarParser {

  /// Parse raw script output into structured xbar items
  static func parse(_ output: String) -> XBarParsedOutput {
    let lines = output.components(separatedBy: "\n")

    var headerLines: [XBarLineItem] = []
    var menuItems: [XBarLineItem] = []
    var inMenu = false

    for line in lines {
      if line.isEmpty { continue }

      let stripped = line.trimmingCharacters(in: .whitespaces)
      if stripped == "---" {
        if !inMenu {
          inMenu = true
        } else {
          menuItems.append(
            XBarLineItem(title: "", level: 0, isSeparator: true, params: .defaults))
        }
        continue
      }

      let item = parseLine(line, isMenuSection: inMenu)

      if inMenu {
        menuItems.append(item)
      } else {
        headerLines.append(item)
      }
    }

    return XBarParsedOutput(headerLines: headerLines, menuItems: menuItems)
  }

  /// Parse a single line with optional pipe-delimited parameters
  private static func parseLine(_ line: String, isMenuSection: Bool) -> XBarLineItem {
    var workingLine = line
    var level = 0

    // Determine submenu level from leading pairs of dashes (menu section only)
    if isMenuSection {
      while workingLine.hasPrefix("--") {
        level += 1
        workingLine = String(workingLine.dropFirst(2))
      }
    }

    // Split by pipe to separate title and params
    let parts = splitByPipe(workingLine)
    let rawTitle = parts.first ?? ""
    let paramParts = Array(parts.dropFirst())

    // Parse parameters
    var params = XBarParams.defaults

    for part in paramParts {
      let trimmed = part.trimmingCharacters(in: .whitespaces)
      guard let equalsIndex = trimmed.firstIndex(of: "=") else { continue }

      let key = String(trimmed[trimmed.startIndex..<equalsIndex])
        .trimmingCharacters(in: .whitespaces)
        .lowercased()
      var value = String(trimmed[trimmed.index(after: equalsIndex)...])
        .trimmingCharacters(in: .whitespaces)

      // Remove surrounding quotes
      if (value.hasPrefix("\"") && value.hasSuffix("\""))
        || (value.hasPrefix("'") && value.hasSuffix("'"))
      {
        value = String(value.dropFirst().dropLast())
      }

      switch key {
      case "href": params.href = value
      case "color": params.color = value
      case "font": params.font = value
      case "size": params.size = CGFloat(Double(value) ?? 0)
      case "shell": params.shell = value
      case "terminal": params.terminal = value.lowercased() == "true"
      case "refresh": params.refresh = value.lowercased() == "true"
      case "dropdown": params.dropdown = value.lowercased() != "false"
      case "length": params.length = Int(value)
      case "trim": params.trim = value.lowercased() != "false"
      case "alternate": params.alternate = value.lowercased() == "true"
      case "image": params.image = value
      case "templateimage": params.templateImage = value
      case "disabled": params.disabled = value.lowercased() == "true"
      case "key": params.key = value
      case "ansi": params.ansi = value.lowercased() != "false"
      case "emojize": params.emojize = value.lowercased() != "false"
      default:
        if key.hasPrefix("param"), let num = Int(key.dropFirst(5)), num > 0 {
          while params.shellParams.count < num {
            params.shellParams.append("")
          }
          params.shellParams[num - 1] = value
        }
      }
    }

    let finalTitle = params.trim ? rawTitle.trimmingCharacters(in: .whitespaces) : rawTitle

    return XBarLineItem(
      title: finalTitle,
      level: level,
      isSeparator: false,
      params: params
    )
  }

  /// Split a string by pipe character, respecting quoted strings
  private static func splitByPipe(_ string: String) -> [String] {
    var parts: [String] = []
    var current = ""
    var inQuote: Character? = nil

    for char in string {
      if let q = inQuote {
        current.append(char)
        if char == q { inQuote = nil }
      } else if char == "\"" || char == "'" {
        current.append(char)
        inQuote = char
      } else if char == "|" {
        parts.append(current)
        current = ""
      } else {
        current.append(char)
      }
    }
    parts.append(current)

    return parts
  }
}

/// Handles actions for xbar dropdown menu items
class XBarMenuActionHandler: NSObject {
  var onRefresh: (() -> Void)?

  @objc func handleAction(_ sender: NSMenuItem) {
    guard let item = sender.representedObject as? XBarLineItemWrapper else { return }
    let params = item.lineItem.params

    if let href = params.href, let url = URL(string: href) {
      NSWorkspace.shared.open(url)
    }

    if let shell = params.shell {
      Task {
        var cmd = shell
        for param in params.shellParams where !param.isEmpty {
          cmd += " " + param
        }
        _ = try? await ShellExecutor.run(cmd)
        if params.refresh {
          await MainActor.run { self.onRefresh?() }
        }
      }
    } else if params.refresh {
      onRefresh?()
    }
  }

  @objc func retryAction(_ sender: NSMenuItem) {
    onRefresh?()
  }
}

/// Wrapper to store XBarLineItem as NSMenuItem.representedObject
class XBarLineItemWrapper: NSObject {
  let lineItem: XBarLineItem
  init(_ lineItem: XBarLineItem) {
    self.lineItem = lineItem
  }
}

/// Builds an NSMenu from parsed xbar output
enum XBarMenuBuilder {

  static func buildMenu(
    from output: XBarParsedOutput, handler: XBarMenuActionHandler
  ) -> NSMenu {
    let menu = NSMenu()
    menu.autoenablesItems = false

    var itemsToShow: [XBarLineItem] = []

    if output.menuItems.isEmpty {
      // No --- separator: show header lines with dropdown=true
      itemsToShow = output.headerLines.filter { $0.params.dropdown }
    } else {
      let dropdownHeaders = output.headerLines.filter { $0.params.dropdown }
      if !dropdownHeaders.isEmpty {
        itemsToShow.append(contentsOf: dropdownHeaders)
        itemsToShow.append(
          XBarLineItem(title: "", level: 0, isSeparator: true, params: .defaults))
      }
      itemsToShow.append(contentsOf: output.menuItems)
    }

    buildMenuItems(menu: menu, items: itemsToShow, handler: handler)
    return menu
  }

  private static func buildMenuItems(
    menu: NSMenu, items: [XBarLineItem], handler: XBarMenuActionHandler
  ) {
    // Stack: (menu, level). Level -1 = root.
    var stack: [(NSMenu, Int)] = [(menu, -1)]

    for item in items {
      if item.isSeparator {
        // Pop the stack back to the root menu so the separator is added to the
        // correct parent, not to the last item's pre-allocated submenu.
        while stack.count > 1 && stack.last!.1 >= 0 {
          stack.removeLast()
        }
        stack.last?.0.addItem(.separator())
        continue
      }

      // Pop stack to find the correct parent
      while stack.count > 1 && stack.last!.1 >= item.level {
        stack.removeLast()
      }

      let parentMenu = stack.last!.0
      let nsItem = createMenuItem(from: item, handler: handler)
      parentMenu.addItem(nsItem)

      // Prepare a potential submenu for children
      let submenu = NSMenu()
      nsItem.submenu = submenu
      stack.append((submenu, item.level))
    }

    // Remove empty submenus
    cleanEmptySubmenus(menu)
  }

  private static func cleanEmptySubmenus(_ menu: NSMenu) {
    for item in menu.items {
      if let sub = item.submenu {
        if sub.items.isEmpty {
          item.submenu = nil
        } else {
          cleanEmptySubmenus(sub)
        }
      }
    }
  }

  private static func createMenuItem(
    from item: XBarLineItem, handler: XBarMenuActionHandler
  ) -> NSMenuItem {
    let menuItem = NSMenuItem()

    // Build attributed title
    let displayText = truncatedTitle(item)
    let attrs = buildAttributes(from: item.params)
    menuItem.attributedTitle = NSAttributedString(string: displayText, attributes: attrs)

    // Tooltip for truncated text
    if let maxLen = item.params.length, item.title.count > maxLen {
      menuItem.toolTip = item.title
    }

    // Image
    if let imageB64 = item.params.image,
      let data = Data(base64Encoded: imageB64),
      let image = NSImage(data: data)
    {
      image.size = NSSize(width: 16, height: 16)
      menuItem.image = image
    } else if let templateB64 = item.params.templateImage,
      let data = Data(base64Encoded: templateB64),
      let image = NSImage(data: data)
    {
      image.isTemplate = true
      image.size = NSSize(width: 16, height: 16)
      menuItem.image = image
    }

    // Disabled state
    menuItem.isEnabled = !item.params.disabled

    // Alternate (Option key)
    if item.params.alternate {
      menuItem.isAlternate = true
      menuItem.keyEquivalentModifierMask = .option
    }

    // Key shortcut
    if let key = item.params.key {
      let (keyEquiv, mods) = parseKeyShortcut(key)
      menuItem.keyEquivalent = keyEquiv
      menuItem.keyEquivalentModifierMask = mods
    }

    // Action (only if the item has something to do)
    let hasAction = item.params.href != nil || item.params.shell != nil || item.params.refresh
    if hasAction && !item.params.disabled {
      menuItem.target = handler
      menuItem.action = #selector(XBarMenuActionHandler.handleAction(_:))
      menuItem.representedObject = XBarLineItemWrapper(item)
    }

    return menuItem
  }

  private static func truncatedTitle(_ item: XBarLineItem) -> String {
    guard let maxLen = item.params.length, item.title.count > maxLen else {
      return item.title
    }
    return String(item.title.prefix(maxLen)) + "…"
  }

  private static func buildAttributes(from params: XBarParams) -> [NSAttributedString.Key: Any] {
    var attrs: [NSAttributedString.Key: Any] = [:]

    if let colorStr = params.color, let color = NSColor(xbarString: colorStr) {
      attrs[.foregroundColor] = color
    }

    let fontSize = params.size ?? NSFont.menuFont(ofSize: 0).pointSize
    if let fontName = params.font {
      attrs[.font] = NSFont(name: fontName, size: fontSize) ?? NSFont.menuFont(ofSize: fontSize)
    } else if params.size != nil {
      attrs[.font] = NSFont.menuFont(ofSize: fontSize)
    }

    return attrs
  }

  private static func parseKeyShortcut(_ shortcut: String) -> (String, NSEvent.ModifierFlags) {
    let parts = shortcut.components(separatedBy: "+")
    var modifiers: NSEvent.ModifierFlags = []
    var key = ""

    for part in parts {
      let p = part.trimmingCharacters(in: .whitespaces).lowercased()
      switch p {
      case "cmdorctrl", "cmd", "command": modifiers.insert(.command)
      case "optionoralt", "option", "alt": modifiers.insert(.option)
      case "shift": modifiers.insert(.shift)
      case "ctrl", "control": modifiers.insert(.control)
      case "return", "enter": key = "\r"
      case "escape", "esc": key = "\u{1B}"
      case "tab": key = "\t"
      case "space": key = " "
      case "plus": key = "+"
      default:
        if p.count == 1 {
          key = p
        }
      }
    }

    return (key, modifiers)
  }
}

extension NSColor {
  /// Parse xbar color strings: named colors, #hex, rgb(), rgba()
  convenience init?(xbarString: String) {
    let trimmed = xbarString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

    // Named colors (CSS-like subset)
    let namedColors: [String: NSColor] = [
      "red": .systemRed, "blue": .systemBlue, "green": .systemGreen,
      "yellow": .systemYellow, "orange": .systemOrange, "purple": .systemPurple,
      "pink": .systemPink, "white": .white, "black": .black,
      "gray": .systemGray, "grey": .systemGray, "cyan": .cyan,
      "magenta": .magenta, "brown": .systemBrown, "teal": .systemTeal,
      "indigo": .systemIndigo, "mint": .systemMint,
      "cadetblue": NSColor(red: 95 / 255, green: 158 / 255, blue: 160 / 255, alpha: 1),
    ]

    if let named = namedColors[trimmed] {
      self.init(cgColor: named.cgColor)
      return
    }

    // Hex: #RGB, #RRGGBB, #RRGGBBAA
    if trimmed.hasPrefix("#") {
      let hex = String(trimmed.dropFirst())
      var hexValue: UInt64 = 0
      guard Scanner(string: hex).scanHexInt64(&hexValue) else { return nil }

      let r, g, b, a: CGFloat
      switch hex.count {
      case 3:
        r = CGFloat((hexValue >> 8) & 0xF) / 15
        g = CGFloat((hexValue >> 4) & 0xF) / 15
        b = CGFloat(hexValue & 0xF) / 15
        a = 1
      case 6:
        r = CGFloat((hexValue >> 16) & 0xFF) / 255
        g = CGFloat((hexValue >> 8) & 0xFF) / 255
        b = CGFloat(hexValue & 0xFF) / 255
        a = 1
      case 8:
        r = CGFloat((hexValue >> 24) & 0xFF) / 255
        g = CGFloat((hexValue >> 16) & 0xFF) / 255
        b = CGFloat((hexValue >> 8) & 0xFF) / 255
        a = CGFloat(hexValue & 0xFF) / 255
      default:
        return nil
      }
      self.init(red: r, green: g, blue: b, alpha: a)
      return
    }

    // rgb(r, g, b) / rgba(r, g, b, a)
    if trimmed.hasPrefix("rgb") {
      let pattern = #"rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(?:,\s*([\d.]+)\s*)?\)"#
      guard let regex = try? NSRegularExpression(pattern: pattern),
        let match = regex.firstMatch(
          in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
        match.numberOfRanges >= 4
      else { return nil }

      func extractInt(_ index: Int) -> Int? {
        guard let range = Range(match.range(at: index), in: trimmed) else { return nil }
        return Int(trimmed[range])
      }
      func extractDouble(_ index: Int) -> Double? {
        guard match.numberOfRanges > index,
          let range = Range(match.range(at: index), in: trimmed)
        else { return nil }
        return Double(trimmed[range])
      }

      guard let rv = extractInt(1), let gv = extractInt(2), let bv = extractInt(3) else {
        return nil
      }
      let av = extractDouble(4) ?? 1.0

      self.init(
        red: CGFloat(rv) / 255, green: CGFloat(gv) / 255,
        blue: CGFloat(bv) / 255, alpha: CGFloat(av))
      return
    }

    return nil
  }
}
