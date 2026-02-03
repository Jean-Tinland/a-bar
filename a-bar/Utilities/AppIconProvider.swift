import AppKit
import SwiftUI

/// Provides native application icons for windows
class AppIconProvider {
    static let shared = AppIconProvider()
    
    private var iconCache: [String: NSImage] = [:]
    private let queue = DispatchQueue(label: "com.abar.icon-provider", attributes: .concurrent)
    
    private init() {}
    
    /// Get the icon for an application by name
    func icon(forApp appName: String) -> NSImage? {
        // Check cache first
        if let cached = queue.sync(execute: { iconCache[appName] }) {
            return cached
        }
        
        // Try to find the app and get its icon
        if let icon = findAppIcon(appName: appName) {
            queue.async(flags: .barrier) {
                self.iconCache[appName] = icon
            }
            return icon
        }
        
        return nil
    }
    
    /// Get a SwiftUI Image for an application
    func iconImage(forApp appName: String, size: CGFloat = 16) -> Image {
        if let nsImage = icon(forApp: appName) {
            return Image(nsImage: resizedIcon(nsImage, to: size))
        }
        return Image(systemName: "app.fill")
    }
    
    private func findAppIcon(appName: String) -> NSImage? {
        // 1. PRIORITY: Get icon from running applications
        // This is most likely to respect system icon tinting preferences
        if let runningApp = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == appName }) {
            if let icon = runningApp.icon {
                return icon
            }
            // Also try getting icon from the bundle if the app is running
            if let bundleURL = runningApp.bundleURL {
                let icon = NSWorkspace.shared.icon(forFile: bundleURL.path)
                return icon
            }
        }

        // 2. Search in Applications folders
        let searchPaths = [
            "/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
            NSHomeDirectory() + "/Applications"
        ]
        for path in searchPaths {
            let appPath = "\(path)/\(appName).app"
            if FileManager.default.fileExists(atPath: appPath) {
                return NSWorkspace.shared.icon(forFile: appPath)
            }
        }

        // 3. Use mdfind to locate the app by display name
        if let appPath = findAppPath(appName: appName) {
            return NSWorkspace.shared.icon(forFile: appPath)
        }

        return nil
    }
    
    private func findAppPath(appName: String) -> String? {
        let command = "mdfind 'kMDItemKind == \"Application\" && kMDItemDisplayName == \"\(appName)\"' | head -1"
        let result = ShellExecutor.runSync(command)
        let path = result.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        
        return path
    }
    
    private func resizedIcon(_ image: NSImage, to size: CGFloat) -> NSImage {
        let newSize = NSSize(width: size, height: size)
        let newImage = NSImage(size: newSize)
        
        newImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: newSize),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1.0
        )
        newImage.unlockFocus()
        
        return newImage
    }
    
    /// Clear the icon cache
    func clearCache() {
        queue.async(flags: .barrier) {
            self.iconCache.removeAll()
        }
    }
}

struct AppIconView: View {
    let appName: String
    var size: CGFloat = 16
    
    private var iconProvider: AppIconProvider { .shared }
    @ObservedObject private var settingsManager = SettingsManager.shared
    private var useGrayscale: Bool {
        settingsManager.settings.global.grayscaleAppIcons
    }
    
    var body: some View {
        iconProvider.iconImage(forApp: appName, size: size)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .saturation(useGrayscale ? 0 : 1)
    }
}
