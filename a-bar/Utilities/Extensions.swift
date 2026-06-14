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
}

protocol ABarSettingsBindable {
    var settings: SettingsManager { get }
}

extension ABarSettingsBindable {
    func binding<T>(_ keyPath: WritableKeyPath<ABarSettings, T>) -> Binding<T> {
        Binding(
            get: { settings.draftSettings[keyPath: keyPath] },
            set: { settings.draftSettings[keyPath: keyPath] = $0 }
        )
    }
}

extension GlobalSettings {
    func settingsFont(
        scaledBy factor: Double = 1.0,
        weight: Font.Weight? = nil,
        design: Font.Design? = nil
    ) -> Font {
        let size = CGFloat(Double(fontSize) * factor)

        if !fontName.isEmpty {
            return .custom(fontName, size: size)
        }

        if let design = design, let weight = weight {
            return .system(size: size, weight: weight, design: design)
        }

        if let weight = weight {
            return .system(size: size, weight: weight)
        }

        return .system(size: size)
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

extension Double {
    /// Format transfer speed as B/s, K/s, M/s, or G/s.
    func formattedTransferRate(spacedUnits: Bool = false) -> String {
        let sep = spacedUnits ? " " : ""
        if self < 1024 {
            return String(format: "%.0f%@B/s", self, sep)
        }
        if self < 1024 * 1024 {
            return String(format: "%.1f%@K/s", self / 1024, sep)
        }
        if self < 1024 * 1024 * 1024 {
            return String(format: "%.1f%@M/s", self / 1024 / 1024, sep)
        }
        return String(format: "%.1f%@G/s", self / 1024 / 1024 / 1024, sep)
    }
}

extension Animation {
    static var abarFast: Animation {
        .easeInOut(duration: 0.32)
    }
}

/// Shared click-outside monitor used by popover-style widgets.
final class OutsideClickMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var handler: (() -> Void)?

    func start(_ handler: @escaping () -> Void) {
        stop()
        self.handler = handler

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.handle(event: event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.handle(event: event)
            return event
        }
    }

    func stop() {
        if let globalMonitor = globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor = localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        handler = nil
    }

    private func handle(event: NSEvent) {
        let windowNumber = event.windowNumber
        if NSApp.windows.contains(where: { $0.windowNumber == windowNumber }) {
            return
        }
        handler?()
    }
}
