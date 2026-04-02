#!/usr/bin/env swift
// Generate Apple Watch screenshots for App Store
// Watch Series 4+ resolution: 368x448

import AppKit

let outputDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("build/watch-screenshots")
try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

func savePNG(_ rep: NSBitmapImageRep, to name: String) {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        print("Failed to encode \(name)")
        return
    }
    let url = outputDir.appendingPathComponent(name)
    try! data.write(to: url)
    print("Created: \(url.path) (\(Int(rep.pixelsWide))x\(Int(rep.pixelsHigh)))")
}

// Watch Series 4: 368x448
let W: CGFloat = 368
let H: CGFloat = 448

// Colors
let bg = NSColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1)
let accent = NSColor(red: 0.36, green: 0.51, blue: 1.0, alpha: 1)
let green = NSColor(red: 0.3, green: 0.8, blue: 0.4, alpha: 1)
let orange = NSColor(red: 0.95, green: 0.6, blue: 0.1, alpha: 1)
let purple = NSColor(red: 0.58, green: 0.39, blue: 0.98, alpha: 1)
let cardBg = NSColor(red: 0.12, green: 0.12, blue: 0.16, alpha: 1)

func drawText(_ text: String, at point: NSPoint, size: CGFloat, color: NSColor = .white, bold: Bool = false) {
    let font = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    (text as NSString).draw(at: point, withAttributes: attrs)
}

func drawRoundedRect(_ rect: NSRect, radius: CGFloat, fill: NSColor) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    fill.setFill()
    path.fill()
}

func drawCircle(center: NSPoint, radius: CGFloat, fill: NSColor) {
    let rect = NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    let path = NSBezierPath(ovalIn: rect)
    fill.setFill()
    path.fill()
}

func drawArc(center: NSPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, lineWidth: CGFloat, color: NSColor) {
    let path = NSBezierPath()
    path.appendArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
    color.setStroke()
    path.lineWidth = lineWidth
    path.lineCapStyle = .round
    path.stroke()
}

// MARK: - Dashboard Screenshot
func drawDashboard() -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H),
                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                isPlanar: false, colorSpaceName: .deviceRGB,
                                bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Background
    bg.setFill()
    NSRect(x: 0, y: 0, width: W, height: H).fill()

    // Title
    drawText("CLI Pulse", at: NSPoint(x: 16, y: H - 38), size: 16, color: accent, bold: true)

    // Online indicator
    drawCircle(center: NSPoint(x: W - 30, y: H - 30), radius: 4, fill: green)
    drawText("Online", at: NSPoint(x: W - 80, y: H - 35), size: 10, color: .gray)

    // Usage gauge (compact)
    let gaugeCenter = NSPoint(x: W / 2, y: H - 95)
    let gaugeR: CGFloat = 38
    // Background arc
    drawArc(center: gaugeCenter, radius: gaugeR, startAngle: 210, endAngle: -30, lineWidth: 8, color: NSColor(white: 0.2, alpha: 1))
    // Usage arc (67%)
    drawArc(center: gaugeCenter, radius: gaugeR, startAngle: 210, endAngle: 210 - 240 * 0.67, lineWidth: 8, color: accent)
    drawText("67%", at: NSPoint(x: gaugeCenter.x - 18, y: gaugeCenter.y - 9), size: 18, bold: true)
    drawText("Usage Today", at: NSPoint(x: gaugeCenter.x - 34, y: gaugeCenter.y - 24), size: 9, color: .gray)

    // Metric cards
    var y: CGFloat = H - 180
    let cardH: CGFloat = 44
    let cardW: CGFloat = (W - 48) / 2

    // Cost card
    drawRoundedRect(NSRect(x: 16, y: y, width: cardW, height: cardH), radius: 8, fill: cardBg)
    drawText("$2.45", at: NSPoint(x: 24, y: y + 18), size: 16, color: green, bold: true)
    drawText("Cost Today", at: NSPoint(x: 24, y: y + 4), size: 9, color: .gray)

    // Sessions card
    drawRoundedRect(NSRect(x: 24 + cardW, y: y, width: cardW, height: cardH), radius: 8, fill: cardBg)
    drawText("3", at: NSPoint(x: 32 + cardW, y: y + 18), size: 16, color: NSColor.cyan, bold: true)
    drawText("Sessions", at: NSPoint(x: 32 + cardW, y: y + 4), size: 9, color: .gray)

    y -= 52

    // Alerts card
    drawRoundedRect(NSRect(x: 16, y: y, width: cardW, height: cardH), radius: 8, fill: cardBg)
    drawText("2", at: NSPoint(x: 24, y: y + 18), size: 16, color: orange, bold: true)
    drawText("Alerts", at: NSPoint(x: 24, y: y + 4), size: 9, color: .gray)

    // Devices card
    drawRoundedRect(NSRect(x: 24 + cardW, y: y, width: cardW, height: cardH), radius: 8, fill: cardBg)
    drawText("1", at: NSPoint(x: 32 + cardW, y: y + 18), size: 16, color: .blue, bold: true)
    drawText("Devices", at: NSPoint(x: 32 + cardW, y: y + 4), size: 9, color: .gray)

    y -= 60

    // Provider bars
    drawText("Providers", at: NSPoint(x: 16, y: y + 8), size: 12, color: .white, bold: true)
    y -= 20

    let providers = [("Claude", 0.72, orange), ("Codex", 0.45, accent), ("Gemini", 0.30, purple)]
    for (name, pct, color) in providers {
        drawText(name, at: NSPoint(x: 16, y: y), size: 10, color: .lightGray)
        drawText("\(Int(pct * 100))%", at: NSPoint(x: W - 48, y: y), size: 10, color: color)
        // Bar background
        drawRoundedRect(NSRect(x: 16, y: y - 6, width: W - 32, height: 4), radius: 2, fill: NSColor(white: 0.15, alpha: 1))
        // Bar fill
        drawRoundedRect(NSRect(x: 16, y: y - 6, width: (W - 32) * CGFloat(pct), height: 4), radius: 2, fill: color)
        y -= 32
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// MARK: - Providers Screenshot
func drawProviders() -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H),
                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                isPlanar: false, colorSpaceName: .deviceRGB,
                                bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    bg.setFill()
    NSRect(x: 0, y: 0, width: W, height: H).fill()

    drawText("Providers", at: NSPoint(x: 16, y: H - 38), size: 16, color: accent, bold: true)
    drawText("6 active", at: NSPoint(x: W - 70, y: H - 35), size: 10, color: .gray)

    let providers: [(String, Double, NSColor, String)] = [
        ("Claude", 0.72, orange, "$1.85"),
        ("Codex", 0.45, accent, "$0.42"),
        ("Gemini", 0.30, purple, "$0.18"),
        ("Cursor", 0.55, green, "$0.65"),
        ("Copilot", 0.20, NSColor(red: 0.25, green: 0.6, blue: 0.95, alpha: 1), "$0.12"),
    ]

    var y = H - 70
    let cardH: CGFloat = 66
    for (name, pct, color, cost) in providers {
        drawRoundedRect(NSRect(x: 12, y: y - cardH, width: W - 24, height: cardH), radius: 10, fill: cardBg)

        // Provider name and status
        drawCircle(center: NSPoint(x: 26, y: y - 14), radius: 4, fill: color)
        drawText(name, at: NSPoint(x: 36, y: y - 20), size: 13, bold: true)
        drawCircle(center: NSPoint(x: W - 24, y: y - 14), radius: 3, fill: green)

        // Usage bar
        drawRoundedRect(NSRect(x: 20, y: y - 38, width: W - 40, height: 5), radius: 2.5, fill: NSColor(white: 0.2, alpha: 1))
        drawRoundedRect(NSRect(x: 20, y: y - 38, width: (W - 40) * CGFloat(pct), height: 5), radius: 2.5, fill: color)

        // Stats
        drawText("\(Int(pct * 100))% used", at: NSPoint(x: 20, y: y - 58), size: 9, color: .gray)
        drawText(cost, at: NSPoint(x: W - 60, y: y - 58), size: 10, color: green)

        y -= cardH + 8
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// MARK: - Alerts Screenshot
func drawAlerts() -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H),
                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                isPlanar: false, colorSpaceName: .deviceRGB,
                                bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    bg.setFill()
    NSRect(x: 0, y: 0, width: W, height: H).fill()

    drawText("Alerts", at: NSPoint(x: 16, y: H - 38), size: 16, color: accent, bold: true)

    // Alert badges
    drawRoundedRect(NSRect(x: W - 90, y: H - 40, width: 32, height: 18), radius: 9, fill: .red)
    drawText("1", at: NSPoint(x: W - 79, y: H - 38), size: 11, color: .white, bold: true)
    drawRoundedRect(NSRect(x: W - 54, y: H - 40, width: 32, height: 18), radius: 9, fill: orange)
    drawText("2", at: NSPoint(x: W - 43, y: H - 38), size: 11, color: .white, bold: true)

    let alerts: [(String, String, NSColor, String)] = [
        ("Claude quota low", "Usage at 90% of daily limit", .red, "5m ago"),
        ("Usage spike detected", "Codex usage 3x normal rate", orange, "15m ago"),
        ("Session too long", "claude-dev running 4h+", orange, "1h ago"),
    ]

    var y = H - 70
    let cardH: CGFloat = 80
    for (title, msg, color, time) in alerts {
        drawRoundedRect(NSRect(x: 12, y: y - cardH, width: W - 24, height: cardH), radius: 10, fill: cardBg)

        // Severity dot
        drawCircle(center: NSPoint(x: 24, y: y - 14), radius: 5, fill: color)

        // Title
        drawText(title, at: NSPoint(x: 36, y: y - 20), size: 12, bold: true)
        drawText(time, at: NSPoint(x: W - 60, y: y - 18), size: 9, color: .gray)

        // Message
        drawText(msg, at: NSPoint(x: 20, y: y - 40), size: 10, color: .gray)

        // Action buttons
        drawRoundedRect(NSRect(x: 20, y: y - cardH + 8, width: 50, height: 20), radius: 10, fill: green.withAlphaComponent(0.15))
        drawText("Resolve", at: NSPoint(x: 24, y: y - cardH + 11), size: 9, color: green)

        drawRoundedRect(NSRect(x: 78, y: y - cardH + 8, width: 40, height: 20), radius: 10, fill: orange.withAlphaComponent(0.15))
        drawText("Snooze", at: NSPoint(x: 81, y: y - cardH + 11), size: 9, color: orange)

        y -= cardH + 10
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

print("Generating Watch screenshots...")
savePNG(drawDashboard(), to: "dashboard_watch.png")
savePNG(drawProviders(), to: "providers_watch.png")
savePNG(drawAlerts(), to: "alerts_watch.png")
print("Done!")
