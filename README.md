# CostWidget

A minimal floating macOS widget that tracks API costs (Anthropic, Twilio, Replicate) from OpenClaw session logs.

## Features
- Floating always-on-top pill showing total spend
- Expandable card with per-service breakdown, model costs, daily bar chart
- Resizable from any corner, draggable anywhere on screen
- Adjustable text size (50%-300%), persisted across launches
- Menu bar icon with cost summary
- Auto-refreshes every 60 seconds

## Build

```bash
swiftc -framework SwiftUI -framework AppKit CostWidget.swift -o CostWidget
./CostWidget
```

Requires macOS 13+ and the `cost-tracker.sh` script to parse session logs.
