import SwiftUI
import AppKit
import Foundation

// MARK: - Data Model

struct CostData: Codable {
    let timestamp: String
    let anthropic: AnthropicCost
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

// MARK: - Cost Tracker

class CostTracker: ObservableObject {
    @Published var data: CostData?
    @Published var lastUpdate: Date = Date()

    let scriptPath: String
    var timer: Timer?

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        scriptPath = "\(home)/.openclaw/workspace/CostWidget/cost-tracker.sh"
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [self.scriptPath]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let costData = try? JSONDecoder().decode(CostData.self, from: data) {
                    DispatchQueue.main.async {
                        self.data = costData
                        self.lastUpdate = Date()
                    }
                }
            } catch {
                print("Error: \(error)")
            }
        }
    }
}

// MARK: - Theme

struct Theme {
    // Apple-style semantic colors for dark vibrancy
    static let primary = Color.white.opacity(0.85)
    static let secondary = Color.white.opacity(0.55)
    static let tertiary = Color.white.opacity(0.35)
    static let quaternary = Color.white.opacity(0.18)
    static let separator = Color.white.opacity(0.12)
    static let accent = Color.accentColor

    // Bar chart gradient
    static func barColor(index: Int, total: Int) -> Color {
        let progress = total > 1 ? Double(total - 1 - index) / Double(total - 1) : 0.5
        return Color(
            hue: 0.38,  // green-teal
            saturation: 0.55 + 0.2 * progress,
            brightness: 0.55 + 0.25 * progress
        )
    }
}

// MARK: - Daily Bar Chart

struct DailyBarChart: View {
    let days: [(String, Double)]
    let s: (CGFloat) -> CGFloat

    var body: some View {
        let maxCost = days.map(\.1).max() ?? 1

        VStack(alignment: .leading, spacing: s(4)) {
            Text("Daily Spend")
                .font(.system(size: s(9), weight: .medium))
                .foregroundColor(Theme.tertiary)
                .textCase(.uppercase)
                .tracking(0.5)

            ForEach(Array(days.enumerated()), id: \.offset) { index, entry in
                let (day, cost) = entry
                let fraction = maxCost > 0 ? cost / maxCost : 0

                HStack(spacing: s(6)) {
                    Text(shortDate(day))
                        .font(.system(size: s(9), weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.secondary)
                        .frame(width: s(36), alignment: .leading)

                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: s(2.5))
                            .fill(Theme.barColor(index: index, total: days.count))
                            .frame(width: max(s(3), geo.size.width * fraction))
                    }
                    .frame(height: s(12))

                    Text("$\(cost, specifier: "%.2f")")
                        .font(.system(size: s(9), weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.secondary)
                        .frame(width: s(50), alignment: .trailing)
                }
            }
        }
    }

    func shortDate(_ iso: String) -> String {
        let parts = iso.split(separator: "-")
        guard parts.count == 3 else { return iso }
        return "\(parts[1])/\(parts[2])"
    }
}

// MARK: - Service Row

struct ServiceRow: View {
    let symbol: String  // SF Symbol name
    let label: String
    let value: Double
    let detail: String
    let color: Color
    let s: (CGFloat) -> CGFloat

    var body: some View {
        HStack(spacing: s(6)) {
            Image(systemName: symbol)
                .font(.system(size: s(10), weight: .medium))
                .foregroundColor(color)
                .frame(width: s(16))

            Text(label)
                .font(.system(size: s(11), weight: .medium))
                .foregroundColor(Theme.primary)

            Spacer()

            Text(detail)
                .font(.system(size: s(9)))
                .foregroundColor(Theme.tertiary)
                .padding(.trailing, s(4))

            Text("$\(value, specifier: "%.2f")")
                .font(.system(size: s(11), weight: .semibold, design: .monospaced))
                .foregroundColor(Theme.primary)
        }
    }
}

// MARK: - Sub-detail Row

struct SubRow: View {
    let label: String
    let value: String
    let s: (CGFloat) -> CGFloat

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: s(9), weight: .regular, design: .monospaced))
                .foregroundColor(Theme.tertiary)
                .padding(.leading, s(22))
            Spacer()
            Text(value)
                .font(.system(size: s(9), weight: .regular, design: .monospaced))
                .foregroundColor(Theme.tertiary)
        }
    }
}

// MARK: - Floating Widget View

struct WidgetView: View {
    @ObservedObject var tracker: CostTracker
    @State private var isExpanded = false
    @State private var isHoveringRefresh = false
    @AppStorage("textScale") private var textScale: Double = 1.0

    func s(_ size: CGFloat) -> CGFloat { size * CGFloat(textScale) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: Compact pill
            compactPill
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        isExpanded.toggle()
                    }
                }

            if isExpanded, let data = tracker.data {
                Divider().overlay(Theme.separator)

                expandedContent(data: data)
                    .padding(.horizontal, s(12))
                    .padding(.vertical, s(10))
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(minWidth: 200, maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: s(12)))
        .overlay(
            RoundedRectangle(cornerRadius: s(12))
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 6)
        .shadow(color: .black.opacity(0.08), radius: 2, x: 0, y: 1)
    }

    // MARK: - Compact Pill

    var compactPill: some View {
        HStack(spacing: s(8)) {
            // Subtle colored dot instead of emoji
            Circle()
                .fill(Color.green.opacity(0.8))
                .frame(width: s(7), height: s(7))

            Text("$\(tracker.data?.grand_total ?? 0, specifier: "%.2f")")
                .font(.system(size: s(14), weight: .semibold, design: .rounded))
                .foregroundColor(Theme.primary)

            Rectangle()
                .fill(Theme.quaternary)
                .frame(width: 1, height: s(14))

            Text("today $\(tracker.data?.anthropic.today ?? 0, specifier: "%.2f")")
                .font(.system(size: s(10), weight: .medium, design: .monospaced))
                .foregroundColor(Theme.secondary)

            Spacer(minLength: 0)

            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: s(8), weight: .semibold))
                .foregroundColor(Theme.tertiary)
        }
        .padding(.horizontal, s(12))
        .padding(.vertical, s(8))
    }

    // MARK: - Expanded Content

    func expandedContent(data: CostData) -> some View {
        VStack(alignment: .leading, spacing: s(6)) {
            // Services
            ServiceRow(
                symbol: "brain.head.profile",
                label: "Anthropic",
                value: data.anthropic.total,
                detail: "\(data.anthropic.requests) reqs",
                color: Color(hue: 0.08, saturation: 0.65, brightness: 0.95),
                s: s
            )

            // Model sub-rows
            ForEach(
                Array(data.anthropic.by_model.sorted(by: { $0.value > $1.value }).prefix(3)),
                id: \.key
            ) { model, cost in
                if cost > 0 {
                    SubRow(label: shortModelName(model), value: "$" + String(format: "%.2f", cost), s: s)
                }
            }

            Divider().overlay(Theme.separator).padding(.vertical, s(2))

            ServiceRow(
                symbol: "phone.fill",
                label: "Twilio",
                value: data.twilio.total,
                detail: "\(data.twilio.calls) calls",
                color: Color(hue: 0.6, saturation: 0.5, brightness: 0.9),
                s: s
            )
            SubRow(label: "calls", value: "$" + String(format: "%.2f", data.twilio.call_cost), s: s)
            SubRow(label: "number", value: "$" + String(format: "%.2f", data.twilio.number_cost), s: s)

            Divider().overlay(Theme.separator).padding(.vertical, s(2))

            ServiceRow(
                symbol: "waveform",
                label: "Replicate",
                value: data.replicate.total,
                detail: "\(data.replicate.runs) runs",
                color: Color(hue: 0.8, saturation: 0.45, brightness: 0.85),
                s: s
            )

            Divider().overlay(Theme.separator).padding(.vertical, s(2))

            // Daily bar chart
            let days = Array(data.anthropic.by_day.sorted(by: { $0.key > $1.key }).prefix(5).reversed())
            DailyBarChart(days: days, s: s)

            Divider().overlay(Theme.separator).padding(.vertical, s(2))

            // Footer
            HStack(spacing: s(8)) {
                Text("Updated \(timeAgo(tracker.lastUpdate))")
                    .font(.system(size: s(9)))
                    .foregroundColor(Theme.tertiary)

                Spacer()

                // Text scale controls
                Group {
                    Button(action: { withAnimation(.easeOut(duration: 0.15)) { textScale = max(0.5, textScale - 0.1) } }) {
                        Image(systemName: "textformat.size.smaller")
                            .font(.system(size: s(9), weight: .medium))
                            .foregroundColor(textScale <= 0.5 ? Theme.quaternary : Theme.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(textScale <= 0.5)

                    Text("\(Int(round(textScale * 100)))%")
                        .font(.system(size: s(8), weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.tertiary)
                        .frame(width: s(30))

                    Button(action: { withAnimation(.easeOut(duration: 0.15)) { textScale = min(3.0, textScale + 0.1) } }) {
                        Image(systemName: "textformat.size.larger")
                            .font(.system(size: s(9), weight: .medium))
                            .foregroundColor(textScale >= 3.0 ? Theme.quaternary : Theme.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(textScale >= 3.0)
                }

                Rectangle()
                    .fill(Theme.quaternary)
                    .frame(width: 1, height: s(12))

                Button(action: { tracker.refresh() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: s(9), weight: .medium))
                        .foregroundColor(isHoveringRefresh ? Theme.primary : Theme.secondary)
                }
                .buttonStyle(.plain)
                .onHover { isHoveringRefresh = $0 }
            }
        }
    }

    func shortModelName(_ name: String) -> String {
        if name.contains("opus") { return "Opus 4.6" }
        if name.contains("sonnet-4") || name.contains("sonnet4") { return "Sonnet 4" }
        if name.contains("sonnet") { return "Sonnet 3.5" }
        if name.contains("gemini") { return "Gemini" }
        return String(name.prefix(15))
    }

    func timeAgo(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        return "\(seconds / 3600)h ago"
    }
}

// MARK: - Draggable + Resizable Window

enum ResizeCorner {
    case topLeading, topTrailing, bottomLeading, bottomTrailing
}

class DraggableWindow: NSWindow {
    var initialLocation: NSPoint?
    var activeCorner: ResizeCorner? = nil
    var resizeStartFrame: NSRect?
    var resizeStartMouse: NSPoint?

    func cornerAt(_ loc: NSPoint) -> ResizeCorner? {
        let zone: CGFloat = 20
        let w = frame.width, h = frame.height
        if loc.x < zone && loc.y > h - zone { return .topLeading }
        if loc.x > w - zone && loc.y > h - zone { return .topTrailing }
        if loc.x < zone && loc.y < zone { return .bottomLeading }
        if loc.x > w - zone && loc.y < zone { return .bottomTrailing }
        return nil
    }

    override func mouseMoved(with event: NSEvent) {
        let loc = event.locationInWindow
        if let corner = cornerAt(loc) {
            switch corner {
            case .topLeading, .bottomTrailing:
                NSCursor(image: makeCursorImage(type: "nwse"), hotSpot: NSPoint(x: 8, y: 8)).set()
            case .topTrailing, .bottomLeading:
                NSCursor(image: makeCursorImage(type: "nesw"), hotSpot: NSPoint(x: 8, y: 8)).set()
            }
        } else {
            NSCursor.openHand.set()
        }
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.openHand.set()
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseDown(with event: NSEvent) {
        let loc = event.locationInWindow
        activeCorner = cornerAt(loc)
        if activeCorner != nil {
            resizeStartFrame = frame
            resizeStartMouse = convertPoint(toScreen: loc)
        } else {
            NSCursor.closedHand.set()
            initialLocation = loc
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if let corner = activeCorner, let sf = resizeStartFrame, let sm = resizeStartMouse {
            let cm = convertPoint(toScreen: event.locationInWindow)
            let dx = cm.x - sm.x
            let dy = cm.y - sm.y
            var newX = sf.origin.x, newY = sf.origin.y
            var newW = sf.width, newH = sf.height

            switch corner {
            case .bottomTrailing:
                newW = sf.width + dx; newH = sf.height - dy; newY = sf.origin.y + dy
            case .bottomLeading:
                newW = sf.width - dx; newX = sf.origin.x + dx; newH = sf.height - dy; newY = sf.origin.y + dy
            case .topTrailing:
                newW = sf.width + dx; newH = sf.height + dy
            case .topLeading:
                newW = sf.width - dx; newX = sf.origin.x + dx; newH = sf.height + dy
            }

            newW = max(200, newW); newH = max(40, newH)
            setFrame(NSRect(x: newX, y: newY, width: newW, height: newH), display: true)
        } else if let initial = initialLocation {
            let cur = event.locationInWindow
            let origin = frame.origin
            setFrameOrigin(NSPoint(x: origin.x + (cur.x - initial.x), y: origin.y + (cur.y - initial.y)))
        }
    }

    override func mouseUp(with event: NSEvent) {
        activeCorner = nil; initialLocation = nil
        mouseMoved(with: event)
    }

    // Generates a simple resize cursor image
    func makeCursorImage(type: String) -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let img = NSImage(size: size)
        img.lockFocus()
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(1.5)
        ctx.setLineCap(.round)
        if type == "nwse" {
            ctx.move(to: CGPoint(x: 3, y: 13)); ctx.addLine(to: CGPoint(x: 13, y: 3))
            // arrowheads
            ctx.move(to: CGPoint(x: 3, y: 13)); ctx.addLine(to: CGPoint(x: 7, y: 13))
            ctx.move(to: CGPoint(x: 3, y: 13)); ctx.addLine(to: CGPoint(x: 3, y: 9))
            ctx.move(to: CGPoint(x: 13, y: 3)); ctx.addLine(to: CGPoint(x: 9, y: 3))
            ctx.move(to: CGPoint(x: 13, y: 3)); ctx.addLine(to: CGPoint(x: 13, y: 7))
        } else {
            ctx.move(to: CGPoint(x: 13, y: 13)); ctx.addLine(to: CGPoint(x: 3, y: 3))
            ctx.move(to: CGPoint(x: 13, y: 13)); ctx.addLine(to: CGPoint(x: 9, y: 13))
            ctx.move(to: CGPoint(x: 13, y: 13)); ctx.addLine(to: CGPoint(x: 13, y: 9))
            ctx.move(to: CGPoint(x: 3, y: 3)); ctx.addLine(to: CGPoint(x: 7, y: 3))
            ctx.move(to: CGPoint(x: 3, y: 3)); ctx.addLine(to: CGPoint(x: 3, y: 7))
        }
        ctx.strokePath()
        img.unlockFocus()
        return img
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: DraggableWindow!
    var tracker = CostTracker()
    var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let contentView = WidgetView(tracker: tracker)

        window = DraggableWindow(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 40),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let hostView = NSHostingView(rootView: contentView)
        hostView.autoresizingMask = [.width, .height]
        window.contentView = hostView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.hasShadow = false
        window.isMovableByWindowBackground = false
        window.acceptsMouseMovedEvents = true

        // Position top-right
        if let screen = NSScreen.main {
            let sf = screen.visibleFrame
            window.setFrameOrigin(NSPoint(x: sf.maxX - 270, y: sf.maxY - 50))
        }

        window.orderFront(nil)

        // Mouse tracking
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: window,
            userInfo: nil
        )
        window.contentView?.addTrackingArea(trackingArea)

        // Menu bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateMenuBar()
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.updateMenuBar()
        }
    }

    func updateMenuBar() {
        if let data = tracker.data {
            statusItem?.button?.title = "$\(String(format: "%.2f", data.grand_total))"
        } else {
            statusItem?.button?.title = "..."
        }
        rebuildMenu()
    }

    func rebuildMenu() {
        let menu = NSMenu()

        if let data = tracker.data {
            let header = NSMenuItem(title: "Total: $\(String(format: "%.2f", data.grand_total))", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            menu.addItem(NSMenuItem.separator())

            let items: [(String, String, Double)] = [
                ("brain.head.profile", "Anthropic", data.anthropic.total),
                ("phone.fill", "Twilio", data.twilio.total),
                ("waveform", "Replicate", data.replicate.total)
            ]
            for (_, label, cost) in items {
                let item = NSMenuItem(title: "\(label): $\(String(format: "%.2f", cost))", action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }

            menu.addItem(NSMenuItem.separator())
            let today = NSMenuItem(title: "Today: $\(String(format: "%.2f", data.anthropic.today))", action: nil, keyEquivalent: "")
            today.isEnabled = false
            menu.addItem(today)
            menu.addItem(NSMenuItem.separator())
        }

        menu.addItem(NSMenuItem(title: "Refresh", action: #selector(refreshData), keyEquivalent: "r"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc func refreshData() { tracker.refresh() }
}

// MARK: - Main

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
