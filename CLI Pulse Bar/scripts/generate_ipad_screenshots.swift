#!/usr/bin/env swift
// Generates CLI Pulse iPad Pro 12.9" App Store screenshots (2048x2732)

import Cocoa

let pw: CGFloat = 2048
let ph: CGFloat = 2732

// Logical coordinate space (scaled up to fill pixels)
let logW: CGFloat = 1024
let logH: CGFloat = 1366

func makeBitmap() -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(pw), pixelsHigh: Int(ph),
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pw, height: ph)
    return rep
}

func beginDraw(_ rep: NSBitmapImageRep) {
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let sf = pw / logW
    NSGraphicsContext.current!.cgContext.scaleBy(x: sf, y: sf)
}

func endDraw() {
    NSGraphicsContext.restoreGraphicsState()
}

func drawBG() {
    let rect = NSRect(x: 0, y: 0, width: logW, height: logH)
    let bg = NSGradient(colors: [
        NSColor(calibratedRed: 0.06, green: 0.04, blue: 0.14, alpha: 1.0),
        NSColor(calibratedRed: 0.10, green: 0.07, blue: 0.22, alpha: 1.0),
    ])!
    bg.draw(in: rect, angle: -90)
}

func drawText(_ text: String, at point: NSPoint, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    (text as NSString).draw(at: point, withAttributes: attrs)
}

func drawCircle(at center: NSPoint, radius: CGFloat, color: NSColor) {
    let path = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    color.setFill()
    path.fill()
}

let dimColor = NSColor(calibratedWhite: 0.45, alpha: 1.0)
let cardBG = NSColor(calibratedRed: 0.12, green: 0.10, blue: 0.22, alpha: 1.0)
let orange = NSColor(calibratedRed: 0.90, green: 0.55, blue: 0.20, alpha: 1.0)
let blue = NSColor(calibratedRed: 0.36, green: 0.51, blue: 1.0, alpha: 1.0)
let purple = NSColor(calibratedRed: 0.58, green: 0.39, blue: 0.98, alpha: 1.0)
let green = NSColor(calibratedRed: 0.2, green: 0.8, blue: 0.4, alpha: 1.0)
let teal = NSColor(calibratedRed: 0.30, green: 0.80, blue: 0.65, alpha: 1.0)
let cyan = NSColor(calibratedRed: 0.2, green: 0.7, blue: 0.8, alpha: 1.0)

func drawRoundedRect(_ rect: NSRect, radius: CGFloat, fill: NSColor, stroke: NSColor? = nil) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    fill.setFill()
    path.fill()
    if let s = stroke {
        s.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

// ===== DASHBOARD =====
func drawDashboard() -> NSBitmapImageRep {
    let rep = makeBitmap()
    beginDraw(rep)
    drawBG()

    let mx: CGFloat = 40
    let contentW = logW - mx * 2
    var y = logH - 60

    // Title
    drawText("Your AI Dashboard", at: NSPoint(x: 0, y: y - 36), size: 36, weight: .bold, color: .white)
    let titleW = ("Your AI Dashboard" as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 36, weight: .bold)]).width
    drawText("Your AI Dashboard", at: NSPoint(x: (logW - titleW) / 2, y: y - 36), size: 36, weight: .bold, color: .white)
    // Overwrite - let me just center it properly
    drawBG() // redraw bg to clear

    y = logH - 60
    let title = "Your AI Dashboard"
    let titleFont = NSFont.systemFont(ofSize: 36, weight: .bold)
    let titleSize = (title as NSString).size(withAttributes: [.font: titleFont])
    drawText(title, at: NSPoint(x: (logW - titleSize.width) / 2, y: y - 36), size: 36, weight: .bold, color: .white)

    let sub = "Track usage across all providers"
    let subFont = NSFont.systemFont(ofSize: 20, weight: .medium)
    let subSize = (sub as NSString).size(withAttributes: [.font: subFont])
    drawText(sub, at: NSPoint(x: (logW - subSize.width) / 2, y: y - 68), size: 20, weight: .medium, color: dimColor)

    y -= 100

    // Status bar
    drawCircle(at: NSPoint(x: mx + 8, y: y - 6), radius: 5, color: green)
    drawText("Server Online", at: NSPoint(x: mx + 20, y: y - 14), size: 14, weight: .regular, color: dimColor)
    drawText("Last sync: 2s ago", at: NSPoint(x: logW - mx - 140, y: y - 14), size: 13, weight: .regular, color: dimColor)
    y -= 40

    // 3x2 metric cards
    let cardW = (contentW - 20) / 3
    let cardH: CGFloat = 100
    let metrics = [
        ("Usage Today", "12.4K", blue),
        ("Est. Cost", "$4.82", green),
        ("Requests", "847", purple),
        ("Sessions", "5", cyan),
        ("Devices", "3", blue),
        ("Alerts", "2", orange),
    ]

    for (i, m) in metrics.enumerated() {
        let col = i % 3
        let row = i / 3
        let cx = mx + CGFloat(col) * (cardW + 10)
        let cy = y - CGFloat(row) * (cardH + 10) - cardH

        drawRoundedRect(NSRect(x: cx, y: cy, width: cardW, height: cardH), radius: 10, fill: cardBG)

        // Accent line at top
        let accentRect = NSRect(x: cx + 12, y: cy + cardH - 14, width: 30, height: 3)
        drawRoundedRect(accentRect, radius: 1.5, fill: m.2)

        drawText(m.0, at: NSPoint(x: cx + 12, y: cy + cardH - 34), size: 12, weight: .medium, color: dimColor)
        drawText(m.1, at: NSPoint(x: cx + 12, y: cy + 14), size: 32, weight: .bold, color: .white)
    }

    y -= (cardH + 10) * 2 + 30

    // Provider Usage section
    drawText("Provider Usage", at: NSPoint(x: mx, y: y), size: 22, weight: .semibold, color: .white)
    y -= 30

    let providers: [(String, Double, String, NSColor)] = [
        ("Claude", 0.85, "85%", orange),
        ("Codex", 0.62, "62%", blue),
        ("Gemini", 0.45, "45%", purple),
        ("Ollama", 0.30, "30%", teal),
        ("OpenRouter", 0.18, "18%", cyan),
    ]

    for p in providers {
        drawText(p.0, at: NSPoint(x: mx, y: y), size: 15, weight: .medium, color: .white)
        drawText(p.2, at: NSPoint(x: logW - mx - 40, y: y), size: 14, weight: .bold, color: p.3)
        y -= 22
        let barRect = NSRect(x: mx, y: y, width: contentW, height: 8)
        drawRoundedRect(barRect, radius: 4, fill: p.3.withAlphaComponent(0.15))
        let fillRect = NSRect(x: mx, y: y, width: contentW * CGFloat(p.1), height: 8)
        drawRoundedRect(fillRect, radius: 4, fill: p.3)
        y -= 30
    }

    y -= 15

    // Activity Timeline
    drawText("Activity Timeline", at: NSPoint(x: mx, y: y), size: 22, weight: .semibold, color: .white)
    y -= 30

    // Mini bar chart (24 hours)
    let barCount = 24
    let barW = (contentW - CGFloat(barCount - 1) * 3) / CGFloat(barCount)
    let maxBarH: CGFloat = 100
    let values: [Double] = [0.1, 0.15, 0.05, 0.02, 0.01, 0.03, 0.2, 0.5, 0.8, 0.95, 0.7, 0.65, 0.85, 0.9, 0.75, 0.6, 0.8, 0.95, 0.7, 0.4, 0.3, 0.25, 0.15, 0.1]
    for i in 0..<barCount {
        let bx = mx + CGFloat(i) * (barW + 3)
        let bh = maxBarH * CGFloat(values[i])
        let by = y - maxBarH
        drawRoundedRect(NSRect(x: bx, y: by, width: barW, height: maxBarH), radius: 3, fill: blue.withAlphaComponent(0.1))
        drawRoundedRect(NSRect(x: bx, y: by, width: barW, height: bh), radius: 3, fill: blue.withAlphaComponent(0.7))
    }
    y -= maxBarH + 5
    drawText("12AM", at: NSPoint(x: mx, y: y - 14), size: 10, weight: .regular, color: dimColor)
    drawText("6AM", at: NSPoint(x: mx + contentW * 0.25 - 10, y: y - 14), size: 10, weight: .regular, color: dimColor)
    drawText("12PM", at: NSPoint(x: mx + contentW * 0.5 - 12, y: y - 14), size: 10, weight: .regular, color: dimColor)
    drawText("6PM", at: NSPoint(x: mx + contentW * 0.75 - 10, y: y - 14), size: 10, weight: .regular, color: dimColor)
    drawText("Now", at: NSPoint(x: logW - mx - 20, y: y - 14), size: 10, weight: .regular, color: dimColor)
    y -= 35

    // Top Projects
    drawText("Top Projects", at: NSPoint(x: mx, y: y), size: 22, weight: .semibold, color: .white)
    y -= 10

    let projects = [
        ("my-web-app", "4.2K tokens", "$1.85"),
        ("api-service", "3.1K tokens", "$1.20"),
        ("ml-pipeline", "2.8K tokens", "$0.95"),
        ("cli-tools", "1.5K tokens", "$0.52"),
    ]

    for p in projects {
        y -= 36
        drawRoundedRect(NSRect(x: mx, y: y, width: contentW, height: 32), radius: 8, fill: cardBG)
        drawText(p.0, at: NSPoint(x: mx + 12, y: y + 8), size: 14, weight: .medium, color: .white)
        drawText(p.1, at: NSPoint(x: logW - mx - 200, y: y + 8), size: 13, weight: .regular, color: dimColor)
        drawText(p.2, at: NSPoint(x: logW - mx - 60, y: y + 8), size: 14, weight: .bold, color: green)
    }

    endDraw()
    return rep
}

// ===== PROVIDERS =====
func drawProviders() -> NSBitmapImageRep {
    let rep = makeBitmap()
    beginDraw(rep)
    drawBG()

    let mx: CGFloat = 40
    let contentW = logW - mx * 2
    var y = logH - 60

    let title = "Provider Insights"
    let titleFont = NSFont.systemFont(ofSize: 36, weight: .bold)
    let titleSize = (title as NSString).size(withAttributes: [.font: titleFont])
    drawText(title, at: NSPoint(x: (logW - titleSize.width) / 2, y: y - 36), size: 36, weight: .bold, color: .white)

    let sub = "Monitor quotas and costs in real-time"
    let subFont = NSFont.systemFont(ofSize: 20, weight: .medium)
    let subSize = (sub as NSString).size(withAttributes: [.font: subFont])
    drawText(sub, at: NSPoint(x: (logW - subSize.width) / 2, y: y - 68), size: 20, weight: .medium, color: dimColor)

    y -= 110

    // Provider cards - 2 column layout for iPad
    let providers: [(String, String, String, String, String, Double, NSColor)] = [
        ("Claude", "Active", "8.2K", "$3.41", "Anthropic", 0.82, orange),
        ("Codex", "Active", "2.8K", "$0.92", "OpenAI", 0.55, blue),
        ("Gemini", "Active", "1.1K", "$0.38", "Google", 0.35, purple),
        ("Ollama", "Local", "340", "Free", "Local", 0.20, teal),
        ("OpenRouter", "Active", "520", "$0.28", "Multi", 0.15, cyan),
        ("GitHub Copilot", "Active", "1.9K", "$0.00", "Included", 0.60, green),
    ]

    let colW = (contentW - 15) / 2
    let cardH: CGFloat = 160

    for (i, p) in providers.enumerated() {
        let col = i % 2
        let row = i / 2
        let cx = mx + CGFloat(col) * (colW + 15)
        let cy = y - CGFloat(row) * (cardH + 12) - cardH

        drawRoundedRect(NSRect(x: cx, y: cy, width: colW, height: cardH), radius: 12, fill: cardBG, stroke: p.6.withAlphaComponent(0.2))

        // Icon placeholder
        let iconRect = NSRect(x: cx + 14, y: cy + cardH - 44, width: 30, height: 30)
        drawRoundedRect(iconRect, radius: 8, fill: p.6.withAlphaComponent(0.15))
        drawText(String(p.0.prefix(1)), at: NSPoint(x: cx + 22, y: cy + cardH - 40), size: 16, weight: .bold, color: p.6)

        drawText(p.0, at: NSPoint(x: cx + 52, y: cy + cardH - 32), size: 18, weight: .bold, color: .white)
        drawText(p.1, at: NSPoint(x: cx + 52, y: cy + cardH - 52), size: 12, weight: .regular, color: dimColor)
        drawText(p.4, at: NSPoint(x: cx + colW - 70, y: cy + cardH - 32), size: 11, weight: .medium, color: dimColor)

        // Stats
        drawText("Today", at: NSPoint(x: cx + 14, y: cy + cardH - 75), size: 11, weight: .regular, color: dimColor)
        drawText(p.2, at: NSPoint(x: cx + 14, y: cy + cardH - 110), size: 28, weight: .bold, color: .white)
        drawText(p.3, at: NSPoint(x: cx + 14, y: cy + cardH - 130), size: 15, weight: .medium, color: green)

        // Quota bar
        let barRect = NSRect(x: cx + 14, y: cy + 14, width: colW - 28, height: 8)
        drawRoundedRect(barRect, radius: 4, fill: p.6.withAlphaComponent(0.15))
        let fillW = (colW - 28) * CGFloat(p.5)
        drawRoundedRect(NSRect(x: cx + 14, y: cy + 14, width: fillW, height: 8), radius: 4, fill: p.6)
    }

    y -= (cardH + 12) * 3 + 25

    // Cost Breakdown
    drawText("Cost Breakdown Today", at: NSPoint(x: mx, y: y), size: 22, weight: .semibold, color: .white)
    y -= 15

    let costs = [
        ("Claude (Opus)", "$2.10", 0.42, orange),
        ("Claude (Sonnet)", "$1.31", 0.26, orange.withAlphaComponent(0.7)),
        ("Codex", "$0.92", 0.18, blue),
        ("Gemini", "$0.38", 0.08, purple),
        ("OpenRouter", "$0.28", 0.06, cyan),
    ]

    for c in costs {
        y -= 34
        drawRoundedRect(NSRect(x: mx, y: y, width: contentW, height: 30), radius: 8, fill: cardBG)
        drawText(c.0, at: NSPoint(x: mx + 12, y: y + 7), size: 14, weight: .medium, color: .white)
        drawText(c.1, at: NSPoint(x: logW - mx - 60, y: y + 7), size: 14, weight: .bold, color: green)

        // Mini proportion bar
        let barX = mx + contentW * 0.55
        let barW = contentW * 0.3
        drawRoundedRect(NSRect(x: barX, y: y + 12, width: barW, height: 5), radius: 2.5, fill: c.3.withAlphaComponent(0.15))
        drawRoundedRect(NSRect(x: barX, y: y + 12, width: barW * CGFloat(c.2), height: 5), radius: 2.5, fill: c.3)
    }

    y -= 30
    let totalText = "Total: $4.99"
    let totalFont = NSFont.systemFont(ofSize: 18, weight: .bold)
    let totalSize = (totalText as NSString).size(withAttributes: [.font: totalFont])
    drawText(totalText, at: NSPoint(x: logW - mx - totalSize.width, y: y), size: 18, weight: .bold, color: .white)

    endDraw()
    return rep
}

// ===== ALERTS =====
func drawAlerts() -> NSBitmapImageRep {
    let rep = makeBitmap()
    beginDraw(rep)
    drawBG()

    let mx: CGFloat = 40
    let contentW = logW - mx * 2
    var y = logH - 60

    let title = "Stay Informed"
    let titleFont = NSFont.systemFont(ofSize: 36, weight: .bold)
    let titleSize = (title as NSString).size(withAttributes: [.font: titleFont])
    drawText(title, at: NSPoint(x: (logW - titleSize.width) / 2, y: y - 36), size: 36, weight: .bold, color: .white)

    let sub = "Smart alerts for all your AI tools"
    let subFont = NSFont.systemFont(ofSize: 20, weight: .medium)
    let subSize = (sub as NSString).size(withAttributes: [.font: subFont])
    drawText(sub, at: NSPoint(x: (logW - subSize.width) / 2, y: y - 68), size: 20, weight: .medium, color: dimColor)

    y -= 110

    // Badge pills
    let critRect = NSRect(x: mx, y: y - 2, width: 100, height: 26)
    drawRoundedRect(critRect, radius: 13, fill: NSColor.red.withAlphaComponent(0.15))
    drawText("1 critical", at: NSPoint(x: mx + 10, y: y + 2), size: 13, weight: .semibold, color: .red)

    let warnRect = NSRect(x: mx + 115, y: y - 2, width: 100, height: 26)
    drawRoundedRect(warnRect, radius: 13, fill: NSColor.orange.withAlphaComponent(0.15))
    drawText("1 warning", at: NSPoint(x: mx + 125, y: y + 2), size: 13, weight: .semibold, color: .orange)

    let infoRect = NSRect(x: mx + 230, y: y - 2, width: 70, height: 26)
    drawRoundedRect(infoRect, radius: 13, fill: blue.withAlphaComponent(0.15))
    drawText("2 info", at: NSPoint(x: mx + 240, y: y + 2), size: 13, weight: .semibold, color: blue)

    y -= 45

    // Segmented control
    let segRect = NSRect(x: mx, y: y - 6, width: contentW, height: 32)
    drawRoundedRect(segRect, radius: 8, fill: cardBG)
    let selW = contentW / 3 - 6
    drawRoundedRect(NSRect(x: mx + 4, y: y - 2, width: selW, height: 24), radius: 6, fill: blue.withAlphaComponent(0.3))
    drawText("Open (4)", at: NSPoint(x: mx + selW / 2 - 24, y: y + 1), size: 13, weight: .semibold, color: .white)
    drawText("Resolved", at: NSPoint(x: mx + contentW / 3 + selW / 2 - 24, y: y + 1), size: 13, weight: .medium, color: dimColor)
    drawText("All", at: NSPoint(x: mx + contentW * 2 / 3 + selW / 2 - 8, y: y + 1), size: 13, weight: .medium, color: dimColor)

    y -= 45

    // Alert cards
    let alerts: [(String, String, String, NSColor, String, String)] = [
        ("Critical", "Quota Low: Claude", "Claude usage exceeded 90% of your daily quota. Current usage: 8.2K / 9K tokens. Consider reducing usage or upgrading plan.", .red, "2m ago", "Throttling may occur soon"),
        ("Warning", "Usage Spike Detected", "Codex usage increased 3x in the last hour. An automated session appears to be running repeated queries.", .orange, "15m ago", "Monitor closely"),
        ("Info", "Helper Reconnected", "macbook-pro helper reconnected after 5 min disconnect. All sessions restored. No data was lost during the brief interruption.", blue, "1h ago", "Auto-resolved"),
        ("Info", "New Provider Added", "GitHub Copilot was detected and added to monitoring. Usage tracking has started automatically.", blue, "3h ago", "No action needed"),
    ]

    for a in alerts {
        let cardH: CGFloat = 180
        let cardRect = NSRect(x: mx, y: y - cardH, width: contentW, height: cardH)
        drawRoundedRect(cardRect, radius: 12, fill: a.3.withAlphaComponent(0.04), stroke: a.3.withAlphaComponent(0.2))

        // Header
        drawCircle(at: NSPoint(x: mx + 18, y: y - 18), radius: 5, color: a.3)
        drawText(a.0, at: NSPoint(x: mx + 30, y: y - 24), size: 12, weight: .bold, color: a.3)
        drawText(a.4, at: NSPoint(x: mx + contentW - 70, y: y - 22), size: 11, weight: .regular, color: dimColor)

        drawText(a.1, at: NSPoint(x: mx + 16, y: y - 48), size: 17, weight: .semibold, color: .white)

        // Description (multi-line approximation)
        let desc = a.2
        let lineLen = 80
        var descY = y - 72
        var remaining = desc
        while !remaining.isEmpty && descY > cardRect.minY + 50 {
            let end = remaining.index(remaining.startIndex, offsetBy: min(lineLen, remaining.count))
            var line = String(remaining[..<end])
            if end != remaining.endIndex {
                if let space = line.lastIndex(of: " ") {
                    line = String(line[..<space])
                }
            }
            drawText(line, at: NSPoint(x: mx + 16, y: descY), size: 13, weight: .regular, color: NSColor(calibratedWhite: 0.55, alpha: 1.0))
            remaining = String(remaining.dropFirst(line.count).drop(while: { $0 == " " }))
            descY -= 18
        }

        // Status note
        drawText(a.5, at: NSPoint(x: mx + 16, y: cardRect.minY + 36), size: 12, weight: .medium, color: a.3.withAlphaComponent(0.8))

        // Action buttons
        let btnY = cardRect.minY + 10
        if a.0 != "Info" {
            var bx = mx + 16.0
            let btns = [("Acknowledge", a.3), ("Resolve", green), ("Snooze 1h", NSColor.gray)]
            for btn in btns {
                let bw: CGFloat = btn.0.count > 5 ? 90 : 80
                drawRoundedRect(NSRect(x: bx, y: btnY, width: bw, height: 22), radius: 11, fill: btn.1.withAlphaComponent(0.1))
                drawText(btn.0, at: NSPoint(x: bx + 8, y: btnY + 4), size: 11, weight: .semibold, color: btn.1)
                bx += bw + 8
            }
        }

        y -= cardH + 12
    }

    endDraw()
    return rep
}

func savePNG(_ rep: NSBitmapImageRep, to path: String) {
    guard let png = rep.representation(using: .png, properties: [:]) else { return }
    try! png.write(to: URL(fileURLWithPath: path))
    print("Created: \(path) (\(rep.pixelsWide)x\(rep.pixelsHigh))")
}

let scriptDir = CommandLine.arguments[0].components(separatedBy: "/").dropLast().joined(separator: "/")
let baseDir = scriptDir.isEmpty ? "." : scriptDir
let outDir = baseDir + "/../build/ipad-screenshots"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

print("Generating iPad screenshots...")
savePNG(drawDashboard(), to: outDir + "/dashboard_ipad.png")
savePNG(drawProviders(), to: outDir + "/providers_ipad.png")
savePNG(drawAlerts(), to: outDir + "/alerts_ipad.png")
print("Done!")
