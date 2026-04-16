#if canImport(PDFKit) && !os(watchOS)
import Foundation
import PDFKit
#if canImport(AppKit)
import AppKit
private typealias PlatformColor = NSColor
private typealias PlatformFont = NSFont
#elseif canImport(UIKit)
import UIKit
private typealias PlatformColor = UIColor
private typealias PlatformFont = UIFont
#endif

/// Generates a monthly usage/cost report as a PDF document.
public enum PDFReportGenerator {

    // MARK: - Public API

    /// Generate a monthly PDF report and write to a temporary file.
    /// Returns the file URL on success, nil on failure.
    public static func generateReport(
        dashboard: DashboardSummary?,
        providers: [ProviderUsage],
        sessions: [SessionRecord],
        dailyUsage: [DailyUsage],
        costForecast: CostForecast?,
        generatedDate: Date = Date()
    ) -> URL? {
        let pageWidth: CGFloat = 612  // US Letter
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 50
        let contentWidth = pageWidth - margin * 2

        let pdfData = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return nil
        }

        var y: CGFloat = pageHeight - margin

        func newPage() {
            if y < pageHeight - margin { // Don't end a page we haven't drawn on
                context.endPage()
            }
            context.beginPage(mediaBox: &mediaBox)
            y = pageHeight - margin
        }

        func checkSpace(_ needed: CGFloat) {
            if y - needed < margin {
                newPage()
            }
        }

        // ── Page 1: Header + Summary ──
        context.beginPage(mediaBox: &mediaBox)

        // Title
        y = drawText("CLI Pulse Monthly Report", at: CGPoint(x: margin, y: y), fontSize: 22, bold: true, context: context)
        y -= 4

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        y = drawText("Generated: \(dateFormatter.string(from: generatedDate))", at: CGPoint(x: margin, y: y), fontSize: 10, color: .gray, context: context)
        y -= 20

        // Divider
        y = drawDivider(at: y, x: margin, width: contentWidth, context: context)
        y -= 12

        // Summary section
        if let d = dashboard {
            y = drawText("Summary", at: CGPoint(x: margin, y: y), fontSize: 16, bold: true, context: context)
            y -= 8

            let summaryItems: [(String, String)] = [
                ("Today's Usage", formatTokens(d.total_usage_today)),
                ("Today's Estimated Cost", String(format: "$%.2f", d.total_estimated_cost_today)),
                ("Active Sessions", "\(d.active_sessions)"),
                ("Online Devices", "\(d.online_devices)"),
                ("Unresolved Alerts", "\(d.unresolved_alerts)"),
            ]

            for (label, value) in summaryItems {
                y = drawKeyValue(label, value: value, at: y, x: margin, width: contentWidth, fontSize: 11, context: context)
            }
            y -= 12
        }

        // Cost Forecast section
        if let forecast = costForecast, forecast.isReliable {
            y = drawDivider(at: y, x: margin, width: contentWidth, context: context)
            y -= 8
            y = drawText("Cost Forecast", at: CGPoint(x: margin, y: y), fontSize: 16, bold: true, context: context)
            y -= 8

            y = drawKeyValue("Month-End Estimate", value: String(format: "$%.2f", forecast.predictedMonthTotal), at: y, x: margin, width: contentWidth, fontSize: 11, context: context)
            y = drawKeyValue("Spent So Far", value: String(format: "$%.2f", forecast.actualToDate), at: y, x: margin, width: contentWidth, fontSize: 11, context: context)
            y = drawKeyValue("Confidence Range", value: String(format: "$%.2f — $%.2f", forecast.lowerBound, forecast.upperBound), at: y, x: margin, width: contentWidth, fontSize: 11, context: context)
            y = drawKeyValue("Progress", value: "\(forecast.currentDayOfMonth)/\(forecast.daysInMonth) days", at: y, x: margin, width: contentWidth, fontSize: 11, context: context)
            y -= 12
        }

        // Provider breakdown
        y = drawDivider(at: y, x: margin, width: contentWidth, context: context)
        y -= 8
        y = drawText("Provider Breakdown", at: CGPoint(x: margin, y: y), fontSize: 16, bold: true, context: context)
        y -= 8

        // Table header
        let colWidths: [CGFloat] = [contentWidth * 0.3, contentWidth * 0.2, contentWidth * 0.2, contentWidth * 0.15, contentWidth * 0.15]
        let headers = ["Provider", "Week Usage", "Est. Cost", "Remaining", "Quota"]
        y = drawTableRow(headers, at: y, x: margin, colWidths: colWidths, fontSize: 9, bold: true, context: context)

        y = drawDivider(at: y, x: margin, width: contentWidth, context: context, thin: true)

        let sortedProviders = providers.sorted { $0.estimated_cost_week > $1.estimated_cost_week }
        for p in sortedProviders {
            checkSpace(16)
            let row = [
                p.provider,
                formatTokens(p.week_usage),
                String(format: "$%.2f", p.estimated_cost_week),
                p.remaining.map { formatTokens($0) } ?? "N/A",
                p.quota.map { formatTokens($0) } ?? "N/A",
            ]
            y = drawTableRow(row, at: y, x: margin, colWidths: colWidths, fontSize: 9, context: context)
        }
        y -= 12

        // Top sessions by cost
        checkSpace(40)
        y = drawDivider(at: y, x: margin, width: contentWidth, context: context)
        y -= 8
        y = drawText("Top Sessions by Cost", at: CGPoint(x: margin, y: y), fontSize: 16, bold: true, context: context)
        y -= 8

        let sessionColWidths: [CGFloat] = [contentWidth * 0.25, contentWidth * 0.25, contentWidth * 0.15, contentWidth * 0.2, contentWidth * 0.15]
        let sessionHeaders = ["Provider", "Project", "Cost", "Usage", "Status"]
        y = drawTableRow(sessionHeaders, at: y, x: margin, colWidths: sessionColWidths, fontSize: 9, bold: true, context: context)
        y = drawDivider(at: y, x: margin, width: contentWidth, context: context, thin: true)

        let topSessions = sessions.sorted { $0.estimated_cost > $1.estimated_cost }.prefix(15)
        for s in topSessions {
            checkSpace(16)
            let row = [
                s.provider,
                s.project,
                String(format: "$%.4f", s.estimated_cost),
                formatTokens(s.total_usage),
                s.status,
            ]
            y = drawTableRow(row, at: y, x: margin, colWidths: sessionColWidths, fontSize: 9, context: context)
        }
        y -= 12

        // Daily cost trend (text-based)
        if !dailyUsage.isEmpty {
            checkSpace(40)
            y = drawDivider(at: y, x: margin, width: contentWidth, context: context)
            y -= 8
            y = drawText("Daily Cost Trend (Last 30 Days)", at: CGPoint(x: margin, y: y), fontSize: 16, bold: true, context: context)
            y -= 8

            let costByDate = dailyUsage.reduce(into: [String: Double]()) { result, entry in
                result[entry.date, default: 0] += entry.cost
            }
            let sortedDates = costByDate.keys.sorted().suffix(30)
            let maxCost = costByDate.values.max() ?? 1.0

            for date in sortedDates {
                checkSpace(14)
                let cost = costByDate[date] ?? 0
                let barWidth = maxCost > 0 ? CGFloat(cost / maxCost) * (contentWidth - 130) : 0

                // Date label
                let _ = drawText(String(date.suffix(5)), at: CGPoint(x: margin, y: y), fontSize: 8, color: .gray, context: context)

                // Bar
                context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 1.0, alpha: 0.7))
                context.fill(CGRect(x: margin + 45, y: y - 2, width: barWidth, height: 8))

                // Cost label
                let _ = drawText(String(format: "$%.2f", cost), at: CGPoint(x: margin + 50 + (contentWidth - 130), y: y), fontSize: 8, context: context)
                y -= 12
            }
        }

        // Footer
        checkSpace(30)
        y -= 10
        y = drawDivider(at: y, x: margin, width: contentWidth, context: context)
        y -= 4
        let _ = drawText("CLI Pulse v1.9 • \(dateFormatter.string(from: generatedDate))", at: CGPoint(x: margin, y: y), fontSize: 8, color: .gray, context: context)

        context.endPage()
        context.closePDF()

        // Write to temp file
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cli-pulse-report-\(dateString(generatedDate)).pdf")
        do {
            try (pdfData as Data).write(to: url)
            return url
        } catch {
            return nil
        }
    }

    // MARK: - Drawing Helpers

    private static func drawText(
        _ text: String,
        at point: CGPoint,
        fontSize: CGFloat,
        bold: Bool = false,
        color: PlatformColor = PlatformColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1),
        context: CGContext
    ) -> CGFloat {
        let font: PlatformFont
        if bold {
            font = PlatformFont.boldSystemFont(ofSize: fontSize)
        } else {
            font = PlatformFont.systemFont(ofSize: fontSize)
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
        ]
        let attrString = NSAttributedString(string: text, attributes: attrs)
        let size = attrString.size()
        let drawPoint = CGPoint(x: point.x, y: point.y - size.height)

        #if canImport(AppKit)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        attrString.draw(at: drawPoint)
        NSGraphicsContext.restoreGraphicsState()
        #elseif canImport(UIKit)
        UIGraphicsPushContext(context)
        // UIKit draws top-down; we need to flip for our coordinate system
        context.saveGState()
        context.translateBy(x: 0, y: point.y)
        context.scaleBy(x: 1, y: -1)
        attrString.draw(at: CGPoint(x: point.x, y: 0))
        context.restoreGState()
        UIGraphicsPopContext()
        #endif

        return point.y - size.height - 2
    }

    private static func drawKeyValue(
        _ key: String,
        value: String,
        at y: CGFloat,
        x: CGFloat,
        width: CGFloat,
        fontSize: CGFloat,
        context: CGContext
    ) -> CGFloat {
        let _ = drawText(key, at: CGPoint(x: x, y: y), fontSize: fontSize, color: .gray, context: context)
        let _ = drawText(value, at: CGPoint(x: x + width * 0.5, y: y), fontSize: fontSize, bold: true, context: context)
        return y - fontSize - 6
    }

    private static func drawTableRow(
        _ values: [String],
        at y: CGFloat,
        x: CGFloat,
        colWidths: [CGFloat],
        fontSize: CGFloat,
        bold: Bool = false,
        context: CGContext
    ) -> CGFloat {
        var offsetX = x
        for (i, value) in values.enumerated() {
            let w = i < colWidths.count ? colWidths[i] : 80
            // Truncate if too long
            let truncated = value.count > 25 ? String(value.prefix(22)) + "..." : value
            let _ = drawText(truncated, at: CGPoint(x: offsetX, y: y), fontSize: fontSize, bold: bold, context: context)
            offsetX += w
        }
        return y - fontSize - 5
    }

    private static func drawDivider(
        at y: CGFloat,
        x: CGFloat,
        width: CGFloat,
        context: CGContext,
        thin: Bool = false
    ) -> CGFloat {
        context.setStrokeColor(CGColor(gray: 0.8, alpha: 1))
        context.setLineWidth(thin ? 0.5 : 1.0)
        context.move(to: CGPoint(x: x, y: y))
        context.addLine(to: CGPoint(x: x + width, y: y))
        context.strokePath()
        return y - 2
    }

    // MARK: - Utilities

    private static func formatTokens(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
#endif
