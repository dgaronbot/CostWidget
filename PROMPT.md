# Build: OpenClaw Cost Tracker macOS Widget

Build a native macOS SwiftUI app that shows API costs as a floating overlay widget + menu bar icon.

## Data Source
`cost-tracker.sh` already exists and outputs JSON. Run it to see the schema. It refreshes Anthropic, Twilio, and Replicate costs from OpenClaw session logs.

## Requirements

### Menu Bar
- Show lobster emoji + total cost: `🦞 $157.52`
- Clicking opens a dropdown with the expanded breakdown
- "Refresh" and "Quit" menu items

### Floating Widget (top-right corner of screen)
- Small dark translucent pill showing: `🦞 $157.52 | today $42.99`
- Click to expand into a detailed card showing:
  - Anthropic total + breakdown by model (Opus 4.6, Sonnet 4)
  - Twilio total (calls + number)
  - Replicate total (TTS runs)
  - Daily cost chart (last 5 days as horizontal bar chart)
  - "Updated Xm ago" footer with refresh button
- Click again to collapse back to pill
- Draggable (hold and drag to reposition)
- Always on top, visible on all spaces/desktops
- Semi-transparent dark background with rounded corners

### Technical
- Single-file Swift app (CostWidget.swift), compiled with swiftc
- No Xcode project needed
- Refresh data every 60 seconds by re-running cost-tracker.sh
- App activation policy: .accessory (no dock icon)
- Window: borderless, floating level, canJoinAllSpaces
- Use NSHostingView for SwiftUI in NSWindow

### Design
- Dark theme (black @ 85% opacity background)
- White text, monospaced numbers
- Subtle border (white @ 10%)
- Smooth expand/collapse animation
- Compact - widget should be ~220px wide collapsed, ~240px expanded
- Daily bars should use a green gradient (darker = older)

### Build
Compile with: `swiftc -framework SwiftUI -framework AppKit CostWidget.swift -o CostWidget`
Test by running: `./CostWidget`
