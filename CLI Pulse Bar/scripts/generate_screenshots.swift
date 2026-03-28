#!/usr/bin/env swift
// Generates App Store screenshots for CLI Pulse Bar
// Renders SwiftUI-like views using AppKit at required dimensions

import Cocoa

let OUTPUT_DIR = NSString(string: "~/Desktop/CLIPulseBar-Screenshots").expandingTildeInPath

// MARK: - Colors

struct Theme {
    static let bg = NSColor(calibratedRed: 0.11, green: 0.11, blue: 0.13, alpha: 1.0)
    static let cardBg = NSColor(calibratedRed: 0.15, green: 0.15, blue: 0.18, alpha: 1.0)
    static let accent = NSColor(calibratedRed: 0.36, green: 0.51, blue: 1.0, alpha: 1.0)
    static let text = NSColor.white
    static let secondaryText = NSColor(white: 0.6, alpha: 1.0)
    static let tertiaryText = NSColor(white: 0.4, alpha: 1.0)
    static let green = NSColor(calibratedRed: 0.30, green: 0.78, blue: 0.40, alpha: 1.0)
    static let orange = NSColor(calibratedRed: 0.95, green: 0.60, blue: 0.20, alpha: 1.0)
    static let red = NSColor(calibratedRed: 0.95, green: 0.30, blue: 0.30, alpha: 1.0)
    static let purple = NSColor(calibratedRed: 0.58, green: 0.39, blue: 0.98, alpha: 1.0)
    static let cyan = NSColor(calibratedRed: 0.30, green: 0.80, blue: 0.90, alpha: 1.0)

    static func provider(_ name: String) -> NSColor {
        switch name {
        case "Codex": return accent
        case "Gemini": return purple
        case "Claude": return orange
        case "OpenRouter": return cyan
        case "Ollama": return NSColor(calibratedRed: 0.30, green: 0.80, blue: 0.65, alpha: 1.0)
        default: return secondaryText
        }
    }
}

// MARK: - Drawing Helpers

func drawText(_ text: String, at point: NSPoint, font: NSFont, color: NSColor, maxWidth: CGFloat = 0) {
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    if maxWidth > 0 {
        let rect = NSRect(x: point.x, y: point.y, width: maxWidth, height: 200)
        (text as NSString).draw(in: rect, withAttributes: attrs)
    } else {
        (text as NSString).draw(at: point, withAttributes: attrs)
    }
}

func textSize(_ text: String, font: NSFont) -> NSSize {
    let attrs: [NSAttributedString.Key: Any] = [.font: font]
    return (text as NSString).size(withAttributes: attrs)
}

func drawRoundedRect(_ rect: NSRect, radius: CGFloat, fill: NSColor, stroke: NSColor? = nil) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    fill.setFill()
    path.fill()
    if let stroke = stroke {
        stroke.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

func drawBar(_ rect: NSRect, fraction: CGFloat, color: NSColor) {
    drawRoundedRect(rect, radius: 3, fill: color.withAlphaComponent(0.15))
    if fraction > 0 {
        let filled = NSRect(x: rect.minX, y: rect.minY, width: rect.width * min(1, fraction), height: rect.height)
        drawRoundedRect(filled, radius: 3, fill: color)
    }
}

func drawBadge(_ text: String, at point: NSPoint, color: NSColor) {
    let font = NSFont.systemFont(ofSize: 9, weight: .semibold)
    let size = textSize(text, font: font)
    let rect = NSRect(x: point.x, y: point.y - 2, width: size.width + 10, height: size.height + 4)
    drawRoundedRect(rect, radius: 7, fill: color.withAlphaComponent(0.15))
    drawText(text, at: NSPoint(x: rect.minX + 5, y: rect.minY + 2), font: font, color: color)
}

func drawSFSymbol(_ name: String, at point: NSPoint, size: CGFloat, color: NSColor) {
    if let img = NSImage(systemSymbolName: name, accessibilityDescription: nil) {
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
        let configured = img.withSymbolConfiguration(config)!
        let imgSize = configured.size
        let rect = NSRect(x: point.x, y: point.y, width: imgSize.width, height: imgSize.height)
        configured.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
        // Tint by drawing over
        color.set()
        rect.fill(using: .sourceAtop)
    }
}

// MARK: - Screenshot 1: Dashboard Overview

func drawDashboardScreenshot(width pw: CGFloat, height ph: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(pw), pixelsHigh: Int(ph),
                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pw, height: ph)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let sf = pw / 1280.0
    NSGraphicsContext.current!.cgContext.scaleBy(x: sf, y: sf)
    let width: CGFloat = 1280
    let height: CGFloat = 800

    // Background gradient
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.06, green: 0.06, blue: 0.10, alpha: 1.0),
        NSColor(calibratedRed: 0.10, green: 0.08, blue: 0.16, alpha: 1.0),
    ])!
    gradient.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: 90)

    // Title text at top
    let titleFont = NSFont.systemFont(ofSize: 32, weight: .bold)
    let titleText = "CLI Pulse Bar"
    let titleSize = textSize(titleText, font: titleFont)
    drawText(titleText, at: NSPoint(x: (width - titleSize.width) / 2, y: height - 70), font: titleFont, color: .white)

    let subtitleFont = NSFont.systemFont(ofSize: 16, weight: .regular)
    let subtitle = "Monitor your AI coding tools from the menu bar"
    let subSize = textSize(subtitle, font: subtitleFont)
    drawText(subtitle, at: NSPoint(x: (width - subSize.width) / 2, y: height - 100), font: subtitleFont, color: Theme.secondaryText)

    // Menu bar mockup at top center
    let barW: CGFloat = 380
    let barH: CGFloat = 490
    let barX = (width - barW) / 2
    let barY = height - barH - 140

    // Window shadow
    let shadowRect = NSRect(x: barX - 4, y: barY - 4, width: barW + 8, height: barH + 8)
    drawRoundedRect(shadowRect, radius: 14, fill: NSColor.black.withAlphaComponent(0.4))

    // Window background
    let windowRect = NSRect(x: barX, y: barY, width: barW, height: barH)
    drawRoundedRect(windowRect, radius: 12, fill: Theme.bg)

    let p: CGFloat = 14  // padding
    var y = barY + barH - p

    // Tab bar
    y -= 30
    let tabRect = NSRect(x: barX, y: y, width: barW, height: 30)
    drawRoundedRect(tabRect, radius: 0, fill: NSColor.black.withAlphaComponent(0.2))

    let tabs = ["Overview", "Providers", "Sessions", "Alerts", "Settings"]
    let tabIcons = ["gauge.with.dots.needle.33percent", "cpu", "terminal", "bell.badge", "gear"]
    let tabW = barW / CGFloat(tabs.count)
    for (i, tab) in tabs.enumerated() {
        let tx = barX + CGFloat(i) * tabW
        let isSelected = i == 0
        let color = isSelected ? Theme.accent : Theme.tertiaryText
        let font = NSFont.systemFont(ofSize: 8, weight: isSelected ? .semibold : .regular)
        let sz = textSize(tab, font: font)
        drawText(tab, at: NSPoint(x: tx + (tabW - sz.width) / 2, y: y + 4), font: font, color: color)
        drawSFSymbol(tabIcons[i], at: NSPoint(x: tx + (tabW - 12) / 2, y: y + 16), size: 11, color: color)
    }

    // Dashboard header
    y -= 5
    let headerFont = NSFont.systemFont(ofSize: 14, weight: .bold)
    drawText("Dashboard", at: NSPoint(x: barX + p, y: y - 18), font: headerFont, color: .white)

    // Server status
    let onlineFont = NSFont.systemFont(ofSize: 9, weight: .regular)
    drawRoundedRect(NSRect(x: barX + barW - p - 55, y: y - 16, width: 6, height: 6), radius: 3, fill: Theme.green)
    drawText("Online", at: NSPoint(x: barX + barW - p - 46, y: y - 18), font: onlineFont, color: Theme.secondaryText)

    y -= 28

    // Metrics grid - 2 rows x 3 cols
    let metrics = [
        ("Usage Today", "24.5K", "chart.bar.fill", Theme.accent),
        ("Est. Cost", "$1.85", "dollarsign.circle", Theme.green),
        ("Requests", "342", "arrow.up.arrow.down", Theme.purple),
        ("Sessions", "5", "terminal", Theme.cyan),
        ("Devices", "2", "desktopcomputer", Theme.accent),
        ("Alerts", "3", "bell.badge", Theme.orange),
    ]
    let cellW = (barW - p * 2 - 8) / 3
    let cellH: CGFloat = 52
    for (i, metric) in metrics.enumerated() {
        let col = i % 3
        let row = i / 3
        let cx = barX + p + CGFloat(col) * (cellW + 4)
        let cy = y - CGFloat(row) * (cellH + 4) - cellH

        drawRoundedRect(NSRect(x: cx, y: cy, width: cellW, height: cellH), radius: 6, fill: Theme.cardBg)
        let labelFont = NSFont.systemFont(ofSize: 9, weight: .medium)
        let valueFont = NSFont.systemFont(ofSize: 16, weight: .bold)
        drawText(metric.0, at: NSPoint(x: cx + 8, y: cy + cellH - 16), font: labelFont, color: Theme.secondaryText)
        drawText(metric.1, at: NSPoint(x: cx + 8, y: cy + 6), font: valueFont, color: .white)
    }

    y -= cellH * 2 + 16

    // Provider Usage section
    let sectionFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
    drawText("Provider Usage", at: NSPoint(x: barX + p, y: y - 14), font: sectionFont, color: .white)
    y -= 22

    let providerRect = NSRect(x: barX + p, y: y - 120, width: barW - p * 2, height: 120)
    drawRoundedRect(providerRect, radius: 8, fill: Theme.cardBg.withAlphaComponent(0.5))

    let providers = [
        ("Claude", 0.68, "18.2K · $1.05"),
        ("Codex", 0.42, "4.8K · $0.38"),
        ("Gemini", 0.25, "1.2K · $0.22"),
        ("Ollama", 0.12, "0.3K · free"),
    ]
    let provLabelFont = NSFont.systemFont(ofSize: 11, weight: .medium)
    let provDetailFont = NSFont.systemFont(ofSize: 10, weight: .regular)
    var py = providerRect.maxY - 10
    for (name, frac, detail) in providers {
        py -= 24
        drawText(name, at: NSPoint(x: providerRect.minX + 10, y: py + 8), font: provLabelFont, color: .white)
        drawText(detail, at: NSPoint(x: providerRect.maxX - 110, y: py + 8), font: provDetailFont, color: Theme.secondaryText)
        let barRect = NSRect(x: providerRect.minX + 10, y: py, width: providerRect.width - 20, height: 5)
        drawBar(barRect, fraction: CGFloat(frac), color: Theme.provider(name))
    }

    y -= 130

    // Top Projects
    drawText("Top Projects", at: NSPoint(x: barX + p, y: y - 14), font: sectionFont, color: .white)
    y -= 22

    let projRect = NSRect(x: barX + p, y: y - 72, width: barW - p * 2, height: 72)
    drawRoundedRect(projRect, radius: 8, fill: Theme.cardBg.withAlphaComponent(0.5))

    let projects = [
        ("cli-pulse-ios", "12.4K", "$0.92"),
        ("backend-api", "8.1K", "$0.55"),
        ("web-dashboard", "4.0K", "$0.38"),
    ]
    let projFont = NSFont.systemFont(ofSize: 11, weight: .medium)
    let projValFont = NSFont.systemFont(ofSize: 10, weight: .medium)
    var projY = projRect.maxY - 8
    for (name, usage, cost) in projects {
        projY -= 20
        drawText(name, at: NSPoint(x: projRect.minX + 10, y: projY), font: projFont, color: .white)
        drawText(usage, at: NSPoint(x: projRect.maxX - 100, y: projY), font: projValFont, color: Theme.secondaryText)
        drawText(cost, at: NSPoint(x: projRect.maxX - 45, y: projY), font: projValFont, color: Theme.green)
    }

    // Footer
    let footerFont = NSFont.systemFont(ofSize: 8, weight: .regular)
    drawText("CLI Pulse Bar v1.0.0", at: NSPoint(x: barX + (barW - 80) / 2, y: barY + 6), font: footerFont, color: Theme.tertiaryText)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// MARK: - Screenshot 2: Providers Detail

func drawProvidersScreenshot(width pw: CGFloat, height ph: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(pw), pixelsHigh: Int(ph),
                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pw, height: ph)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let sf = pw / 1280.0
    NSGraphicsContext.current!.cgContext.scaleBy(x: sf, y: sf)
    let width: CGFloat = 1280
    let height: CGFloat = 800

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.06, green: 0.06, blue: 0.10, alpha: 1.0),
        NSColor(calibratedRed: 0.10, green: 0.08, blue: 0.16, alpha: 1.0),
    ])!
    gradient.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: 90)

    drawText("Track Every AI Provider", at: NSPoint(x: 0, y: height - 70),
             font: NSFont.systemFont(ofSize: 32, weight: .bold), color: .white, maxWidth: width)
    // Center it
    let t2 = "Track Every AI Provider"
    let t2s = textSize(t2, font: NSFont.systemFont(ofSize: 32, weight: .bold))
    drawText(t2, at: NSPoint(x: (width - t2s.width) / 2, y: height - 70),
             font: NSFont.systemFont(ofSize: 32, weight: .bold), color: .white)
    let s2 = "Usage, costs, and quota for Claude, Codex, Gemini, OpenRouter & Ollama"
    let s2s = textSize(s2, font: NSFont.systemFont(ofSize: 14, weight: .regular))
    drawText(s2, at: NSPoint(x: (width - s2s.width) / 2, y: height - 98),
             font: NSFont.systemFont(ofSize: 14, weight: .regular), color: Theme.secondaryText)

    // Provider cards
    let barW: CGFloat = 380
    let barX = (width - barW) / 2
    var y = height - 140

    let providerData: [(String, String, String, String, String, Double)] = [
        ("Claude", "Active · 3 sessions", "18.2K", "$1.05", "231.8K remaining", 0.32),
        ("Codex", "Active · 1 session", "4.8K", "$0.38", "495.2K remaining", 0.10),
        ("Gemini", "Active · 1 session", "1.2K", "$0.22", "298.8K remaining", 0.04),
        ("OpenRouter", "Idle", "0.5K", "$0.05", "199.5K remaining", 0.03),
        ("Ollama", "Active · local", "0.3K", "free", "unlimited", 0.00),
    ]

    for (name, status, today, cost, remaining, quotaUsed) in providerData {
        let cardH: CGFloat = 72
        y -= cardH + 8
        let cardRect = NSRect(x: barX, y: y, width: barW, height: cardH)
        drawRoundedRect(cardRect, radius: 8, fill: Theme.cardBg)
        drawRoundedRect(cardRect, radius: 8, fill: .clear, stroke: Theme.provider(name).withAlphaComponent(0.2))

        // Provider name + icon
        let iconRect = NSRect(x: cardRect.minX + 10, y: cardRect.maxY - 30, width: 24, height: 24)
        drawRoundedRect(iconRect, radius: 5, fill: Theme.provider(name).withAlphaComponent(0.12))
        let nameFont = NSFont.systemFont(ofSize: 12, weight: .bold)
        drawText(name, at: NSPoint(x: iconRect.maxX + 6, y: cardRect.maxY - 24), font: nameFont, color: .white)
        let statusFont = NSFont.systemFont(ofSize: 9, weight: .regular)
        drawText(status, at: NSPoint(x: iconRect.maxX + 6, y: cardRect.maxY - 36), font: statusFont, color: Theme.secondaryText)

        // Badge
        let badgeText = quotaUsed > 0.7 ? "LOW" : quotaUsed > 0.4 ? "MODERATE" : "OK"
        let badgeColor = quotaUsed > 0.7 ? Theme.red : quotaUsed > 0.4 ? Theme.orange : Theme.green
        drawBadge(badgeText, at: NSPoint(x: cardRect.maxX - 55, y: cardRect.maxY - 22), color: badgeColor)

        // Usage values
        let valFont = NSFont.systemFont(ofSize: 14, weight: .bold)
        let labelFont = NSFont.systemFont(ofSize: 9, weight: .regular)
        drawText("Today", at: NSPoint(x: cardRect.minX + 10, y: y + 20), font: labelFont, color: Theme.tertiaryText)
        drawText(today, at: NSPoint(x: cardRect.minX + 10, y: y + 4), font: valFont, color: .white)
        drawText(cost, at: NSPoint(x: cardRect.minX + 75, y: y + 4), font: NSFont.systemFont(ofSize: 10, weight: .medium), color: Theme.green)

        // Quota bar
        if quotaUsed > 0 {
            let qBarRect = NSRect(x: cardRect.minX + 130, y: y + 8, width: cardRect.width - 145, height: 5)
            drawBar(qBarRect, fraction: CGFloat(quotaUsed), color: Theme.provider(name))
            drawText(remaining, at: NSPoint(x: cardRect.minX + 130, y: y + 16), font: NSFont.systemFont(ofSize: 8, weight: .regular), color: Theme.tertiaryText)
        }
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// MARK: - Screenshot 3: Alerts

func drawAlertsScreenshot(width pw: CGFloat, height ph: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(pw), pixelsHigh: Int(ph),
                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pw, height: ph)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let sf = pw / 1280.0
    NSGraphicsContext.current!.cgContext.scaleBy(x: sf, y: sf)
    let width: CGFloat = 1280
    let height: CGFloat = 800

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.06, green: 0.06, blue: 0.10, alpha: 1.0),
        NSColor(calibratedRed: 0.12, green: 0.06, blue: 0.10, alpha: 1.0),
    ])!
    gradient.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: 90)

    let t = "Smart Alerts & Notifications"
    let ts = textSize(t, font: NSFont.systemFont(ofSize: 32, weight: .bold))
    drawText(t, at: NSPoint(x: (width - ts.width) / 2, y: height - 70),
             font: NSFont.systemFont(ofSize: 32, weight: .bold), color: .white)
    let s = "Stay on top of usage spikes, quota warnings, and session issues"
    let ss = textSize(s, font: NSFont.systemFont(ofSize: 14, weight: .regular))
    drawText(s, at: NSPoint(x: (width - ss.width) / 2, y: height - 98),
             font: NSFont.systemFont(ofSize: 14, weight: .regular), color: Theme.secondaryText)

    let barW: CGFloat = 380
    let barX = (width - barW) / 2
    var y = height - 140

    let alerts: [(String, String, String, String, String, NSColor)] = [
        ("Warning", "Claude quota below 20%", "Remaining quota is 48,200 tokens. Consider upgrading your plan.", "Claude", "2m ago", Theme.orange),
        ("Critical", "Device CPU usage elevated", "Helper sampled CPU usage at 92%. Performance may be affected.", "MacBook Pro", "5m ago", Theme.red),
        ("Info", "backend-api session running long", "Session has been active for over 3 hours with 245 requests.", "Codex", "12m ago", Theme.accent),
        ("Warning", "Usage spike detected", "Daily usage increased by 340% compared to 7-day average.", "Gemini", "25m ago", Theme.orange),
    ]

    for (severity, title, message, related, time, color) in alerts {
        let cardH: CGFloat = 90
        y -= cardH + 8
        let cardRect = NSRect(x: barX, y: y, width: barW, height: cardH)
        drawRoundedRect(cardRect, radius: 8, fill: color.withAlphaComponent(0.06))
        drawRoundedRect(cardRect, radius: 8, fill: .clear, stroke: color.withAlphaComponent(0.2))

        // Severity dot + title
        let dotRect = NSRect(x: cardRect.minX + 12, y: cardRect.maxY - 20, width: 8, height: 8)
        drawRoundedRect(dotRect, radius: 4, fill: color)
        drawText(title, at: NSPoint(x: dotRect.maxX + 6, y: cardRect.maxY - 22),
                 font: NSFont.systemFont(ofSize: 11, weight: .semibold), color: .white)
        drawText(time, at: NSPoint(x: cardRect.maxX - 45, y: cardRect.maxY - 20),
                 font: NSFont.systemFont(ofSize: 9, weight: .regular), color: Theme.tertiaryText)

        // Message
        drawText(message, at: NSPoint(x: cardRect.minX + 12, y: cardRect.maxY - 42),
                 font: NSFont.systemFont(ofSize: 10, weight: .regular), color: Theme.secondaryText, maxWidth: barW - 24)

        // Related chip
        drawBadge(related, at: NSPoint(x: cardRect.minX + 12, y: y + 22), color: Theme.tertiaryText)

        // Action buttons
        let btnFont = NSFont.systemFont(ofSize: 9, weight: .semibold)
        let ackRect = NSRect(x: cardRect.minX + 12, y: y + 4, width: 30, height: 14)
        drawRoundedRect(ackRect, radius: 7, fill: Theme.accent.withAlphaComponent(0.12))
        drawText("Ack", at: NSPoint(x: ackRect.minX + 6, y: y + 5), font: btnFont, color: Theme.accent)

        let resolveRect = NSRect(x: ackRect.maxX + 4, y: y + 4, width: 48, height: 14)
        drawRoundedRect(resolveRect, radius: 7, fill: Theme.green.withAlphaComponent(0.12))
        drawText("Resolve", at: NSPoint(x: resolveRect.minX + 6, y: y + 5), font: btnFont, color: Theme.green)

        let snoozeRect = NSRect(x: resolveRect.maxX + 4, y: y + 4, width: 42, height: 14)
        drawRoundedRect(snoozeRect, radius: 7, fill: Theme.orange.withAlphaComponent(0.12))
        drawText("Snooze", at: NSPoint(x: snoozeRect.minX + 6, y: y + 5), font: btnFont, color: Theme.orange)
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// MARK: - Generate

func save(_ rep: NSBitmapImageRep, name: String) {
    guard let png = rep.representation(using: .png, properties: [:]) else { return }
    let path = "\(OUTPUT_DIR)/\(name).png"
    try! png.write(to: URL(fileURLWithPath: path))
    print("  Saved: \(name).png (\(rep.pixelsWide)x\(rep.pixelsHigh))")
}

// Create output dir
try! FileManager.default.createDirectory(atPath: OUTPUT_DIR, withIntermediateDirectories: true)

print("Generating App Store screenshots...")

// Mac App Store requires: 1280x800, 1440x900, 2560x1600, or 2880x1800
let sizes: [(String, CGFloat, CGFloat)] = [
    ("1280x800", 1280, 800),
    ("2880x1800", 2880, 1800),
]

for (label, w, h) in sizes {
    save(drawDashboardScreenshot(width: w, height: h), name: "01_dashboard_\(label)")
    save(drawProvidersScreenshot(width: w, height: h), name: "02_providers_\(label)")
    save(drawAlertsScreenshot(width: w, height: h), name: "03_alerts_\(label)")
}

print("\nDone! Screenshots saved to: \(OUTPUT_DIR)")
print("Upload these to App Store Connect > macOS Screenshots")
