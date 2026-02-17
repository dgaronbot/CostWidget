import SwiftUI
import AppKit
import Foundation

struct CostData: Codable {
    let timestamp: String
    let anthropic: AnthropicCost
    let openrouter: OpenrouterCost
    let twilio: TwilioCost
    let replicate: ReplicateCost
    let grand_total: Double

    struct AnthropicCost: Codable {
        let total: Double
        let today: Double
        let requests: Int
        let input_tokens: Int
        let output_tokens: Int
        let cache_read_tokens: Int
        let by_model: [String: Double]
        let by_day: [String: Double]
    }

    struct OpenrouterCost: Codable {
        let total: Double
        let requests: Int
        let by_model: [String: Double]
    }

    struct TwilioCost: Codable {
        let total: Double
        let calls: Int
        let call_cost: Double
        let number_cost: Double
    }

    struct ReplicateCost: Codable {
        let total: Double
        let runs: Int
    }
}

class CostTracker: ObservableObject {
    @Published var data: CostData?
    @Published var isLoading = true
    @Published var lastUpdate: Date = Date()
    let scriptPath: String
    private var timer: Timer?
    private var activeProcess: Process?

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        scriptPath = "\(home)/.openclaw/workspace/CostWidget/cost-tracker.sh"
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        timer?.invalidate()
        activeProcess?.terminate()
    }

    func refresh() {
        isLoading = true
        activeProcess?.terminate()
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            let process = Process()
            self.activeProcess = process
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [self.scriptPath]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
                self.activeProcess = nil
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let costData = try? JSONDecoder().decode(CostData.self, from: data) {
                    DispatchQueue.main.async {
                        self.data = costData
                        self.lastUpdate = Date()
                        self.isLoading = false
                    }
                } else {
                    DispatchQueue.main.async { self.isLoading = false }
                }
            } catch {
                DispatchQueue.main.async { self.isLoading = false }
            }
        }
    }
}

struct Theme {
    static let primary = Color.primary.opacity(0.9)
    static let secondary = Color.primary.opacity(0.6)
    static let tertiary = Color.primary.opacity(0.4)
    static let quaternary = Color.primary.opacity(0.2)
    static let separator = Color.primary.opacity(0.15)
    static let accent = Color.accentColor
    static func barColor(index: Int, total: Int) -> Color {
        let progress = total > 1 ? Double(total - 1 - index) / Double(total - 1) : 0.5
        return Color(hue: 0.38, saturation: 0.55 + 0.2 * progress, brightness: 0.55 + 0.25 * progress)
    }
}

struct WidgetView: View {
    @ObservedObject var tracker: CostTracker
    @State private var isExpanded = false
    @AppStorage("textScale") private var textScale: Double = 1.0
    func s(_ size: CGFloat) -> CGFloat { size * CGFloat(textScale) }
    func performHaptic() {
        if #available(macOS 13.0, *) {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            compactPill.onTapGesture {
                performHaptic()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { isExpanded.toggle() }
            }
            if isExpanded, let data = tracker.data {
                Divider().overlay(Theme.separator)
                expandedContent(data: data).padding(.horizontal, s(12)).padding(.vertical, s(10))
            }
        }
        .padding(.vertical, s(4))
        .frame(minWidth: 200, maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: s(14)))
        .shadow(color: .black.opacity(0.3), radius: 16, x: 0, y: 8)
    }

    var compactPill: some View {
        HStack(spacing: s(8)) {
            Circle().fill(Theme.accent.opacity(0.8)).frame(width: s(7), height: s(7))
            if tracker.isLoading {
                Text("Loading...").font(.system(size: s(14), weight: .semibold, design: .rounded)).foregroundColor(Theme.tertiary)
            } else {
                Text("$\(tracker.data?.grand_total ?? 0, specifier: "%.2f")").font(.system(size: s(14), weight: .semibold, design: .rounded))
            }
            Rectangle().fill(Theme.quaternary).frame(width: 1, height: s(14))
            Text("today $\(tracker.data?.anthropic.today ?? 0, specifier: "%.2f")").font(.system(size: s(10), weight: .medium, design: .monospaced)).foregroundColor(Theme.secondary)
            Spacer(minLength: 0)
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down").font(.system(size: s(8), weight: .semibold)).foregroundColor(Theme.tertiary)
        }
        .padding(.horizontal, s(12)).padding(.vertical, s(8))
    }

    func expandedContent(data: CostData) -> some View {
        VStack(alignment: .leading, spacing: s(6)) {
            if data.openrouter.total > 0 {
                ServiceRow(symbol: "network", label: "OpenRouter", value: data.openrouter.total, detail: "\(data.openrouter.requests) reqs", color: Color(hue: 0.55, saturation: 0.6, brightness: 0.9), s: s)
                Divider().overlay(Theme.separator).padding(.vertical, s(2))
            }
            ServiceRow(symbol: "brain.head.profile", label: "Anthropic", value: data.anthropic.total, detail: "\(data.anthropic.requests) reqs", color: Color(hue: 0.08, saturation: 0.65, brightness: 0.95), s: s)
            Divider().overlay(Theme.separator).padding(.vertical, s(2))
            ServiceRow(symbol: "phone.fill", label: "Twilio", value: data.twilio.total, detail: "\(data.twilio.calls) calls", color: Color(hue: 0.6, saturation: 0.5, brightness: 0.9), s: s)
            Divider().overlay(Theme.separator).padding(.vertical, s(2))
            ServiceRow(symbol: "waveform", label: "Replicate", value: data.replicate.total, detail: "\(data.replicate.runs) runs", color: Color(hue: 0.8, saturation: 0.45, brightness: 0.85), s: s)
        }
    }

    func shortModelName(_ name: String) -> String {
        if name.contains("sonnet-4") || name.contains("sonnet4") { return "Sonnet 4" }
        if name.contains("opus") { return "Opus 4.6" }
        if name.contains("sonnet") { return "Sonnet 3.5" }
        if name.contains("kimi") { return "Kimi" }
        if name.contains("gemini") { return "Gemini" }
        return String(name.prefix(15))
    }
}

struct ServiceRow: View {
    let symbol: String, label: String, value: Double, detail: String, color: Color
    let s: (CGFloat) -> CGFloat
    var body: some View {
        HStack(spacing: s(6)) {
            Image(systemName: symbol).font(.system(size: s(10), weight: .medium)).foregroundColor(color).frame(width: s(16))
            Text(label).font(.system(size: s(11), weight: .medium))
            Spacer()
            Text(detail).font(.system(size: s(9))).foregroundColor(Theme.tertiary)
            Text("$\(value, specifier: "%.2f")").font(.system(size: s(11), weight: .semibold, design: .monospaced))
        }
    }
}

class DraggableWindow: NSWindow {
    enum ResizeCorner { case topLeading, topTrailing, bottomLeading, bottomTrailing }
    var activeCorner: ResizeCorner?
    var resizeStartFrame: NSRect?
    var resizeStartMouse: NSPoint?

    func cornerAt(_ loc: NSPoint) -> ResizeCorner? {
        let zone: CGFloat = 20, w = frame.width, h = frame.height
        if loc.x < zone && loc.y > h - zone { return .topLeading }
        if loc.x > w - zone && loc.y > h - zone { return .topTrailing }
        if loc.x < zone && loc.y < zone { return .bottomLeading }
        if loc.x > w - zone && loc.y < zone { return .bottomTrailing }
        return nil
    }

    override func mouseMoved(with event: NSEvent) {
        if cornerAt(event.locationInWindow) != nil { NSCursor.crosshair.set() }
        else { NSCursor.openHand.set() }
    }

    override func mouseDown(with event: NSEvent) {
        let loc = event.locationInWindow
        activeCorner = cornerAt(loc)
        if activeCorner != nil {
            resizeStartFrame = frame
            resizeStartMouse = convertPoint(toScreen: loc)
        } else {
            super.mouseDown(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if let corner = activeCorner, let sf = resizeStartFrame, let sm = resizeStartMouse {
            let cm = convertPoint(toScreen: event.locationInWindow)
            let dx = cm.x - sm.x, dy = cm.y - sm.y
            var newX = sf.origin.x, newY = sf.origin.y, newW = sf.width, newH = sf.height
            switch corner {
            case .bottomTrailing: newW = sf.width + dx; newH = sf.height - dy; newY = sf.origin.y + dy
            case .bottomLeading: newW = sf.width - dx; newX = sf.origin.x + dx; newH = sf.height - dy; newY = sf.origin.y + dy
            case .topTrailing: newW = sf.width + dx; newH = sf.height + dy
            case .topLeading: newW = sf.width - dx; newX = sf.origin.x + dx; newH = sf.height + dy
            }
            newW = max(200, newW); newH = max(40, newH)
            setFrame(NSRect(x: newX, y: newY, width: newW, height: newH), display: true)
        } else {
            super.mouseDragged(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        activeCorner = nil
        super.mouseUp(with: event)
        mouseMoved(with: event)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: DraggableWindow!
    var tracker = CostTracker()
    func applicationDidFinishLaunching(_ notification: Notification) {
        let contentView = WidgetView(tracker: tracker)
        window = DraggableWindow(contentRect: NSRect(x: 0, y: 0, width: 260, height: 40), styleMask: [.borderless], backing: .buffered, defer: false)
        let hostView = NSHostingView(rootView: contentView)
        hostView.autoresizingMask = [.width, .height]
        window.contentView = hostView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.hasShadow = false
        window.isMovableByWindowBackground = true
        window.acceptsMouseMovedEvents = true
        if let screen = NSScreen.main {
            let sf = screen.visibleFrame
            window.setFrameOrigin(NSPoint(x: sf.maxX - 270, y: sf.maxY - 50))
        }
        window.orderFront(nil)
        let trackingArea = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: window, userInfo: nil)
        window.contentView?.addTrackingArea(trackingArea)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
