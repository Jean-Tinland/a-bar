import Foundation
import SwiftUI
import AppKit

extension Color {
    /// Initialize Color from a CSS-style color string
    /// Supports: hex (#RGB, #RRGGBB, #RRGGBBAA), rgb(), rgba(), and named colors
    init?(cssString: String) {
        let trimmed = cssString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // Named colors
        let namedColors: [String: Color] = [
            "red": .red, "blue": .blue, "green": .green, "yellow": .yellow,
            "orange": .orange, "purple": .purple, "pink": .pink, "white": .white,
            "black": .black, "gray": .gray, "grey": .gray, "cyan": .cyan,
            "mint": .mint, "teal": .teal, "indigo": .indigo, "brown": .brown,
            "clear": .clear
        ]
        
        if let named = namedColors[trimmed] {
            self = named
            return
        }
        
        // Hex color (#RGB, #RRGGBB, #RRGGBBAA)
        if trimmed.hasPrefix("#") {
            let hex = String(trimmed.dropFirst())
            var hexValue: UInt64 = 0
            guard Scanner(string: hex).scanHexInt64(&hexValue) else { return nil }
            
            let r, g, b, a: Double
            switch hex.count {
            case 3: // #RGB
                r = Double((hexValue >> 8) & 0xF) / 15.0
                g = Double((hexValue >> 4) & 0xF) / 15.0
                b = Double(hexValue & 0xF) / 15.0
                a = 1.0
            case 6: // #RRGGBB
                r = Double((hexValue >> 16) & 0xFF) / 255.0
                g = Double((hexValue >> 8) & 0xFF) / 255.0
                b = Double(hexValue & 0xFF) / 255.0
                a = 1.0
            case 8: // #RRGGBBAA
                r = Double((hexValue >> 24) & 0xFF) / 255.0
                g = Double((hexValue >> 16) & 0xFF) / 255.0
                b = Double((hexValue >> 8) & 0xFF) / 255.0
                a = Double(hexValue & 0xFF) / 255.0
            default:
                return nil
            }
            self = Color(red: r, green: g, blue: b, opacity: a)
            return
        }
        
        // rgb(r, g, b) or rgba(r, g, b, a)
        if trimmed.hasPrefix("rgb") {
            let pattern = #"rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(?:,\s*([\d.]+)\s*)?\)"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
                  match.numberOfRanges >= 4 else { return nil }
            
            func extractInt(_ index: Int) -> Int? {
                guard let range = Range(match.range(at: index), in: trimmed) else { return nil }
                return Int(trimmed[range])
            }
            func extractDouble(_ index: Int) -> Double? {
                guard match.numberOfRanges > index,
                      let range = Range(match.range(at: index), in: trimmed) else { return nil }
                return Double(trimmed[range])
            }
            
            guard let r = extractInt(1), let g = extractInt(2), let b = extractInt(3) else { return nil }
            let a = extractDouble(4) ?? 1.0
            
            self = Color(red: Double(r) / 255.0, green: Double(g) / 255.0, blue: Double(b) / 255.0, opacity: a)
            return
        }
        
        return nil
    }
}

extension View {
    /// Apply a modifier conditionally
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
    
    /// Apply a modifier if a value is non-nil
    @ViewBuilder
    func ifLet<Value, Content: View>(_ value: Value?, transform: (Self, Value) -> Content) -> some View {
        if let value = value {
            transform(self, value)
        } else {
            self
        }
    }
}

extension String {
    /// Truncate string to a maximum length with ellipsis
    func truncated(to length: Int, trailing: String = "…") -> String {
        if self.count > length {
            return String(self.prefix(length)) + trailing
        }
        return self
    }
    
    /// Check if string matches a regex pattern
    func matches(pattern: String) -> Bool {
        return self.range(of: pattern, options: .regularExpression) != nil
    }
}

extension Date {
    /// Format date with the given format string
    func formatted(as format: String, locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.locale = locale
        return formatter.string(from: self)
    }
    
    /// Get progress through the day (0.0 to 1.0)
    var dayProgress: Double {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: self)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        let totalSeconds = endOfDay.timeIntervalSince(startOfDay)
        let elapsedSeconds = self.timeIntervalSince(startOfDay)
        return elapsedSeconds / totalSeconds
    }
}

extension Collection {
    /// Safe subscript that returns nil instead of crashing for out of bounds
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

extension Array where Element: Equatable {
    /// Remove duplicates while preserving order
    func uniqued() -> [Element] {
        var seen = [Element]()
        return filter { element in
            if seen.contains(element) {
                return false
            }
            seen.append(element)
            return true
        }
    }
}

extension Double {
    /// Format as percentage
    var percentageString: String {
        return "\(Int(self))%"
    }
    
    /// Format with fixed decimal places
    func formatted(decimals: Int) -> String {
        return String(format: "%.\(decimals)f", self)
    }
}

extension Int {
    /// Format as human readable byte count
    var formattedBytes: String {
        ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .binary)
    }
}

extension UInt64 {
    /// Format as human readable byte count
    var formattedBytes: String {
        ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .binary)
    }
}

extension NSScreen {
    /// Get the screen index (0-based)
    var screenIndex: Int {
        return NSScreen.screens.firstIndex(of: self) ?? 0
    }
    
    /// Check if this is the main screen
    var isMainScreen: Bool {
        return self == NSScreen.main
    }
}

import Combine

extension Publisher {
    /// Debounce and receive on main thread
    func debounceOnMain(for dueTime: RunLoop.SchedulerTimeType.Stride) -> AnyPublisher<Output, Failure> {
        return self
            .debounce(for: dueTime, scheduler: RunLoop.main)
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
}

extension Animation {
    static var abarDefault: Animation {
        .easeInOut(duration: 0.48)
    }
    
    static var abarFast: Animation {
        .easeInOut(duration: 0.32)
    }
    
    static var abarSlow: Animation {
        .easeInOut(duration: 0.64)
    }
}

extension Notification.Name {
    static let abarRefreshAll = Notification.Name("abar.refresh.all")
    static let abarRefreshYabai = Notification.Name("abar.refresh.yabai")
    static let abarRefreshWidget = Notification.Name("abar.refresh.widget")
    static let abarSettingsChanged = Notification.Name("abar.settings.changed")
}

enum UserDefaultsKey {
    static let settings = "abar-settings"
    static let layout = "abar-layout"
    static let userWidgets = "abar-user-widgets"
    static let firstLaunch = "abar-first-launch"
}

enum ABarError: LocalizedError {
    case yabaiNotFound
    case yabaiCommandFailed(String)
    case settingsCorrupted
    case widgetRefreshFailed(String)
    case networkError(String)
    
    var errorDescription: String? {
        switch self {
        case .yabaiNotFound:
            return "yabai executable not found at the specified path"
        case .yabaiCommandFailed(let message):
            return "yabai command failed: \(message)"
        case .settingsCorrupted:
            return "Settings file is corrupted"
        case .widgetRefreshFailed(let widget):
            return "Failed to refresh widget: \(widget)"
        case .networkError(let message):
            return "Network error: \(message)"
        }
    }
}
