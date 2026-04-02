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
let accentRed = NSColor(calibratedRed: 0.95, green: 0.25, blue: 0.30, alpha: 1.0)
let textPrimary = NSColor.white
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

/// Draw text anchored at TOP-LEFT of the text bounds (y = top edge, text goes downward)
/// In Cocoa coords: y param is the TOP of the text, we compute baseline from font metrics
func drawText(_ text: String, at point: NSPoint, size: CGFloat, weight: NSFont.Weight, color: NSColor, maxWidth: CGFloat? = nil, align: NSTextAlignment = .left) {
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    let para = NSMutableParagraphStyle()
    para.alignment = align
    para.lineBreakMode = .byWordWrapping
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: para]
    let attrStr = NSAttributedString(string: text, attributes: attrs)

    if let maxWidth = maxWidth {
        let boundingRect = attrStr.boundingRect(with: NSSize(width: maxWidth, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin])
        let drawRect = NSRect(x: point.x, y: point.y - boundingRect.height, width: maxWidth, height: boundingRect.height)
        attrStr.draw(in: drawRect)
    } else {
        let textSize = attrStr.size()
        let drawPoint = NSPoint(x: point.x, y: point.y - textSize.height)
        attrStr.draw(at: drawPoint)
    }
}

/// Measure text height for layout calculations
func textHeight(_ text: String, size: CGFloat, weight: NSFont.Weight, maxWidth: CGFloat? = nil) -> CGFloat {
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    let attrs: [NSAttributedString.Key: Any] = [.font: font]
    let attrStr = NSAttributedString(string: text, attributes: attrs)
    if let maxWidth = maxWidth {
        return attrStr.boundingRect(with: NSSize(width: maxWidth, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin]).height
    }
    return attrStr.size().height
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

/// Draw title banner at top of screenshot, returns y position below the subtitle
func drawTitleBanner(_ title: String, _ subtitle: String) -> CGFloat {
    let titleFont = NSFont.systemFont(ofSize: 76, weight: .bold)
    let titleAttrs: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: NSColor.white]
    let titleSize = (title as NSString).size(withAttributes: titleAttrs)
    let titleY = screenHeight - 160
    (title as NSString).draw(at: NSPoint(x: (screenWidth - titleSize.width) / 2, y: titleY - titleSize.height), withAttributes: titleAttrs)

    let subFont = NSFont.systemFont(ofSize: 40, weight: .medium)
    let subColor = NSColor(calibratedRed: 0.6, green: 0.6, blue: 0.8, alpha: 1.0)
    let subAttrs: [NSAttributedString.Key: Any] = [.font: subFont, .foregroundColor: subColor]
    let subSize = (subtitle as NSString).size(withAttributes: subAttrs)
    let subY = titleY - titleSize.height - 16
    (subtitle as NSString).draw(at: NSPoint(x: (screenWidth - subSize.width) / 2, y: subY - subSize.height), withAttributes: subAttrs)

    return subY - subSize.height - 50
}

/// Draw iOS-style tab bar at bottom
func drawTabBar(activeIndex: Int) {
    let barH: CGFloat = 110
    let barRect = NSRect(x: 0, y: 0, width: screenWidth, height: barH)
    // Semi-transparent background
    let barBg = NSColor(calibratedRed: 0.08, green: 0.06, blue: 0.14, alpha: 0.95)
    barBg.setFill()
    NSBezierPath(rect: barRect).fill()

    // Separator line
    NSColor(calibratedWhite: 0.2, alpha: 0.5).setFill()
    NSBezierPath(rect: NSRect(x: 0, y: barH, width: screenWidth, height: 1)).fill()

    let tabs = ["Dashboard", "Providers", "Sessions", "Alerts", "Settings"]
    let icons = ["◉", "◧", "▶", "⚠", "⚙"]
    let tabW = screenWidth / CGFloat(tabs.count)

    for (i, tab) in tabs.enumerated() {
        let isActive = i == activeIndex
        let color = isActive ? accentBlue : textTertiary
        let x = CGFloat(i) * tabW + tabW / 2

        // Icon
        let iconFont = NSFont.systemFont(ofSize: 28, weight: .regular)
        let iconAttrs: [NSAttributedString.Key: Any] = [.font: iconFont, .foregroundColor: color]
        let iconSize = (icons[i] as NSString).size(withAttributes: iconAttrs)
        (icons[i] as NSString).draw(at: NSPoint(x: x - iconSize.width / 2, y: 52), withAttributes: iconAttrs)

        // Label
        let labelFont = NSFont.systemFont(ofSize: 20, weight: isActive ? .semibold : .regular)
        let labelAttrs: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: color]
        let labelSize = (tab as NSString).size(withAttributes: labelAttrs)
        (tab as NSString).draw(at: NSPoint(x: x - labelSize.width / 2, y: 26), withAttributes: labelAttrs)
    }
}

// MARK: - Screenshot 1: Dashboard

func drawDashboard() -> NSBitmapImageRep {
    let rep = createCanvas()
    var y = drawTitleBanner("Your AI Dashboard", "Track usage across all providers")

    let margin: CGFloat = 70
    let w = screenWidth - margin * 2

    // Status bar
    drawCircle(at: NSPoint(x: margin + 14, y: y - 8), radius: 8, color: accentGreen)
    drawText("Server Online", at: NSPoint(x: margin + 32, y: y), size: 30, weight: .medium, color: textSecondary)
    drawText("Last sync: 2s ago", at: NSPoint(x: w + margin - 260, y: y), size: 26, weight: .regular, color: textTertiary)
    y -= 56

    // 2x3 Metric cards
    let cardW = (w - 36) / 2
    let cardH: CGFloat = 210
    let gap: CGFloat = 24
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
        let cardX = margin + CGFloat(col) * (cardW + 36)
        let cardTop = y - CGFloat(row) * (cardH + gap)
        let cardRect = NSRect(x: cardX, y: cardTop - cardH, width: cardW, height: cardH)

        drawRoundedRect(cardRect, radius: 22, fill: bgCard, stroke: metric.2.withAlphaComponent(0.15))

        // Color accent bar
        drawRoundedRect(NSRect(x: cardX + 20, y: cardRect.maxY - 20, width: 44, height: 5), radius: 3, fill: metric.2)

        // Label
        drawText(metric.0, at: NSPoint(x: cardX + 22, y: cardRect.maxY - 36), size: 28, weight: .medium, color: textSecondary)

        // Value
        drawText(metric.1, at: NSPoint(x: cardX + 22, y: cardRect.maxY - 80), size: 64, weight: .bold, color: .white)
    }

    y -= (cardH + gap) * 3 + 30

    // Provider Usage section
    drawText("Provider Usage", at: NSPoint(x: margin, y: y), size: 38, weight: .bold, color: .white)
    y -= 52

    let providers: [(String, Double, NSColor)] = [
        ("Claude", 0.85, accentOrange),
        ("Codex", 0.62, accentBlue),
        ("Gemini", 0.45, accentPurple),
        ("Ollama", 0.30, accentTeal),
        ("OpenRouter", 0.18, accentCyan),
    ]

    for p in providers {
        let rowH: CGFloat = 80
        let rowRect = NSRect(x: margin, y: y - rowH, width: w, height: rowH)
        drawRoundedRect(rowRect, radius: 14, fill: bgCard.withAlphaComponent(0.6))

        drawText(p.0, at: NSPoint(x: margin + 22, y: rowRect.maxY - 14), size: 30, weight: .semibold, color: .white)
        let pctText = "\(Int(p.1 * 100))%"
        drawText(pctText, at: NSPoint(x: margin + w - 90, y: rowRect.maxY - 14), size: 28, weight: .bold, color: p.2)

        drawBar(at: NSRect(x: margin + 22, y: rowRect.minY + 14, width: w - 44, height: 12), fraction: CGFloat(p.1), color: p.2)

        y -= rowH + 10
    }

    drawTabBar(activeIndex: 0)
    finishCanvas(rep)
    return rep
}

// MARK: - Screenshot 2: Providers

func drawProviders() -> NSBitmapImageRep {
    let rep = createCanvas()
    var y = drawTitleBanner("Provider Insights", "Monitor quotas and costs in real time")

    let margin: CGFloat = 70
    let w = screenWidth - margin * 2

    let providerData: [(String, String, String, String, String, Double, NSColor)] = [
        ("Claude", "Active", "8.2K", "$3.41", "5.2K", 0.68, accentOrange),
        ("Codex", "Active", "2.8K", "$0.92", "1.4K", 0.42, accentBlue),
        ("Gemini", "Active", "1.1K", "$0.38", "800", 0.25, accentPurple),
        ("OpenRouter", "Idle", "0.5K", "$0.05", "200", 0.10, accentCyan),
        ("Ollama", "Local", "340", "Free", "340", 0.00, accentTeal),
    ]

    for p in providerData {
        let cardH: CGFloat = 340
        let cardRect = NSRect(x: margin, y: y - cardH, width: w, height: cardH)
        drawRoundedRect(cardRect, radius: 22, fill: bgCard, stroke: p.6.withAlphaComponent(0.2))

        let cx = margin + 24  // content x start

        // Row 1: Icon + Name + Status badge
        let row1Top = cardRect.maxY - 22
        // Icon square
        let iconSize: CGFloat = 48
        let iconRect = NSRect(x: cx, y: row1Top - iconSize, width: iconSize, height: iconSize)
        drawRoundedRect(iconRect, radius: 12, fill: p.6.withAlphaComponent(0.15))
        let letterFont = NSFont.systemFont(ofSize: 28, weight: .bold)
        let letterAttrs: [NSAttributedString.Key: Any] = [.font: letterFont, .foregroundColor: p.6]
        let letter = String(p.0.prefix(1))
        let letterSize = (letter as NSString).size(withAttributes: letterAttrs)
        (letter as NSString).draw(at: NSPoint(x: iconRect.midX - letterSize.width / 2, y: iconRect.midY - letterSize.height / 2), withAttributes: letterAttrs)

        // Name
        drawText(p.0, at: NSPoint(x: cx + iconSize + 14, y: row1Top - 6), size: 34, weight: .bold, color: .white)
        // Status text below name
        drawText(p.1, at: NSPoint(x: cx + iconSize + 14, y: row1Top - 38), size: 24, weight: .regular, color: textSecondary)

        // Status badge (right side)
        let badgeColor = p.1 == "Active" ? accentGreen : textTertiary
        let badgeText = p.1 == "Active" ? "OK" : p.1
        let badgeFont = NSFont.systemFont(ofSize: 20, weight: .bold)
        let badgeAttrs: [NSAttributedString.Key: Any] = [.font: badgeFont, .foregroundColor: badgeColor]
        let badgeTextSize = (badgeText as NSString).size(withAttributes: badgeAttrs)
        let badgeW = badgeTextSize.width + 28
        let badgeRect = NSRect(x: cardRect.maxX - 24 - badgeW, y: row1Top - 38, width: badgeW, height: 32)
        drawRoundedRect(badgeRect, radius: 16, fill: badgeColor.withAlphaComponent(0.15))
        (badgeText as NSString).draw(at: NSPoint(x: badgeRect.midX - badgeTextSize.width / 2, y: badgeRect.minY + 6), withAttributes: badgeAttrs)

        // Row 2: Stats - Today / Cost / This Week
        let row2Top = row1Top - 80
        let statW = (w - 48) / 3

        // Stat 1: Today
        drawText("Today", at: NSPoint(x: cx, y: row2Top), size: 22, weight: .regular, color: textTertiary)
        drawText(p.2, at: NSPoint(x: cx, y: row2Top - 32), size: 44, weight: .bold, color: .white)

        // Stat 2: Cost
        drawText("Cost", at: NSPoint(x: cx + statW, y: row2Top), size: 22, weight: .regular, color: textTertiary)
        drawText(p.3, at: NSPoint(x: cx + statW, y: row2Top - 32), size: 44, weight: .bold, color: accentGreen)

        // Stat 3: This Week
        drawText("This Week", at: NSPoint(x: cx + statW * 2, y: row2Top), size: 22, weight: .regular, color: textTertiary)
        drawText(p.4, at: NSPoint(x: cx + statW * 2, y: row2Top - 32), size: 44, weight: .bold, color: .white)

        // Row 3: Quota bar
        if p.5 > 0 {
            let barY = cardRect.minY + 44
            drawText("Quota", at: NSPoint(x: cx, y: barY + 26), size: 22, weight: .medium, color: textSecondary)
            drawBar(at: NSRect(x: cx, y: barY, width: w - 48, height: 12), fraction: CGFloat(p.5), color: p.6)
        }

        y -= cardH + 18
    }

    drawTabBar(activeIndex: 1)
    finishCanvas(rep)
    return rep
}

// MARK: - Screenshot 3: Alerts

func drawAlerts() -> NSBitmapImageRep {
    let rep = createCanvas()
    var y = drawTitleBanner("Stay Alert", "Real-time notifications at a glance")

    let margin: CGFloat = 70
    let w = screenWidth - margin * 2

    // Summary badges row
    let badgeH: CGFloat = 44
    let badges: [(String, NSColor)] = [("1 critical", accentRed), ("1 warning", accentOrange), ("1 info", accentBlue)]
    var badgeX = margin
    for b in badges {
        let font = NSFont.systemFont(ofSize: 26, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: b.1]
        let textW = (b.0 as NSString).size(withAttributes: attrs).width
        let bw = textW + 32
        let bRect = NSRect(x: badgeX, y: y - badgeH, width: bw, height: badgeH)
        drawRoundedRect(bRect, radius: 22, fill: b.1.withAlphaComponent(0.12))
        (b.0 as NSString).draw(at: NSPoint(x: badgeX + 16, y: bRect.minY + 10), withAttributes: attrs)
        badgeX += bw + 14
    }
    y -= badgeH + 24

    // Segmented control
    let segH: CGFloat = 52
    let segRect = NSRect(x: margin, y: y - segH, width: w, height: segH)
    drawRoundedRect(segRect, radius: 12, fill: bgCard)
    let selW = w / 3
    drawRoundedRect(NSRect(x: margin + 4, y: segRect.minY + 4, width: selW - 8, height: segH - 8),
                    radius: 10, fill: accentBlue.withAlphaComponent(0.3))

    let segLabels = [("Open", true), ("Resolved", false), ("All", false)]
    for (i, seg) in segLabels.enumerated() {
        let font = NSFont.systemFont(ofSize: 26, weight: seg.1 ? .semibold : .medium)
        let color = seg.1 ? NSColor.white : textSecondary
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (seg.0 as NSString).size(withAttributes: attrs)
        let cx = margin + selW * CGFloat(i) + selW / 2
        (seg.0 as NSString).draw(at: NSPoint(x: cx - size.width / 2, y: segRect.minY + (segH - size.height) / 2), withAttributes: attrs)
    }
    y -= segH + 24

    // Alert cards - with proper spacing
    let alerts: [(String, String, String, String, String, NSColor)] = [
        ("Critical", "Quota Low: Claude",
         "Claude usage has exceeded 90% of daily quota. Consider reducing usage or upgrading your plan.",
         "Claude", "2m ago", accentRed),
        ("Warning", "Usage Spike Detected",
         "Codex usage spiked 3x in the last hour. Check for runaway sessions.",
         "Codex", "15m ago", accentOrange),
        ("Info", "Helper Reconnected",
         "macbook-pro helper reconnected after brief disconnect. All services restored.",
         "macbook-pro", "1h ago", accentBlue),
    ]

    for a in alerts {
        // Calculate card height based on content
        let contentW = w - 56
        let descH = textHeight(a.2, size: 26, weight: .regular, maxWidth: contentW)
        let cardH: CGFloat = 28 + 40 + 16 + descH + 20 + 36 + 20 + 48 + 28  // padding + title + gap + desc + gap + chip + gap + buttons + padding
        let cardRect = NSRect(x: margin, y: y - cardH, width: w, height: cardH)
        drawRoundedRect(cardRect, radius: 22, fill: a.5.withAlphaComponent(0.05), stroke: a.5.withAlphaComponent(0.2))

        var cy = cardRect.maxY - 28  // top padding

        // Severity dot + Title + Time
        drawCircle(at: NSPoint(x: margin + 32, y: cy - 18), radius: 8, color: a.5)
        drawText(a.1, at: NSPoint(x: margin + 52, y: cy), size: 30, weight: .bold, color: .white)

        // Time (right-aligned)
        let timeFont = NSFont.systemFont(ofSize: 24, weight: .regular)
        let timeAttrs: [NSAttributedString.Key: Any] = [.font: timeFont, .foregroundColor: textTertiary]
        let timeSize = (a.4 as NSString).size(withAttributes: timeAttrs)
        (a.4 as NSString).draw(at: NSPoint(x: cardRect.maxX - 24 - timeSize.width, y: cy - timeSize.height), withAttributes: timeAttrs)

        cy -= 40 + 16  // title height + gap

        // Description
        drawText(a.2, at: NSPoint(x: margin + 28, y: cy), size: 26, weight: .regular, color: textSecondary, maxWidth: contentW)
        cy -= descH + 20

        // Source chip
        let chipFont = NSFont.systemFont(ofSize: 22, weight: .regular)
        let chipAttrs: [NSAttributedString.Key: Any] = [.font: chipFont, .foregroundColor: textSecondary]
        let chipTextSize = (a.3 as NSString).size(withAttributes: chipAttrs)
        let chipW = chipTextSize.width + 24
        let chipRect = NSRect(x: margin + 28, y: cy - 36, width: chipW, height: 36)
        drawRoundedRect(chipRect, radius: 18, fill: NSColor(calibratedWhite: 0.2, alpha: 0.3))
        (a.3 as NSString).draw(at: NSPoint(x: chipRect.minX + 12, y: chipRect.minY + 8), withAttributes: chipAttrs)
        cy -= 36 + 20

        // Action buttons
        let btnH: CGFloat = 44
        let btnData: [(String, NSColor)] = [("Ack", accentBlue), ("Resolve", accentGreen), ("Snooze", accentOrange)]
        var btnX = margin + 28
        for btn in btnData {
            let btnFont = NSFont.systemFont(ofSize: 24, weight: .semibold)
            let btnAttrs: [NSAttributedString.Key: Any] = [.font: btnFont, .foregroundColor: btn.1]
            let btnTextSize = (btn.0 as NSString).size(withAttributes: btnAttrs)
            let btnW = btnTextSize.width + 36
            let btnRect = NSRect(x: btnX, y: cy - btnH, width: btnW, height: btnH)
            drawRoundedRect(btnRect, radius: btnH / 2, fill: btn.1.withAlphaComponent(0.12))
            (btn.0 as NSString).draw(at: NSPoint(x: btnRect.midX - btnTextSize.width / 2, y: btnRect.minY + (btnH - btnTextSize.height) / 2), withAttributes: btnAttrs)
            btnX += btnW + 14
        }

        y -= cardH + 18
    }

    drawTabBar(activeIndex: 3)
    finishCanvas(rep)
    return rep
}

// MARK: - Screenshot 4: Sessions

func drawSessions() -> NSBitmapImageRep {
    let rep = createCanvas()
    var y = drawTitleBanner("Active Sessions", "See what's running right now")

    let margin: CGFloat = 70
    let w = screenWidth - margin * 2

    // Summary row
    let summaryItems: [(String, String, NSColor)] = [
        ("Active", "5", accentGreen),
        ("Today", "23", accentBlue),
        ("Avg Duration", "12m", accentPurple),
    ]
    let sumW = (w - 28) / 3
    for (i, s) in summaryItems.enumerated() {
        let sx = margin + CGFloat(i) * (sumW + 14)
        let sRect = NSRect(x: sx, y: y - 90, width: sumW, height: 90)
        drawRoundedRect(sRect, radius: 16, fill: bgCard)
        drawText(s.0, at: NSPoint(x: sx + 14, y: sRect.maxY - 14), size: 22, weight: .regular, color: textTertiary)
        drawText(s.1, at: NSPoint(x: sx + 14, y: sRect.maxY - 42), size: 40, weight: .bold, color: s.2)
    }
    y -= 112

    // Session cards
    let sessions: [(String, String, String, String, Bool, NSColor)] = [
        ("Claude Code", "cli-pulse refactor", "12m 34s", "4.2K tokens", true, accentOrange),
        ("Codex CLI", "api-server debug", "8m 12s", "1.8K tokens", true, accentBlue),
        ("Gemini Pro", "docs generation", "3m 45s", "920 tokens", true, accentPurple),
        ("Claude Code", "test suite", "22m 10s", "8.1K tokens", true, accentOrange),
        ("Ollama", "local embeddings", "1m 20s", "340 tokens", true, accentTeal),
        ("OpenRouter", "code review", "Ended 5m ago", "2.1K tokens", false, accentCyan),
        ("Claude Code", "migration script", "Ended 18m ago", "5.4K tokens", false, accentOrange),
    ]

    for s in sessions {
        let cardH: CGFloat = 170
        let cardRect = NSRect(x: margin, y: y - cardH, width: w, height: cardH)
        drawRoundedRect(cardRect, radius: 20, fill: bgCard, stroke: s.5.withAlphaComponent(0.15))

        let cx = margin + 24

        // Provider + status dot
        let statusColor = s.4 ? accentGreen : textTertiary
        drawCircle(at: NSPoint(x: cx + 6, y: cardRect.maxY - 30), radius: 6, color: statusColor)
        drawText(s.0, at: NSPoint(x: cx + 20, y: cardRect.maxY - 20), size: 30, weight: .bold, color: .white)

        // Project name
        drawText(s.1, at: NSPoint(x: cx + 20, y: cardRect.maxY - 52), size: 24, weight: .regular, color: s.5)

        // Duration (right side)
        let durFont = NSFont.systemFont(ofSize: 24, weight: .medium)
        let durColor = s.4 ? accentGreen : textTertiary
        let durAttrs: [NSAttributedString.Key: Any] = [.font: durFont, .foregroundColor: durColor]
        let durSize = (s.2 as NSString).size(withAttributes: durAttrs)
        (s.2 as NSString).draw(at: NSPoint(x: cardRect.maxX - 24 - durSize.width, y: cardRect.maxY - 30 - durSize.height), withAttributes: durAttrs)

        // Bottom stats row
        let statsY = cardRect.minY + 28

        // Token count
        drawText(s.3, at: NSPoint(x: cx, y: statsY + 32), size: 24, weight: .medium, color: textSecondary)

        // Activity mini bar
        if s.4 {
            let barW: CGFloat = 120
            let barX = cardRect.maxX - 24 - barW
            // Animated-looking activity bars
            for j in 0..<8 {
                let bh: CGFloat = CGFloat([14, 22, 18, 28, 12, 24, 16, 20][j])
                let bx = barX + CGFloat(j) * 16
                drawRoundedRect(NSRect(x: bx, y: statsY + 6, width: 10, height: bh), radius: 3, fill: s.5.withAlphaComponent(0.5))
            }
        }

        y -= cardH + 12
    }

    drawTabBar(activeIndex: 2)
    finishCanvas(rep)
    return rep
}

// MARK: - Screenshot 5: Settings

func drawSettings() -> NSBitmapImageRep {
    let rep = createCanvas()
    var y = drawTitleBanner("Settings", "Configure your monitoring setup")

    let margin: CGFloat = 70
    let w = screenWidth - margin * 2

    // Profile card
    let profileH: CGFloat = 140
    let profileRect = NSRect(x: margin, y: y - profileH, width: w, height: profileH)
    drawRoundedRect(profileRect, radius: 22, fill: bgCard)

    // Avatar circle
    let avatarR: CGFloat = 36
    let avatarCenter = NSPoint(x: margin + 40 + avatarR, y: profileRect.midY)
    drawCircle(at: avatarCenter, radius: avatarR, color: accentBlue.withAlphaComponent(0.3))
    let avatarFont = NSFont.systemFont(ofSize: 32, weight: .bold)
    let avatarAttrs: [NSAttributedString.Key: Any] = [.font: avatarFont, .foregroundColor: accentBlue]
    let av = "J"
    let avSize = (av as NSString).size(withAttributes: avatarAttrs)
    (av as NSString).draw(at: NSPoint(x: avatarCenter.x - avSize.width / 2, y: avatarCenter.y - avSize.height / 2), withAttributes: avatarAttrs)

    drawText("jason@cli-pulse.dev", at: NSPoint(x: margin + 40 + avatarR * 2 + 16, y: profileRect.maxY - 40), size: 28, weight: .semibold, color: .white)
    drawText("Pro Plan", at: NSPoint(x: margin + 40 + avatarR * 2 + 16, y: profileRect.maxY - 72), size: 24, weight: .regular, color: accentGreen)

    // Pro badge
    let proBadgeRect = NSRect(x: profileRect.maxX - 110, y: profileRect.midY - 16, width: 80, height: 32)
    drawRoundedRect(proBadgeRect, radius: 16, fill: accentGreen.withAlphaComponent(0.15))
    let proFont = NSFont.systemFont(ofSize: 18, weight: .bold)
    let proAttrs: [NSAttributedString.Key: Any] = [.font: proFont, .foregroundColor: accentGreen]
    let proSize = ("PRO" as NSString).size(withAttributes: proAttrs)
    ("PRO" as NSString).draw(at: NSPoint(x: proBadgeRect.midX - proSize.width / 2, y: proBadgeRect.minY + 7), withAttributes: proAttrs)

    y -= profileH + 28

    // Settings sections
    let sections: [(String, [(String, String, NSColor)])] = [
        ("Monitoring", [
            ("Sync Interval", "30 seconds", accentBlue),
            ("Background Refresh", "Enabled", accentGreen),
            ("Provider Auto-detect", "On", accentGreen),
        ]),
        ("Notifications", [
            ("Push Alerts", "Critical + Warning", accentOrange),
            ("Daily Summary", "9:00 AM", accentBlue),
            ("Quota Warnings", "At 80%", accentPurple),
        ]),
        ("Data & Privacy", [
            ("Data Retention", "90 days", accentBlue),
            ("Export Data", "CSV / JSON", textSecondary),
            ("Delete Account", "Tap to delete", accentRed),
        ]),
        ("About", [
            ("Version", version, textSecondary),
            ("Terms of Service", "", textSecondary),
            ("Privacy Policy", "", textSecondary),
        ]),
    ]

    for section in sections {
        drawText(section.0, at: NSPoint(x: margin + 8, y: y), size: 26, weight: .bold, color: textSecondary)
        y -= 38

        let groupH = CGFloat(section.1.count) * 64
        let groupRect = NSRect(x: margin, y: y - groupH, width: w, height: groupH)
        drawRoundedRect(groupRect, radius: 18, fill: bgCard)

        for (i, item) in section.1.enumerated() {
            let rowY = groupRect.maxY - CGFloat(i) * 64

            drawText(item.0, at: NSPoint(x: margin + 22, y: rowY - 12), size: 28, weight: .regular, color: .white)

            if !item.1.isEmpty {
                let valFont = NSFont.systemFont(ofSize: 26, weight: .regular)
                let valAttrs: [NSAttributedString.Key: Any] = [.font: valFont, .foregroundColor: item.2]
                let valSize = (item.1 as NSString).size(withAttributes: valAttrs)
                (item.1 as NSString).draw(at: NSPoint(x: groupRect.maxX - 22 - valSize.width, y: rowY - 12 - valSize.height), withAttributes: valAttrs)
            }

            // Chevron
            let chevFont = NSFont.systemFont(ofSize: 22, weight: .regular)
            let chevAttrs: [NSAttributedString.Key: Any] = [.font: chevFont, .foregroundColor: textTertiary]
            ("›" as NSString).draw(at: NSPoint(x: groupRect.maxX - 14, y: rowY - 46), withAttributes: chevAttrs)

            // Separator
            if i < section.1.count - 1 {
                let sepY = rowY - 64
                NSColor(calibratedWhite: 0.2, alpha: 0.3).setFill()
                NSBezierPath(rect: NSRect(x: margin + 22, y: sepY, width: w - 44, height: 1)).fill()
            }
        }

        y -= groupH + 24
    }

    drawTabBar(activeIndex: 4)
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

// Read version from project
let projectDir = baseDir + "/.."
func readProjectVersion() -> String {
    let plistPath = projectDir + "/CLI Pulse Bar/Info.plist"
    if let dict = NSDictionary(contentsOfFile: plistPath),
       let ver = dict["CFBundleShortVersionString"] as? String,
       let build = dict["CFBundleVersion"] as? String {
        return "\(ver) (\(build))"
    }
    // Fallback: try pbxproj
    if let pbx = try? String(contentsOfFile: projectDir + "/CLI Pulse Bar.xcodeproj/project.pbxproj", encoding: .utf8) {
        var ver = "1.0.0", build = "1"
        if let range = pbx.range(of: "MARKETING_VERSION = ") {
            let start = range.upperBound
            if let end = pbx[start...].firstIndex(of: ";") {
                ver = String(pbx[start..<end]).trimmingCharacters(in: .whitespaces)
            }
        }
        if let range = pbx.range(of: "CURRENT_PROJECT_VERSION = ") {
            let start = range.upperBound
            if let end = pbx[start...].firstIndex(of: ";") {
                build = String(pbx[start..<end]).trimmingCharacters(in: .whitespaces)
            }
        }
        return "\(ver) (\(build))"
    }
    return "1.1.0 (14)"
}
let version = readProjectVersion()
let outDir = baseDir + "/../build/ios-screenshots"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let desktopDir = NSHomeDirectory() + "/Desktop/cli-pulse-screenshots"
try? FileManager.default.createDirectory(atPath: desktopDir, withIntermediateDirectories: true)

print("Generating iOS screenshots...")

let screenshots: [(String, NSBitmapImageRep)] = [
    ("01_dashboard_6.7", drawDashboard()),
    ("02_providers_6.7", drawProviders()),
    ("03_sessions_6.7", drawSessions()),
    ("04_alerts_6.7", drawAlerts()),
    ("05_settings_6.7", drawSettings()),
]

for (name, rep) in screenshots {
    savePNG(rep, to: outDir + "/\(name).png")
    savePNG(rep, to: desktopDir + "/\(name).png")
}

print("Done! Screenshots also copied to ~/Desktop/cli-pulse-screenshots/")
