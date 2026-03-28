#!/usr/bin/env swift
// Generates CLI Pulse Bar app icons at all required macOS sizes
// Usage: swift generate_icon.swift

import Cocoa

func generateIcon(size: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let scale = CGFloat(size) / 512.0

    // Background: rounded rect with gradient
    let bgPath = NSBezierPath(roundedRect: rect.insetBy(dx: CGFloat(size) * 0.04, dy: CGFloat(size) * 0.04),
                               xRadius: CGFloat(size) * 0.22,
                               yRadius: CGFloat(size) * 0.22)

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.15, green: 0.12, blue: 0.28, alpha: 1.0),
        NSColor(calibratedRed: 0.08, green: 0.06, blue: 0.18, alpha: 1.0),
    ])!
    gradient.draw(in: bgPath, angle: -90)

    // Subtle inner glow
    let innerGlow = NSBezierPath(roundedRect: rect.insetBy(dx: CGFloat(size) * 0.05, dy: CGFloat(size) * 0.05),
                                  xRadius: CGFloat(size) * 0.21,
                                  yRadius: CGFloat(size) * 0.21)
    NSColor(calibratedRed: 0.36, green: 0.51, blue: 1.0, alpha: 0.08).setStroke()
    innerGlow.lineWidth = 2 * scale
    innerGlow.stroke()

    // Pulse waveform (ECG-like)
    let waveColor = NSColor(calibratedRed: 0.36, green: 0.51, blue: 1.0, alpha: 1.0)
    let wavePath = NSBezierPath()
    let centerY = CGFloat(size) * 0.50
    let startX = CGFloat(size) * 0.12
    let endX = CGFloat(size) * 0.88

    wavePath.move(to: NSPoint(x: startX, y: centerY))

    // Flat lead-in
    wavePath.line(to: NSPoint(x: CGFloat(size) * 0.28, y: centerY))

    // P wave (small bump)
    wavePath.curve(to: NSPoint(x: CGFloat(size) * 0.34, y: centerY),
                   controlPoint1: NSPoint(x: CGFloat(size) * 0.30, y: centerY - CGFloat(size) * 0.04),
                   controlPoint2: NSPoint(x: CGFloat(size) * 0.32, y: centerY - CGFloat(size) * 0.04))

    // Lead to QRS
    wavePath.line(to: NSPoint(x: CGFloat(size) * 0.38, y: centerY))

    // Q dip
    wavePath.line(to: NSPoint(x: CGFloat(size) * 0.40, y: centerY + CGFloat(size) * 0.04))

    // R spike (big up)
    wavePath.line(to: NSPoint(x: CGFloat(size) * 0.45, y: centerY - CGFloat(size) * 0.22))

    // S dip (down)
    wavePath.line(to: NSPoint(x: CGFloat(size) * 0.50, y: centerY + CGFloat(size) * 0.10))

    // Return to baseline
    wavePath.line(to: NSPoint(x: CGFloat(size) * 0.54, y: centerY))

    // T wave
    wavePath.curve(to: NSPoint(x: CGFloat(size) * 0.64, y: centerY),
                   controlPoint1: NSPoint(x: CGFloat(size) * 0.57, y: centerY - CGFloat(size) * 0.06),
                   controlPoint2: NSPoint(x: CGFloat(size) * 0.61, y: centerY - CGFloat(size) * 0.06))

    // Flat tail
    wavePath.line(to: NSPoint(x: endX, y: centerY))

    // Glow effect (draw wider stroke first)
    NSColor(calibratedRed: 0.36, green: 0.51, blue: 1.0, alpha: 0.3).setStroke()
    wavePath.lineWidth = 8 * scale
    wavePath.lineCapStyle = .round
    wavePath.lineJoinStyle = .round
    wavePath.stroke()

    // Main waveform stroke
    waveColor.setStroke()
    wavePath.lineWidth = 3.5 * scale
    wavePath.stroke()

    // Bright peak dot
    let dotSize = 6.0 * scale
    let peakPoint = NSPoint(x: CGFloat(size) * 0.45 - dotSize / 2,
                            y: centerY - CGFloat(size) * 0.22 - dotSize / 2)
    let dotPath = NSBezierPath(ovalIn: NSRect(x: peakPoint.x, y: peakPoint.y, width: dotSize, height: dotSize))
    NSColor.white.setFill()
    dotPath.fill()

    // "CLI" text at bottom
    let fontSize = 42.0 * scale
    let font = NSFont.systemFont(ofSize: fontSize, weight: .heavy)
    let textAttrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white.withAlphaComponent(0.9),
        .kern: 4.0 * scale,
    ]
    let text = "CLI" as NSString
    let textSize = text.size(withAttributes: textAttrs)
    let textOrigin = NSPoint(x: (CGFloat(size) - textSize.width) / 2,
                             y: CGFloat(size) * 0.10)
    text.draw(at: textOrigin, withAttributes: textAttrs)

    // "PULSE" subtitle
    let subFontSize = 18.0 * scale
    let subFont = NSFont.systemFont(ofSize: subFontSize, weight: .medium)
    let subAttrs: [NSAttributedString.Key: Any] = [
        .font: subFont,
        .foregroundColor: NSColor(calibratedRed: 0.36, green: 0.51, blue: 1.0, alpha: 0.8),
        .kern: 6.0 * scale,
    ]
    let subText = "PULSE" as NSString
    let subSize = subText.size(withAttributes: subAttrs)
    let subOrigin = NSPoint(x: (CGFloat(size) - subSize.width) / 2,
                            y: CGFloat(size) * 0.05)
    subText.draw(at: subOrigin, withAttributes: subAttrs)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func savePNG(_ rep: NSBitmapImageRep, to path: String) {
    guard let png = rep.representation(using: .png, properties: [:]) else {
        print("Failed to generate PNG for \(path)")
        return
    }
    do {
        try png.write(to: URL(fileURLWithPath: path))
        print("  Created: \(path) (\(rep.pixelsWide)x\(rep.pixelsHigh))")
    } catch {
        print("  Error writing \(path): \(error)")
    }
}

// macOS icon sizes: 16, 32, 64, 128, 256, 512, 1024
let sizes: [(name: String, size: Int)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024),
]

let scriptDir = CommandLine.arguments[0].components(separatedBy: "/").dropLast().joined(separator: "/")
let baseDir: String
if scriptDir.isEmpty {
    baseDir = "."
} else {
    baseDir = scriptDir
}
let iconDir = baseDir + "/../CLI Pulse Bar/Assets.xcassets/AppIcon.appiconset"

print("Generating CLI Pulse Bar icons...")
for entry in sizes {
    let image = generateIcon(size: entry.size)
    let path = iconDir + "/\(entry.name).png"
    savePNG(image, to: path)
}

// Update Contents.json
let contentsJSON = """
{
  "images" : [
    { "filename" : "icon_16x16.png", "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_16x16@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32x32.png", "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_32x32@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128x128.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_128x128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256x256.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_256x256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512x512.png", "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_512x512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
"""
try! contentsJSON.write(toFile: iconDir + "/Contents.json", atomically: true, encoding: .utf8)
print("Updated Contents.json")
print("Done!")
