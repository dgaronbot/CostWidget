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

// MARK: - Daily Bar Chart

struct DailyBarChart: View {
    let days: [(String, Double)]
    var scale: CGFloat = 1.0

    var body: some View {
        let maxCost = days.map(\.1).max() ?? 1

        VStack(alignment: .leading, spacing: 3) {
            Text("DAILY")
                .font(.system(size: s(8), weight: .semibold))
                .foregroundColor(.white.opacity(0.3))
                .tracking(1)

            ForEach(Array(days.enumerated()), id: \.offset) { index, entry in
                let (day, cost) = entry
                let fraction = maxCost > 0 ? cost / maxCost : 0
                let greenColor = Color(
                    red: 0.1,
                    green: 0.45 + 0.35 * Double(days.count - 1 - index) / max(Double(days.count - 1), 1),
                    blue: 0.2
                )

                HStack(spacing: 6) {
                    Text(shortDate(day))
                        .font(.system(size: s(9), design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(width: s(36), alignment: .leading)

                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(greenColor)
                            .frame(width: max(2, geo.size.width * fraction))
                    }
                    .frame(height: s(10))

                    Text("$\(cost, specifier: "%.2f")")
                        .font(.system(size: s(9), design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(width: s(50), alignment: .trailing)
                }
            }
        }
    }

    func s(_ size: CGFloat) -> CGFloat { size * scale }

    func shortDate(_ iso: String) -> String {
        let parts = iso.split(separator: "-")
        guard parts.count == 3 else { return iso }
        return "\(parts[1])/\(parts[2])"
    }
}

// MARK: - Floating Widget View

struct WidgetView: View {
    @ObservedObject var tracker: CostTracker
    @State private var isExpanded = false
    @AppStorage("textScale") private var textScale: Double = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Compact pill - always visible
            HStack(spacing: 6) {
                Text("\u{1F99E}")
                    .font(.system(size: s(11)))
                Text("$\(tracker.data?.grand_total ?? 0, specifier: "%.2f")")
                    .font(.system(size: s(13), weight: .bold, design: .monospaced))
                    .foregroundColor(.white)

                Text("|")
                    .font(.system(size: s(11)))
                    .foregroundColor(.white.opacity(0.3))

                Text("today $\(tracker.data?.anthropic.today ?? 0, specifier: "%.2f")")
                    .font(.system(size: s(10), design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }

            if isExpanded, let data = tracker.data {
                Divider().background(Color.white.opacity(0.2))

                VStack(alignment: .leading, spacing: 4) {
                    // Anthropic breakdown
                    CostRow(icon: "\u{1F9E0}", label: "Anthropic", value: data.anthropic.total, detail: "\(data.anthropic.requests) reqs", scale: CGFloat(textScale))

                    // Model breakdown
                    ForEach(Array(data.anthropic.by_model.sorted(by: { $0.value > $1.value }).prefix(3)), id: \.key) { model, cost in
                        if cost > 0 {
                            HStack {
                                Text("  ")
                                Text(shortModelName(model))
                                    .font(.system(size: s(9), design: .monospaced))
                                    .foregroundColor(.white.opacity(0.5))
                                Spacer()
                                Text("$\(cost, specifier: "%.2f")")
                                    .font(.system(size: s(9), design: .monospaced))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                        }
                    }

                    // Twilio with calls + number breakdown
                    CostRow(icon: "\u{1F4DE}", label: "Twilio", value: data.twilio.total, detail: "\(data.twilio.calls) calls", scale: CGFloat(textScale))
                    HStack {
                        Text("  ")
                        Text("calls")
                            .font(.system(size: s(9), design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                        Spacer()
                        Text("$\(data.twilio.call_cost, specifier: "%.2f")")
                            .font(.system(size: s(9), design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    HStack {
                        Text("  ")
                        Text("number")
                            .font(.system(size: s(9), design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                        Spacer()
                        Text("$\(data.twilio.number_cost, specifier: "%.2f")")
                            .font(.system(size: s(9), design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                    }

                    // Replicate
                    CostRow(icon: "\u{1F3A4}", label: "Replicate", value: data.replicate.total, detail: "\(data.replicate.runs) runs", scale: CGFloat(textScale))

                    Divider().background(Color.white.opacity(0.2))

                    // Daily bar chart (last 5 days)
                    let days = Array(data.anthropic.by_day.sorted(by: { $0.key > $1.key }).prefix(5).reversed())
                    DailyBarChart(days: days, scale: CGFloat(textScale))

                    Divider().background(Color.white.opacity(0.2))

                    // Footer
                    HStack {
                        Text("Updated \(timeAgo(tracker.lastUpdate))")
                            .font(.system(size: s(8)))
                            .foregroundColor(.white.opacity(0.3))
                        Spacer()
                        Button(action: { tracker.refresh() }) {
                            Text("\u{21BB}")
                                .font(.system(size: s(10)))
                                .foregroundColor(.white.opacity(0.4))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 2)

                    // Text size selector
                    Divider().background(Color.white.opacity(0.2))
                    HStack {
                        Text("Text size")
                            .font(.system(size: s(8)))
                            .foregroundColor(.white.opacity(0.3))
                        Spacer()
                        Button(action: { textScale = max(0.5, textScale - 0.1) }) {
                            Text("\u{2212}")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(textScale <= 0.5 ? .white.opacity(0.15) : .white.opacity(0.5))
                                .frame(width: 20, height: 18)
                                .background(Color.white.opacity(0.08))
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .disabled(textScale <= 0.5)

                        Text("\(Int(round(textScale * 100)))%")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                            .frame(width: 32)

                        Button(action: { textScale = min(3.0, textScale + 0.1) }) {
                            Text("+")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(textScale >= 3.0 ? .white.opacity(0.15) : .white.opacity(0.5))
                                .frame(width: 20, height: 18)
                                .background(Color.white.opacity(0.08))
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .disabled(textScale >= 3.0)
                    }
                    .padding(.top, 2)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
        }
        .frame(minWidth: 180, maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.85))
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
        )
        .overlay(alignment: .topLeading) {
            if isExpanded { ResizeHandle(corner: .topLeading).padding(4) }
        }
        .overlay(alignment: .topTrailing) {
            if isExpanded { ResizeHandle(corner: .topTrailing).padding(4) }
        }
        .overlay(alignment: .bottomLeading) {
            if isExpanded { ResizeHandle(corner: .bottomLeading).padding(4) }
        }
        .overlay(alignment: .bottomTrailing) {
            if isExpanded { ResizeHandle(corner: .bottomTrailing).padding(4) }
        }
    }

    func s(_ size: CGFloat) -> CGFloat { size * CGFloat(textScale) }

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

struct CostRow: View {
    let icon: String
    let label: String
    let value: Double
    let detail: String
    var scale: CGFloat = 1.0

    var body: some View {
        HStack {
            Text(icon).font(.system(size: s(10)))
            Text(label)
                .font(.system(size: s(10), weight: .medium))
                .foregroundColor(.white.opacity(0.8))
            Spacer()
            Text(detail)
                .font(.system(size: s(9)))
                .foregroundColor(.white.opacity(0.4))
            Text("$\(value, specifier: "%.2f")")
                .font(.system(size: s(10), weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
        }
    }

    func s(_ size: CGFloat) -> CGFloat { size * scale }
}

// MARK: - Resize Handle

enum ResizeCorner {
    case topLeading, topTrailing, bottomLeading, bottomTrailing
}

struct ResizeHandle: View {
    let corner: ResizeCorner

    var body: some View {
        ZStack {
            Path { path in
                for i in 0..<3 {
                    let offset = CGFloat(i) * 4
                    path.move(to: CGPoint(x: 12 - offset, y: 12))
                    path.addLine(to: CGPoint(x: 12, y: 12 - offset))
                }
            }
            .stroke(Color.white.opacity(0.25), lineWidth: 1)
            .rotationEffect(rotationForCorner)
        }
        .frame(width: 12, height: 12)
    }

    var rotationForCorner: Angle {
        switch corner {
        case .bottomTrailing: return .zero
        case .bottomLeading: return .degrees(90)
        case .topLeading: return .degrees(180)
        case .topTrailing: return .degrees(270)
        }
    }
}

// MARK: - Draggable Window

class DraggableWindow: NSWindow {
    var initialLocation: NSPoint?
    var activeCorner: ResizeCorner? = nil
    var resizeStartFrame: NSRect?
    var resizeStartMouse: NSPoint?

    func cornerAt(_ loc: NSPoint) -> ResizeCorner? {
        let zone: CGFloat = 18
        let w = frame.width, h = frame.height
        if loc.x < zone && loc.y > h - zone { return .topLeading }
        if loc.x > w - zone && loc.y > h - zone { return .topTrailing }
        if loc.x < zone && loc.y < zone { return .bottomLeading }
        if loc.x > w - zone && loc.y < zone { return .bottomTrailing }
        return nil
    }

    func cursorForCorner(_ corner: ResizeCorner) -> NSCursor {
        switch corner {
        case .topLeading, .bottomTrailing: return NSCursor(image: NSCursor.arrow.image, hotSpot: .zero)
        case .topTrailing, .bottomLeading: return NSCursor(image: NSCursor.arrow.image, hotSpot: .zero)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let loc = event.locationInWindow
        if cornerAt(loc) != nil {
            NSCursor.crosshair.set()
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
            NSCursor.crosshair.set()
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
            var newX = sf.origin.x
            var newY = sf.origin.y
            var newW = sf.width
            var newH = sf.height

            switch corner {
            case .bottomTrailing:
                newW = sf.width + dx
                newH = sf.height - dy
                newY = sf.origin.y + dy
            case .bottomLeading:
                newW = sf.width - dx
                newX = sf.origin.x + dx
                newH = sf.height - dy
                newY = sf.origin.y + dy
            case .topTrailing:
                newW = sf.width + dx
                newH = sf.height + dy
            case .topLeading:
                newW = sf.width - dx
                newX = sf.origin.x + dx
                newH = sf.height + dy
            }

            newW = max(180, newW)
            newH = max(40, newH)
            setFrame(NSRect(x: newX, y: newY, width: newW, height: newH), display: true)
        } else if let initial = initialLocation {
            let screenLoc = event.locationInWindow
            let origin = frame.origin
            setFrameOrigin(NSPoint(
                x: origin.x + (screenLoc.x - initial.x),
                y: origin.y + (screenLoc.y - initial.y)
            ))
        }
    }

    override func mouseUp(with event: NSEvent) {
        activeCorner = nil
        initialLocation = nil
        let loc = event.locationInWindow
        if cornerAt(loc) != nil {
            NSCursor.crosshair.set()
        } else {
            NSCursor.openHand.set()
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: DraggableWindow!
    var tracker = CostTracker()
    var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create floating draggable window
        let contentView = WidgetView(tracker: tracker)

        window = DraggableWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 40),
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
        window.isMovableByWindowBackground = false  // we handle drag ourselves

        // Position in top-right corner
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.maxX - 250
            let y = screenFrame.maxY - 50
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        window.acceptsMouseMovedEvents = true
        window.orderFront(nil)

        // Track mouse for cursor changes
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: window,
            userInfo: nil
        )
        window.contentView?.addTrackingArea(trackingArea)

        // Menu bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateMenuBarTitle()

        // Periodic UI sync
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.updateMenuBarTitle()
            self?.resizeWindow()
        }

        // Setup menu with breakdown
        rebuildMenu()
    }

    func updateMenuBarTitle() {
        if let data = tracker.data {
            statusItem?.button?.title = "\u{1F99E} $\(String(format: "%.2f", data.grand_total))"
        } else {
            statusItem?.button?.title = "\u{1F99E} ..."
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

            let anthropic = NSMenuItem(title: "\u{1F9E0} Anthropic: $\(String(format: "%.2f", data.anthropic.total))", action: nil, keyEquivalent: "")
            anthropic.isEnabled = false
            menu.addItem(anthropic)

            for (model, cost) in data.anthropic.by_model.sorted(by: { $0.value > $1.value }).prefix(3) where cost > 0 {
                let item = NSMenuItem(title: "    \(shortModelName(model)): $\(String(format: "%.2f", cost))", action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }

            let twilio = NSMenuItem(title: "\u{1F4DE} Twilio: $\(String(format: "%.2f", data.twilio.total)) (\(data.twilio.calls) calls)", action: nil, keyEquivalent: "")
            twilio.isEnabled = false
            menu.addItem(twilio)

            let replicate = NSMenuItem(title: "\u{1F3A4} Replicate: $\(String(format: "%.2f", data.replicate.total)) (\(data.replicate.runs) runs)", action: nil, keyEquivalent: "")
            replicate.isEnabled = false
            menu.addItem(replicate)

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

    func shortModelName(_ name: String) -> String {
        if name.contains("opus") { return "Opus 4.6" }
        if name.contains("sonnet-4") || name.contains("sonnet4") { return "Sonnet 4" }
        if name.contains("sonnet") { return "Sonnet 3.5" }
        if name.contains("gemini") { return "Gemini" }
        return String(name.prefix(20))
    }

    func resizeWindow() {
        if let contentView = window.contentView {
            let size = contentView.fittingSize
            var frame = window.frame
            let oldHeight = frame.height
            frame.size.height = size.height
            frame.size.width = size.width
            frame.origin.y -= (size.height - oldHeight)
            window.setFrame(frame, display: true, animate: true)
        }
    }

    @objc func refreshData() {
        tracker.refresh()
    }
}

// MARK: - Main

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
