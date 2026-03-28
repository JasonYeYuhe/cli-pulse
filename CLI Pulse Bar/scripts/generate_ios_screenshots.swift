#!/usr/bin/env swift
// Generates CLI Pulse iOS App Store screenshots
// iPhone 6.7" (1290x2796) - required for App Store

import Cocoa

let screenWidth: CGFloat = 1290
let screenHeight: CGFloat = 2796

let bgDark = NSColor(calibratedRed: 0.08, green: 0.06, blue: 0.16, alpha: 1.0)
let bgCard = NSColor(calibratedRed: 0.13, green: 0.11, blue: 0.22, alpha: 1.0)
let accentBlue = NSColor(calibratedRed: 0.36, green: 0.51, blue: 1.0, alpha: 1.0)
let accentGreen = NSColor(calibratedRed: 0.2, green: 0.8, blue: 0.4, alpha: 1.0)
let accentOrange = NSColor(calibratedRed: 0.90, green: 0.55, blue: 0.20, alpha: 1.0)
let accentPurple = NSColor(calibratedRed: 0.58, green: 0.39, blue: 0.98, alpha: 1.0)
let accentCyan = NSColor(calibratedRed: 0.30, green: 0.80, blue: 0.90, alpha: 1.0)
let accentTeal = NSColor(calibratedRed: 0.30, green: 0.80, blue: 0.65, alpha: 1.0)
let textSecondary = NSColor(calibratedWhite: 0.55, alpha: 1.0)
let textTertiary = NSColor(calibratedWhite: 0.35, alpha: 1.0)

func createCanvas() -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(screenWidth), pixelsHigh: Int(screenHeight),
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: screenWidth, height: screenHeight)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Background gradient
    let bg = NSGradient(colors: [
        NSColor(calibratedRed: 0.06, green: 0.04, blue: 0.14, alpha: 1.0),
        NSColor(calibratedRed: 0.10, green: 0.07, blue: 0.22, alpha: 1.0),
    ])!
    bg.draw(in: NSRect(x: 0, y: 0, width: screenWidth, height: screenHeight), angle: -90)
    return rep
}

func finishCanvas(_ rep: NSBitmapImageRep) {
    NSGraphicsContext.restoreGraphicsState()
}

// MARK: - Drawing Helpers

func drawText(_ text: String, at point: NSPoint, size: CGFloat, weight: NSFont.Weight, color: NSColor, maxWidth: CGFloat? = nil) {
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    if let maxWidth = maxWidth {
        let rect = NSRect(x: point.x, y: point.y, width: maxWidth, height: size * 4)
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        attrStr.draw(in: rect)
    } else {
        (text as NSString).draw(at: point, withAttributes: attrs)
    }
}

func drawRoundedRect(_ rect: NSRect, radius: CGFloat, fill: NSColor, stroke: NSColor? = nil, strokeWidth: CGFloat = 2) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    fill.setFill()
    path.fill()
    if let stroke = stroke {
        stroke.setStroke()
        path.lineWidth = strokeWidth
        path.stroke()
    }
}

func drawCircle(at center: NSPoint, radius: CGFloat, color: NSColor) {
    let path = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    color.setFill()
    path.fill()
}

func drawBar(at rect: NSRect, fraction: CGFloat, color: NSColor) {
    drawRoundedRect(rect, radius: rect.height / 2, fill: color.withAlphaComponent(0.15))
    if fraction > 0 {
        let filled = NSRect(x: rect.minX, y: rect.minY, width: rect.width * min(1, fraction), height: rect.height)
        drawRoundedRect(filled, radius: rect.height / 2, fill: color)
    }
}

func drawTitleBanner(_ title: String, _ subtitle: String) {
    // Title at top
    let titleFont = NSFont.systemFont(ofSize: 80, weight: .bold)
    let titleAttrs: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: NSColor.white]
    let titleSize = (title as NSString).size(withAttributes: titleAttrs)
    (title as NSString).draw(at: NSPoint(x: (screenWidth - titleSize.width) / 2, y: screenHeight - 200), withAttributes: titleAttrs)

    let subFont = NSFont.systemFont(ofSize: 44, weight: .medium)
    let subAttrs: [NSAttributedString.Key: Any] = [.font: subFont, .foregroundColor: NSColor(calibratedRed: 0.6, green: 0.6, blue: 0.8, alpha: 1.0)]
    let subSize = (subtitle as NSString).size(withAttributes: subAttrs)
    (subtitle as NSString).draw(at: NSPoint(x: (screenWidth - subSize.width) / 2, y: screenHeight - 270), withAttributes: subAttrs)
}

// MARK: - Screenshot 1: Dashboard

func drawDashboard() -> NSBitmapImageRep {
    let rep = createCanvas()
    drawTitleBanner("Your AI Dashboard", "Track usage across all providers")

    let margin: CGFloat = 80
    let w = screenWidth - margin * 2
    var y = screenHeight - 380

    // Status bar
    drawCircle(at: NSPoint(x: margin + 12, y: y + 12), radius: 10, color: accentGreen)
    drawText("Server Online", at: NSPoint(x: margin + 32, y: y - 2), size: 34, weight: .medium, color: textSecondary)
    drawText("Last sync: 2s ago", at: NSPoint(x: w - 80, y: y - 2), size: 28, weight: .regular, color: textTertiary)
    y -= 70

    // 2x3 Metric cards
    let cardW = (w - 40) / 2
    let cardH: CGFloat = 240
    let gap: CGFloat = 30
    let metrics: [(String, String, NSColor)] = [
        ("Usage Today", "12.4K", accentBlue),
        ("Est. Cost", "$4.82", accentGreen),
        ("Requests", "847", accentPurple),
        ("Sessions", "5", accentCyan),
        ("Devices", "3", accentBlue),
        ("Alerts", "2", accentOrange),
    ]

    for (i, metric) in metrics.enumerated() {
        let col = i % 2
        let row = i / 2
        let cardX = margin + CGFloat(col) * (cardW + 40)
        let cardY = y - CGFloat(row) * (cardH + gap) - cardH

        drawRoundedRect(NSRect(x: cardX, y: cardY, width: cardW, height: cardH),
                        radius: 24, fill: bgCard, stroke: metric.2.withAlphaComponent(0.15))

        // Color accent bar at top
        drawRoundedRect(NSRect(x: cardX + 20, y: cardY + cardH - 40, width: 50, height: 6), radius: 3, fill: metric.2)

        drawText(metric.0, at: NSPoint(x: cardX + 24, y: cardY + cardH - 80), size: 30, weight: .medium, color: textSecondary)
        drawText(metric.1, at: NSPoint(x: cardX + 24, y: cardY + 40), size: 72, weight: .bold, color: .white)
    }

    y -= (cardH + gap) * 3 + 50

    // Provider Usage section
    drawText("Provider Usage", at: NSPoint(x: margin, y: y), size: 42, weight: .bold, color: .white)
    y -= 60

    let providers: [(String, Double, NSColor)] = [
        ("Claude", 0.85, accentOrange),
        ("Codex", 0.62, accentBlue),
        ("Gemini", 0.45, accentPurple),
        ("Ollama", 0.30, accentTeal),
        ("OpenRouter", 0.18, accentCyan),
    ]

    for p in providers {
        // Provider row card
        let rowH: CGFloat = 90
        let rowRect = NSRect(x: margin, y: y - rowH, width: w, height: rowH)
        drawRoundedRect(rowRect, radius: 16, fill: bgCard.withAlphaComponent(0.6))

        drawText(p.0, at: NSPoint(x: margin + 24, y: rowRect.maxY - 42), size: 32, weight: .semibold, color: .white)
        let pctText = "\(Int(p.1 * 100))%"
        drawText(pctText, at: NSPoint(x: margin + w - 90, y: rowRect.maxY - 42), size: 30, weight: .bold, color: p.2)

        drawBar(at: NSRect(x: margin + 24, y: rowRect.minY + 16, width: w - 48, height: 14), fraction: CGFloat(p.1), color: p.2)

        y -= rowH + 12
    }

    finishCanvas(rep)
    return rep
}

// MARK: - Screenshot 2: Providers

func drawProviders() -> NSBitmapImageRep {
    let rep = createCanvas()
    drawTitleBanner("Provider Insights", "Monitor quotas and costs in real time")

    let margin: CGFloat = 80
    let w = screenWidth - margin * 2
    var y = screenHeight - 380

    let providerData: [(String, String, String, String, String, Double, NSColor)] = [
        ("Claude", "Active", "8.2K", "$3.41", "5.2K", 0.68, accentOrange),
        ("Codex", "Active", "2.8K", "$0.92", "1.4K", 0.42, accentBlue),
        ("Gemini", "Active", "1.1K", "$0.38", "800", 0.25, accentPurple),
        ("OpenRouter", "Idle", "0.5K", "$0.05", "200", 0.10, accentCyan),
        ("Ollama", "Local", "340", "Free", "340", 0.00, accentTeal),
    ]

    for p in providerData {
        let cardH: CGFloat = 380
        let cardRect = NSRect(x: margin, y: y - cardH, width: w, height: cardH)
        drawRoundedRect(cardRect, radius: 24, fill: bgCard, stroke: p.6.withAlphaComponent(0.2))

        // Header: icon + name + status
        let iconRect = NSRect(x: margin + 24, y: cardRect.maxY - 80, width: 56, height: 56)
        drawRoundedRect(iconRect, radius: 14, fill: p.6.withAlphaComponent(0.15))
        drawText(String(p.0.prefix(1)), at: NSPoint(x: iconRect.minX + 14, y: iconRect.minY + 10), size: 32, weight: .bold, color: p.6)

        drawText(p.0, at: NSPoint(x: iconRect.maxX + 16, y: cardRect.maxY - 56), size: 36, weight: .bold, color: .white)
        drawText(p.1, at: NSPoint(x: iconRect.maxX + 16, y: cardRect.maxY - 90), size: 26, weight: .regular, color: textSecondary)

        // Status badge
        let badgeColor = p.1 == "Active" ? accentGreen : textTertiary
        let badgeRect = NSRect(x: cardRect.maxX - 110, y: cardRect.maxY - 68, width: 80, height: 34)
        drawRoundedRect(badgeRect, radius: 17, fill: badgeColor.withAlphaComponent(0.15))
        drawText(p.1 == "Active" ? "OK" : p.1, at: NSPoint(x: badgeRect.minX + (p.1 == "Active" ? 26 : 12), y: badgeRect.minY + 6), size: 22, weight: .bold, color: badgeColor)

        // Stats row
        let statsY = cardRect.maxY - 160
        let statW = (w - 48) / 3

        drawText("Today", at: NSPoint(x: margin + 24, y: statsY + 40), size: 24, weight: .regular, color: textTertiary)
        drawText(p.2, at: NSPoint(x: margin + 24, y: statsY), size: 48, weight: .bold, color: .white)

        drawText("Cost", at: NSPoint(x: margin + 24 + statW, y: statsY + 40), size: 24, weight: .regular, color: textTertiary)
        drawText(p.3, at: NSPoint(x: margin + 24 + statW, y: statsY), size: 48, weight: .bold, color: accentGreen)

        drawText("This Week", at: NSPoint(x: margin + 24 + statW * 2, y: statsY + 40), size: 24, weight: .regular, color: textTertiary)
        drawText(p.4, at: NSPoint(x: margin + 24 + statW * 2, y: statsY), size: 48, weight: .bold, color: .white)

        // Quota bar
        if p.5 > 0 {
            let barY = cardRect.minY + 40
            drawText("Quota", at: NSPoint(x: margin + 24, y: barY + 24), size: 24, weight: .medium, color: textSecondary)
            drawBar(at: NSRect(x: margin + 24, y: barY, width: w - 48, height: 14), fraction: CGFloat(p.5), color: p.6)
        }

        y -= cardH + 20
    }

    finishCanvas(rep)
    return rep
}

// MARK: - Screenshot 3: Alerts

func drawAlerts() -> NSBitmapImageRep {
    let rep = createCanvas()
    drawTitleBanner("Stay Alert", "Manage alerts with one tap")

    let margin: CGFloat = 80
    let w = screenWidth - margin * 2
    var y = screenHeight - 380

    // Summary badges
    let critRect = NSRect(x: margin, y: y - 10, width: 200, height: 48)
    drawRoundedRect(critRect, radius: 24, fill: NSColor.red.withAlphaComponent(0.15))
    drawText("1 critical", at: NSPoint(x: critRect.minX + 20, y: critRect.minY + 10), size: 28, weight: .semibold, color: .red)

    let warnRect = NSRect(x: margin + 220, y: y - 10, width: 200, height: 48)
    drawRoundedRect(warnRect, radius: 24, fill: NSColor.orange.withAlphaComponent(0.15))
    drawText("1 warning", at: NSPoint(x: warnRect.minX + 20, y: warnRect.minY + 10), size: 28, weight: .semibold, color: .orange)

    let infoRect = NSRect(x: margin + 440, y: y - 10, width: 170, height: 48)
    drawRoundedRect(infoRect, radius: 24, fill: accentBlue.withAlphaComponent(0.15))
    drawText("1 info", at: NSPoint(x: infoRect.minX + 20, y: infoRect.minY + 10), size: 28, weight: .semibold, color: accentBlue)
    y -= 80

    // Segmented control
    let segRect = NSRect(x: margin, y: y - 15, width: w, height: 56)
    drawRoundedRect(segRect, radius: 12, fill: bgCard)
    let selW = w / 3
    drawRoundedRect(NSRect(x: margin + 4, y: segRect.minY + 4, width: selW - 8, height: 48), radius: 10, fill: accentBlue.withAlphaComponent(0.3))
    drawText("Open", at: NSPoint(x: margin + selW / 2 - 40, y: segRect.minY + 12), size: 28, weight: .semibold, color: .white)
    drawText("Resolved", at: NSPoint(x: margin + selW + selW / 2 - 65, y: segRect.minY + 12), size: 28, weight: .medium, color: textSecondary)
    drawText("All", at: NSPoint(x: margin + selW * 2 + selW / 2 - 22, y: segRect.minY + 12), size: 28, weight: .medium, color: textSecondary)
    y -= 90

    // Alert cards
    let alerts: [(String, String, String, String, String, NSColor)] = [
        ("Critical", "Quota Low: Claude", "Claude usage has exceeded 90% of daily quota.\nConsider reducing usage or upgrading your plan.", "Claude", "2m ago", NSColor.red),
        ("Warning", "Usage Spike Detected", "Codex usage spiked 3x in the last hour.\nCheck for runaway sessions.", "Codex", "15m ago", NSColor.orange),
        ("Info", "Helper Reconnected", "macbook-pro helper reconnected after brief\ndisconnect. All services restored.", "macbook-pro", "1h ago", accentBlue),
    ]

    for a in alerts {
        let cardH: CGFloat = 420
        let cardRect = NSRect(x: margin, y: y - cardH, width: w, height: cardH)
        drawRoundedRect(cardRect, radius: 24, fill: a.5.withAlphaComponent(0.05), stroke: a.5.withAlphaComponent(0.2))

        // Severity dot + title
        drawCircle(at: NSPoint(x: margin + 32, y: cardRect.maxY - 45), radius: 10, color: a.5)
        drawText(a.1, at: NSPoint(x: margin + 54, y: cardRect.maxY - 60), size: 32, weight: .bold, color: .white)
        drawText(a.4, at: NSPoint(x: cardRect.maxX - 140, y: cardRect.maxY - 52), size: 26, weight: .regular, color: textTertiary)

        // Message
        drawText(a.2, at: NSPoint(x: margin + 30, y: cardRect.maxY - 120), size: 28, weight: .regular, color: textSecondary, maxWidth: w - 60)

        // Source chip
        let chipRect = NSRect(x: margin + 30, y: cardRect.maxY - 250, width: 160, height: 40)
        drawRoundedRect(chipRect, radius: 20, fill: NSColor(calibratedWhite: 0.2, alpha: 0.3))
        drawText(a.3, at: NSPoint(x: chipRect.minX + 16, y: chipRect.minY + 8), size: 24, weight: .regular, color: textSecondary)

        // Action buttons
        let btnY = cardRect.minY + 36
        let ackRect = NSRect(x: margin + 30, y: btnY, width: 130, height: 50)
        drawRoundedRect(ackRect, radius: 25, fill: accentBlue.withAlphaComponent(0.12))
        drawText("Ack", at: NSPoint(x: ackRect.minX + 36, y: btnY + 10), size: 28, weight: .semibold, color: accentBlue)

        let resRect = NSRect(x: ackRect.maxX + 16, y: btnY, width: 170, height: 50)
        drawRoundedRect(resRect, radius: 25, fill: accentGreen.withAlphaComponent(0.12))
        drawText("Resolve", at: NSPoint(x: resRect.minX + 30, y: btnY + 10), size: 28, weight: .semibold, color: accentGreen)

        let snzRect = NSRect(x: resRect.maxX + 16, y: btnY, width: 170, height: 50)
        drawRoundedRect(snzRect, radius: 25, fill: NSColor.orange.withAlphaComponent(0.12))
        drawText("Snooze", at: NSPoint(x: snzRect.minX + 30, y: btnY + 10), size: 28, weight: .semibold, color: .orange)

        y -= cardH + 24
    }

    finishCanvas(rep)
    return rep
}

// MARK: - Save

func savePNG(_ rep: NSBitmapImageRep, to path: String) {
    guard let png = rep.representation(using: .png, properties: [:]) else {
        print("Failed PNG for \(path)")
        return
    }
    try! png.write(to: URL(fileURLWithPath: path))
    print("Created: \(path) (\(rep.pixelsWide)x\(rep.pixelsHigh))")
}

// MARK: - Generate

let scriptDir = CommandLine.arguments[0].components(separatedBy: "/").dropLast().joined(separator: "/")
let baseDir = scriptDir.isEmpty ? "." : scriptDir
let outDir = baseDir + "/../build/ios-screenshots"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

print("Generating iOS screenshots...")

savePNG(drawDashboard(), to: outDir + "/dashboard_6.7.png")
savePNG(drawProviders(), to: outDir + "/providers_6.7.png")
savePNG(drawAlerts(), to: outDir + "/alerts_6.7.png")

print("Done!")
