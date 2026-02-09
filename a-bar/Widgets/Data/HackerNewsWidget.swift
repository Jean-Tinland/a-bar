import SwiftUI

/// Hacker News widget showing frontpage stories
struct HackerNewsWidget: View {
    let position: BarPosition
    
    @EnvironmentObject var settings: SettingsManager
    
    @State private var stories: [HNStory] = []
    @State private var currentIndex: Int = 0
    @State private var isLoading = true
    @State private var showPopover = false
    @StateObject private var popoverManager = HNPopoverManager()
    
    private var hnSettings: HackerNewsWidgetSettings {
        settings.settings.widgets.hackerNews
    }
    
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
    
    var body: some View {
        BaseWidgetView(onRightClick: refreshStories) {
            if isLoading {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 16, height: 16)
            } else if !stories.isEmpty {
                HStack(spacing: 4) {
                    if hnSettings.showIcon {
                        Image(systemName: "newspaper.fill")
                            .font(.system(size: 11))
                            .foregroundColor(theme.foreground)
                    }
                    
                    Button(action: {
                        openStoryURL(stories[currentIndex])
                    }) {
                        Text((stories[currentIndex].title ?? "").truncated(to: hnSettings.maxTitleLength))
                            .foregroundColor(theme.foreground)
                            .font(settingsFont())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(stories[currentIndex].title ?? "")
                    
                    if hnSettings.showPoints {
                        Text("(\(stories[currentIndex].points))")
                            .font(settingsFont(scaledBy: 0.8))
                            .foregroundColor(theme.foreground.opacity(0.7))
                    }
                    
                    // Chevron button to show popover
                    Button(action: {
                        togglePopover()
                    }) {
                        Image(systemName: position == .top ? "chevron.down" : "chevron.up")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(theme.foreground.opacity(0.6))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            } else {
                HStack(spacing: 4) {
                    if hnSettings.showIcon {
                        Image(systemName: "newspaper.fill")
                            .font(.system(size: 11))
                            .foregroundColor(theme.minor)
                    }
                    Text("No stories")
                        .foregroundColor(theme.minor)
                }
            }
        }
        .background(
            AnchorView(
                onMake: { view in
                    popoverManager.attach(anchorView: view, position: position)
                    popoverManager.setContent {
                        PopoverContent(stories: stories, onOpenStory: openStoryURL, onOpenComments: openHNComments)
                            .environmentObject(settings)
                    }
                }
            )
        )
        .onAppear {
            if stories.isEmpty {
                refreshStories()
            }
        }
        .onReceive(Timer.publish(every: hnSettings.refreshInterval, on: .main, in: .common).autoconnect()) { _ in
            refreshStories()
        }
        .onReceive(Timer.publish(every: hnSettings.rotationInterval, on: .main, in: .common).autoconnect()) { _ in
            rotateStory()
        }
    }
    
    private func refreshStories() {
        Task {
            do {
                let fetchedStories = try await fetchHackerNewsStories()
                await MainActor.run {
                    stories = fetchedStories
                    currentIndex = 0
                    isLoading = false
                    
                    // Update popover content if showing
                    if showPopover {
                        popoverManager.setContent {
                            PopoverContent(stories: stories, onOpenStory: openStoryURL, onOpenComments: openHNComments)
                                .environmentObject(settings)
                        }
                    }
                }
            } catch {
                print("HN fetch error: \(error)")
                await MainActor.run {
                    isLoading = false
                }
            }
        }
    }
    
    private func rotateStory() {
        guard !stories.isEmpty else { return }
        currentIndex = (currentIndex + 1) % stories.count
    }
    
    private func togglePopover() {
        if showPopover {
            showPopover = false
            popoverManager.scheduleClose()
            OutsideClickMonitor.shared.stop()
        } else {
            NSApp.activate(ignoringOtherApps: true)
            showPopover = true
            popoverManager.showPanel()
            
            DispatchQueue.main.async {
                OutsideClickMonitor.shared.start {
                    if showPopover {
                        showPopover = false
                        popoverManager.scheduleClose()
                        OutsideClickMonitor.shared.stop()
                    }
                }
            }
        }
    }
    
    private func openStoryURL(_ story: HNStory) {
        guard let url = story.url else { return }
        NSWorkspace.shared.open(url)
        showPopover = false
        popoverManager.scheduleClose()
        OutsideClickMonitor.shared.stop()
    }

    private func openHNComments(_ story: HNStory) {
        let commentsURL = URL(string: "https://news.ycombinator.com/item?id=\(story.objectID)")!
        NSWorkspace.shared.open(commentsURL)
        showPopover = false
        popoverManager.scheduleClose()
        OutsideClickMonitor.shared.stop()
    }
    
    private func fetchHackerNewsStories() async throws -> [HNStory] {
        let url = URL(string: "https://hn.algolia.com/api/v1/search?tags=front_page")!
        let (data, _) = try await URLSession.shared.data(from: url)
        
        let response = try JSONDecoder().decode(HNResponse.self, from: data)
        return response.hits.filter { $0.title != nil && !$0.title!.isEmpty }
    }
    
    // Helper for outside click detection (same as SoundWidget)
    private class OutsideClickMonitor {
        static let shared = OutsideClickMonitor()
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
            let myWindows = NSApp.windows
            if myWindows.contains(where: { $0.windowNumber == windowNumber }) {
                return
            }
            self.handler?()
        }
    }
    
    // Popover content view
    private struct PopoverContent: View {
        @EnvironmentObject var settings: SettingsManager
        let stories: [HNStory]
        let onOpenStory: (HNStory) -> Void
        let onOpenComments: (HNStory) -> Void
        
        @State private var hoveredTitleIndex: Int? = nil
        @State private var hoveredMetadataIndex: Int? = nil
        
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
        
        var body: some View {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(stories.prefix(30).enumerated()), id: \.element.objectID) { index, story in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .top, spacing: 6) {
                                    Text("#\(index + 1)")
                                        .font(settingsFont(scaledBy: 0.9))
                                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                                        .frame(width: 20, alignment: .trailing)
                                        .padding(.top, 3)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        // Title - click to open story URL
                                        Button(action: {
                                            onOpenStory(story)
                                        }) {
                                            Text(story.title ?? "")
                                                .font(settingsFont(weight: .semibold))
                                                .foregroundColor(theme.foreground)
                                                .lineLimit(2)
                                                .multilineTextAlignment(.leading)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .padding(.vertical, 2)
                                                .padding(.horizontal, 4)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 4)
                                                      .fill(hoveredTitleIndex == index ? theme.foreground.opacity(0.1) : Color.clear)
                                                )
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                        .onHover { hovering in
                                            hoveredTitleIndex = hovering ? index : nil
                                            if hovering {
                                                NSCursor.pointingHand.push()
                                            } else {
                                                NSCursor.pop()
                                            }
                                        }
                                        
                                        // Metadata - click to open HN comments
                                        Button(action: {
                                            onOpenComments(story)
                                        }) {
                                            HStack(spacing: 8) {
                                                Text("\(story.points) points")
                                                    .font(settingsFont(scaledBy: 0.8))
                                                    .foregroundColor(theme.foreground)
                                                
                                                if let author = story.author {
                                                    Text("by \(author)")
                                                        .font(settingsFont(scaledBy: 0.8))
                                                        .foregroundColor(theme.foreground)
                                                }
                                                
                                                if story.numComments > 0 {
                                                    Text("\(story.numComments) comments")
                                                        .font(settingsFont(scaledBy: 0.8))
                                                        .foregroundColor(theme.foreground)
                                                }
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.vertical, 2)
                                            .padding(.horizontal, 4)
                                            .background(
                                                RoundedRectangle(cornerRadius: 4)
                                                  .fill(hoveredMetadataIndex == index ? theme.foreground.opacity(0.1) : Color.clear)
                                            )
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                        .onHover { hovering in
                                            hoveredMetadataIndex = hovering ? index : nil
                                            if hovering {
                                                NSCursor.pointingHand.push()
                                            } else {
                                                NSCursor.pop()
                                            }
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.all, 4)
                            
                            if index < stories.prefix(30).count - 1 {
                                Divider()
                                    .padding(.horizontal, 8)
                            }
                        }
                    }
                    .padding(.all, 8)
                }
                .frame(maxHeight: 500)
            }
            .frame(width: 400)
            .background(
                RoundedRectangle(cornerRadius: 8)
                  .fill(theme.background)
            )
            .padding(6)
        }
    }
    
    // Popover manager (similar to SoundWidget)
    private class HNPopoverManager: NSObject, ObservableObject {
        private weak var anchorView: NSView?
        private var panel: NSPanel?
        private var host: NSHostingController<AnyView>?
        private var contentProvider: (() -> AnyView)?
        private var closeWorkItem: DispatchWorkItem?
        private var barPosition: BarPosition = .top
        
        func attach(anchorView: NSView, position: BarPosition) {
            self.anchorView = anchorView
            self.barPosition = position
        }
        
        private func makePanelIfNeeded() {
            guard panel == nil else { return }
            let p = NSPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: true)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.level = .statusBar
            p.isMovableByWindowBackground = false
            p.collectionBehavior = [.canJoinAllSpaces, .transient]
            p.ignoresMouseEvents = false
            p.becomesKeyOnlyIfNeeded = true
            p.isReleasedWhenClosed = false
            panel = p
        }
        
        func showPanel() {
            guard let anchor = anchorView else { return }
            makePanelIfNeeded()
            guard let panel = panel else { return }
            
            DispatchQueue.main.async {
                if let provider = self.contentProvider {
                    let view = provider()
                    if self.host == nil {
                        let h = NSHostingController(rootView: view)
                        h.view.wantsLayer = true
                        h.view.layer?.masksToBounds = false
                        self.host = h
                        panel.contentView = h.view
                    } else if let host = self.host {
                        host.rootView = view
                    }
                }
                
                guard let hostView = self.host?.view else { return }
                
                let desiredSize = hostView.fittingSize
                let size = NSSize(width: max(400, desiredSize.width), height: min(520, desiredSize.height))
                
                guard let win = anchor.window else { return }
                let rectInWindow = anchor.convert(anchor.bounds, to: win.contentView)
                let screenRect = win.convertToScreen(rectInWindow)
                
                let x = screenRect.maxX - size.width
                // Position popover below widget for top bar, above for bottom bar
                let y = self.barPosition == .top 
                    ? screenRect.minY - size.height - 6 
                    : screenRect.maxY + 6
                let origin = NSPoint(x: x, y: y)
                
                panel.setFrame(NSRect(origin: origin, size: size), display: true)
                panel.orderFrontRegardless()
                
                self.cancelClose()
            }
        }
        
        func scheduleClose(after delay: TimeInterval = 0.6) {
            cancelClose()
            let item = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.panel?.orderOut(nil)
                }
            }
            closeWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        }
        
        private func cancelClose() {
            closeWorkItem?.cancel()
            closeWorkItem = nil
        }
        
        func setContent<Content: View>(_ provider: @escaping () -> Content) {
            contentProvider = {
                AnyView(provider())
            }
            if let panel = panel, let provider = contentProvider {
                let view = provider()
                let h = NSHostingController(rootView: view)
                h.view.wantsLayer = true
                host = h
                panel.contentView = h.view
            }
        }
    }
    
    /// Anchor view helper
    private struct AnchorView: NSViewRepresentable {
        var onMake: (NSView) -> Void
        
        func makeNSView(context: Context) -> NSView {
            let v = NSView()
            DispatchQueue.main.async {
                onMake(v)
            }
            return v
        }
        
        func updateNSView(_ nsView: NSView, context: Context) {}
    }
}

struct HNResponse: Codable {
    let hits: [HNStory]
}

struct HNStory: Codable {
    let objectID: String
    let title: String?
    let urlString: String?
    let points: Int
    let author: String?
    let numComments: Int
    let createdAt: String
    
    enum CodingKeys: String, CodingKey {
        case objectID
        case title
        case urlString = "url"
        case points
        case author
        case numComments = "num_comments"
        case createdAt = "created_at"
    }
    
    var url: URL? {
        guard let urlString = urlString else { return nil }
        return URL(string: urlString)
    }
}
