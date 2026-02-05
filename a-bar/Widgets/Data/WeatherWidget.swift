import SwiftUI

/// Weather widget showing current conditions
struct WeatherWidget: View {
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.widgetOrientation) var orientation

    @State private var weatherData: WeatherData?
    @State private var lastWeatherData: WeatherData?
    @State private var isLoading = true
    @State private var location: String = ""

    private var weatherSettings: WeatherWidgetSettings {
        settings.settings.widgets.weather
    }

    private var theme: ABarTheme {
        ThemeManager.currentTheme(for: settings.settings.theme)
    }

    private var globalSettings: GlobalSettings {
        settings.settings.global
    }

    private var isVertical: Bool {
        orientation == .vertical
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

    var body: some View {
        BaseWidgetView(onRightClick: refreshWeather) {
            if isLoading {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 16, height: 16)
            } else if let data = (weatherData ?? lastWeatherData) {
                AdaptiveStack(hSpacing: 4, vSpacing: 2) {
                    if weatherSettings.showIcon {
                        weatherIcon(for: data.description, atNight: data.isNight)
                    }

                    Text(temperatureString(weatherSettings.unit == .fahrenheit ? data.temperatureF : data.temperatureC))
                        .foregroundColor(theme.foreground)

                    // Hide location in vertical mode
                    if !weatherSettings.hideLocation && !isVertical {
                            Text(location.truncated(to: 15))
                                .font(settingsFont(scaledBy: 0.75))
                                .foregroundColor(theme.minor)
                    }
                }
            } else {
                AdaptiveStack(hSpacing: 4, vSpacing: 2) {
                    if weatherSettings.showIcon {
                        Image(systemName: "cloud.fill")
                            .font(.system(size: 10))
                            .foregroundColor(theme.minor)
                    }
                    Text("--°")
                        .foregroundColor(theme.minor)
                }
            }
        }
        .onAppear {
            if weatherData == nil {
                refreshWeather()
            }
        }
        .onReceive(Timer.publish(every: weatherSettings.refreshInterval, on: .main, in: .common).autoconnect()) { _ in
            refreshWeather()
        }
    }
    
    private func refreshWeather() {
        isLoading = true
        
        Task {
            do {
                let loc = weatherSettings.customLocation.isEmpty ? await getLocation() : weatherSettings.customLocation
                location = loc
                
                let data = try await fetchWeather(for: loc)
                await MainActor.run {
                    weatherData = data
                    lastWeatherData = data
                    isLoading = false
                }
            } catch {
                print("Weather fetch error: \(error)")
                await MainActor.run {
                    // Keep showing last successful data if available
                    if weatherData == nil, let last = lastWeatherData {
                        weatherData = last
                    }
                    isLoading = false
                }
            }
        }
    }
    
    private func getLocation() async -> String {
        // Try to get location from IP geolocation
        do {
            let output = try await ShellExecutor.run("curl -s 'http://ip-api.com/json/?fields=city,zip' 2>/dev/null")
            if let data = output.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Prefer city name (works better with Open-Meteo geocoding); fallback to zip
                if let city = json["city"] as? String, !city.isEmpty {
                    return city
                }
                if let zip = json["zip"] as? String, !zip.isEmpty {
                    return zip
                }
            }
        } catch {
            print("Location fetch error: \(error)")
        }
        return "London" // Default fallback
    }
    
    private func fetchWeather(for location: String) async throws -> WeatherData {
        // Try Open-Meteo geocoding with multiple location variants to improve match rate
        var lat: Double? = nil
        var lon: Double? = nil

        func generateVariants(_ loc: String) -> [String] {
            var variants: [String] = []
            let trimmed = loc.trimmingCharacters(in: .whitespacesAndNewlines)
            variants.append(trimmed)

            // Split on commas and try progressively shorter forms
            let parts = trimmed.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if parts.count > 1 {
                variants.append(parts[0])
                if parts.count >= 2 {
                    variants.append(parts[0] + ", " + parts[1])
                }
            }

            // Remove digits (postal codes) and hyphens, try without diacritics
            let noDigits = trimmed.replacingOccurrences(of: "\\d+", with: "", options: .regularExpression)
            variants.append(noDigits.replacingOccurrences(of: "-", with: " ").trimmingCharacters(in: .whitespacesAndNewlines))

            // Remove diacritics
            let folded = trimmed.folding(options: .diacriticInsensitive, locale: .current)
            if folded != trimmed { variants.append(folded) }

            // Deduplicate preserving order
            var seen = Set<String>()
            return variants.filter { s in
                let ok = !s.isEmpty && !seen.contains(s)
                if ok { seen.insert(s) }
                return ok
            }
        }

        let candidates = generateVariants(location)
        for candidate in candidates {
            do {
                let geoUrl = URL(string: "https://geocoding-api.open-meteo.com/v1/search?name=\(candidate.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? candidate)&count=1")!
                let (geoData, _) = try await URLSession.shared.data(from: geoUrl)
                if let geoJson = try? JSONSerialization.jsonObject(with: geoData) as? [String: Any],
                   let results = geoJson["results"] as? [[String: Any]],
                   let first = results.first,
                   let gLat = first["latitude"] as? Double,
                   let gLon = first["longitude"] as? Double {
                    lat = gLat
                    lon = gLon
                    break
                } else {
                    
                }
            } catch {
            }
        }

        // Fallback to Nominatim (OpenStreetMap) if Open-Meteo geocoding failed
        if lat == nil || lon == nil {
            do {
                let nominatimUrl = URL(string: "https://nominatim.openstreetmap.org/search?format=json&q=\(location.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? location)&limit=1")!
                var req = URLRequest(url: nominatimUrl)
                req.setValue("a-bar/1.0 (your-email@example.com)", forHTTPHeaderField: "User-Agent")
                let (nomData, _) = try await URLSession.shared.data(for: req)
                if let nomJson = try? JSONSerialization.jsonObject(with: nomData) as? [[String: Any]],
                   let first = nomJson.first,
                   let latStr = first["lat"] as? String,
                   let lonStr = first["lon"] as? String,
                   let nLat = Double(latStr),
                   let nLon = Double(lonStr) {
                    lat = nLat
                    lon = nLon
                } else {
                    
                }
            } catch {
            }
        }

        guard let finalLat = lat, let finalLon = lon else {
            throw NSError(domain: "Weather", code: 2, userInfo: [NSLocalizedDescriptionKey: "Location not found"])
        }

        // Use Open-Meteo Weather API to get current weather
        let unit = weatherSettings.unit == .celsius ? "celsius" : "fahrenheit"
        let tempParam = "temperature_2m"
        let weatherUrl = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(finalLat)&longitude=\(finalLon)&current_weather=true&hourly=weathercode,\(tempParam)&temperature_unit=\(unit)")!
                let (weatherData, _) = try await URLSession.shared.data(from: weatherUrl)
                guard let weatherJson = try? JSONSerialization.jsonObject(with: weatherData) as? [String: Any],
                            let current = weatherJson["current_weather"] as? [String: Any],
                            let temp = current["temperature"] as? Double,
                            let weatherCode = current["weathercode"] as? Int,
                            let isDay = current["is_day"] as? Int else {
                        
                        throw NSError(domain: "Weather", code: 3, userInfo: [NSLocalizedDescriptionKey: "Weather data not found"])
                }

        // Use is_day (1=day, 0=night) from Open-Meteo
        let isNight = isDay == 0

        // Map Open-Meteo weathercode to description
        let description = openMeteoDescription(for: weatherCode)

        let tempC = weatherSettings.unit == .celsius ? Int(round(temp)) : Int(round((temp - 32) * 5 / 9))
        let tempF = weatherSettings.unit == .fahrenheit ? Int(round(temp)) : Int(round((temp * 9 / 5) + 32))

        return WeatherData(
            temperatureC: tempC,
            temperatureF: tempF,
            description: description,
            isNight: isNight
        )
    }

    // Open-Meteo weathercode mapping
    private func openMeteoDescription(for code: Int) -> String {
        switch code {
        case 0: return "Clear sky"
        case 1, 2, 3: return "Mainly clear"
        case 45, 48: return "Fog"
        case 51, 53, 55: return "Drizzle"
        case 56, 57: return "Freezing Drizzle"
        case 61, 63, 65: return "Rain"
        case 66, 67: return "Freezing Rain"
        case 71, 73, 75, 77: return "Snow"
        case 80, 81, 82: return "Rain showers"
        case 85, 86: return "Snow showers"
        case 95: return "Thunderstorm"
        case 96, 99: return "Thunderstorm with hail"
        default: return "Unknown"
        }
    }
    
    private func checkIfNight(sunrise: String, sunset: String) -> Bool {
        let formatter = DateFormatter()
        formatter.dateFormat = "hh:mm a"
        
        let now = Date()
        let calendar = Calendar.current
        
        guard let sunriseTime = formatter.date(from: sunrise),
              let sunsetTime = formatter.date(from: sunset) else {
            return false
        }
        
        // Create dates for today
        var sunriseComponents = calendar.dateComponents([.hour, .minute], from: sunriseTime)
        var sunsetComponents = calendar.dateComponents([.hour, .minute], from: sunsetTime)
        
        let todayComponents = calendar.dateComponents([.year, .month, .day], from: now)
        sunriseComponents.year = todayComponents.year
        sunriseComponents.month = todayComponents.month
        sunriseComponents.day = todayComponents.day
        
        sunsetComponents.year = todayComponents.year
        sunsetComponents.month = todayComponents.month
        sunsetComponents.day = todayComponents.day
        
        guard let todaySunrise = calendar.date(from: sunriseComponents),
              let todaySunset = calendar.date(from: sunsetComponents) else {
            return false
        }
        
        return now < todaySunrise || now > todaySunset
    }
    
    private func temperatureString(_ temp: Int) -> String {
        "\(temp)°\(weatherSettings.unit.rawValue)"
    }
    
    private func weatherIcon(for description: String, atNight: Bool) -> some View {
        let lowercased = description.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var iconName: String? = nil
        var iconColor: Color = theme.foreground

        if lowercased.contains("sun") || lowercased.contains("clear") {
            iconName = atNight ? "moon.fill" : "sun.max.fill"
            iconColor = theme.yellow
        } else if lowercased.contains("cloud") && lowercased.contains("sun") {
            iconName = atNight ? "cloud.moon.fill" : "cloud.sun.fill"
        } else if lowercased.contains("cloud") {
            iconName = "cloud.fill"
        } else if lowercased.contains("rain") || lowercased.contains("drizzle") {
            iconName = "cloud.rain.fill"
            iconColor = theme.blue
        } else if lowercased.contains("thunder") || lowercased.contains("storm") {
            iconName = "cloud.bolt.fill"
            iconColor = theme.yellow
        } else if lowercased.contains("snow") {
            iconName = "cloud.snow.fill"
            iconColor = theme.cyan
        } else if lowercased.contains("fog") || lowercased.contains("mist") {
            iconName = "cloud.fog.fill"
        }

        // Final fallback to a known-good SF Symbol
        if iconName == nil || iconName?.isEmpty == true {
            iconName = atNight ? "moon.fill" : "cloud.fill"
        }

        return Image(systemName: iconName!)
            .font(.system(size: 12))
            .foregroundColor(iconColor)
    }
}

struct WeatherData {
    let temperatureC: Int
    let temperatureF: Int
    let description: String
    let isNight: Bool
    
    var temperature: Int {
        // Deprecated: use temperatureC or temperatureF directly
        temperatureC
    }
}
