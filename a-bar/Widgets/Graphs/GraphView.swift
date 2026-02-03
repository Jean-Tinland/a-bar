import SwiftUI

/// A reusable graph view for displaying time-series data
struct GraphView: View {
    let values: [Double]
    let maxValue: Double
    let fillColor: Color
    let lineColor: Color
    let showLabels: Bool
    let labelPrefix: String

    @EnvironmentObject var settings: SettingsManager

    private var theme: ABarTheme {
        ThemeManager.currentTheme(for: settings.settings.theme)
    }

    private var globalSettings: GlobalSettings {
        settings.settings.global
    }

    private func settingsFont(scaledBy factor: Double = 1.0, weight: Font.Weight? = nil, design: Font.Design? = nil) -> Font {
        let size = CGFloat(Double(globalSettings.fontSize) * factor)
        if globalSettings.fontName.isEmpty {
            if let weight = weight {
                if let design = design {
                    return .system(size: size, weight: weight, design: design)
                }
                return .system(size: size, weight: weight)
            }
            return .system(size: size)
        }
        return .custom(globalSettings.fontName, size: size)
    }

    init(
        values: [Double],
        maxValue: Double = 100.0,
        fillColor: Color = .blue,
        lineColor: Color = .blue,
        showLabels: Bool = false,
        labelPrefix: String = ""
    ) {
        self.values = values
        self.maxValue = maxValue
        self.fillColor = fillColor
        self.lineColor = lineColor
        self.showLabels = showLabels
        self.labelPrefix = labelPrefix
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 2)
                    .fill(theme.minor.opacity(0.2))

                // Graph fill
                Path { path in
                    guard !values.isEmpty else { return }

                    let width = geometry.size.width
                    let height = geometry.size.height
                    let stepX = width / CGFloat(max(1, values.count - 1))

                    path.move(to: CGPoint(x: 0, y: height))

                    for (index, value) in values.enumerated() {
                        let x = CGFloat(index) * stepX
                        let y = height - (CGFloat(value / maxValue) * height)
                        path.addLine(to: CGPoint(x: x, y: y))
                    }

                    path.addLine(to: CGPoint(x: width, y: height))
                    path.closeSubpath()
                }
                .fill(fillColor.opacity(0.3))

                // Graph line
                Path { path in
                    guard !values.isEmpty else { return }

                    let width = geometry.size.width
                    let height = geometry.size.height
                    let stepX = width / CGFloat(max(1, values.count - 1))

                    for (index, value) in values.enumerated() {
                        let x = CGFloat(index) * stepX
                        let y = height - (CGFloat(value / maxValue) * height)

                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(lineColor, lineWidth: 1)

                // Current value label
                if showLabels, let lastValue = values.last {
                    Text("\(labelPrefix)\(Int(lastValue))%")
                        .font(settingsFont(scaledBy: 0.6))
                        .foregroundColor(theme.foreground)
                        .padding(1)
                        .background(theme.background.opacity(0.7))
                        .cornerRadius(2)
                        .position(x: geometry.size.width, y: 6)
                }
            }
        }
    }
}

/// A pie chart view for memory usage
struct PieChartView: View {
    let usedPercentage: Double
    let usedColor: Color
    let freeColor: Color

    @EnvironmentObject var settings: SettingsManager

    private var theme: ABarTheme {
        ThemeManager.currentTheme(for: settings.settings.theme)
    }

    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let radius = min(geometry.size.width, geometry.size.height) / 2 - 1

            ZStack {
                // Free space
                Circle()
                    .fill(freeColor.opacity(0.3))

                // Used space (pie slice)
                Path { path in
                    path.move(to: center)
                    path.addArc(
                        center: center,
                        radius: radius,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(-90 + (usedPercentage / 100 * 360)),
                        clockwise: false
                    )
                    path.closeSubpath()
                }
                .fill(usedColor)

                // Border
                Circle()
                    .stroke(theme.minor.opacity(0.5), lineWidth: 0.5)
            }
        }
    }
}

/// A bar graph for showing current values
struct BarGraphView: View {
    let value: Double
    let maxValue: Double
    let fillColor: Color
    let vertical: Bool

    @EnvironmentObject var settings: SettingsManager

    private var theme: ABarTheme {
        ThemeManager.currentTheme(for: settings.settings.theme)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: vertical ? .bottom : .leading) {
                // Background
                RoundedRectangle(cornerRadius: 2)
                    .fill(theme.minor.opacity(0.2))

                // Fill
                RoundedRectangle(cornerRadius: 2)
                    .fill(fillColor)
                    .frame(
                        width: vertical ? nil : geometry.size.width * CGFloat(value / maxValue),
                        height: vertical ? geometry.size.height * CGFloat(value / maxValue) : nil
                    )
            }
        }
    }
}
