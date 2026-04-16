package com.clipulse.android.util

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.pdf.PdfDocument
import com.clipulse.android.data.model.CostForecast
import com.clipulse.android.data.model.DailyUsage
import com.clipulse.android.data.model.DashboardSummary
import com.clipulse.android.data.model.ProviderUsage
import com.clipulse.android.data.model.SessionRecord
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

object PdfReportGenerator {

    private const val PAGE_WIDTH = 612
    private const val PAGE_HEIGHT = 792
    private const val MARGIN = 50f
    private val CONTENT_WIDTH = PAGE_WIDTH - MARGIN * 2

    fun generate(
        context: Context,
        dashboard: DashboardSummary?,
        providers: List<ProviderUsage>,
        sessions: List<SessionRecord>,
        dailyUsage: List<DailyUsage>,
        costForecast: CostForecast?,
    ): File? {
        val doc = PdfDocument()
        var pageNum = 1
        var pageInfo = PdfDocument.PageInfo.Builder(PAGE_WIDTH, PAGE_HEIGHT, pageNum).create()
        var page = doc.startPage(pageInfo)
        var canvas = page.canvas
        var y = MARGIN

        val titlePaint = Paint().apply { textSize = 22f; isFakeBoldText = true; color = Color.parseColor("#1a1a1a") }
        val headingPaint = Paint().apply { textSize = 16f; isFakeBoldText = true; color = Color.parseColor("#1a1a1a") }
        val bodyPaint = Paint().apply { textSize = 11f; color = Color.parseColor("#333333") }
        val labelPaint = Paint().apply { textSize = 10f; color = Color.GRAY }
        val boldPaint = Paint().apply { textSize = 11f; isFakeBoldText = true; color = Color.parseColor("#1a1a1a") }
        val smallPaint = Paint().apply { textSize = 9f; color = Color.parseColor("#333333") }
        val smallBoldPaint = Paint().apply { textSize = 9f; isFakeBoldText = true; color = Color.parseColor("#1a1a1a") }
        val linePaint = Paint().apply { color = Color.parseColor("#cccccc"); strokeWidth = 1f }
        val thinLinePaint = Paint().apply { color = Color.parseColor("#dddddd"); strokeWidth = 0.5f }
        val barPaint = Paint().apply { color = Color.parseColor("#3380FF"); alpha = 180 }

        fun newPage() {
            doc.finishPage(page)
            pageNum++
            pageInfo = PdfDocument.PageInfo.Builder(PAGE_WIDTH, PAGE_HEIGHT, pageNum).create()
            page = doc.startPage(pageInfo)
            canvas = page.canvas
            y = MARGIN
        }

        fun checkSpace(needed: Float) {
            if (y + needed > PAGE_HEIGHT - MARGIN) newPage()
        }

        fun divider(thin: Boolean = false) {
            canvas.drawLine(MARGIN, y, MARGIN + CONTENT_WIDTH, y, if (thin) thinLinePaint else linePaint)
            y += 4
        }

        val dateFormat = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        val dateDisplayFormat = SimpleDateFormat("MMMM d, yyyy", Locale.US)

        // Title
        canvas.drawText("CLI Pulse Monthly Report", MARGIN, y + 22f, titlePaint)
        y += 30f
        canvas.drawText("Generated: ${dateDisplayFormat.format(Date())}", MARGIN, y + 10f, labelPaint)
        y += 20f
        divider()
        y += 8f

        // Summary
        if (dashboard != null) {
            canvas.drawText("Summary", MARGIN, y + 16f, headingPaint)
            y += 24f

            fun kv(label: String, value: String) {
                canvas.drawText(label, MARGIN, y + 11f, labelPaint)
                canvas.drawText(value, MARGIN + CONTENT_WIDTH * 0.5f, y + 11f, boldPaint)
                y += 16f
            }

            kv("Today's Usage", formatTokens(dashboard.totalUsageToday))
            kv("Today's Estimated Cost", "$${String.format("%.2f", dashboard.totalEstimatedCostToday)}")
            kv("Active Sessions", "${dashboard.activeSessions}")
            kv("Online Devices", "${dashboard.onlineDevices}")
            kv("Unresolved Alerts", "${dashboard.unresolvedAlerts}")
            y += 8f
        }

        // Forecast
        if (costForecast != null && costForecast.isReliable) {
            divider()
            y += 4f
            canvas.drawText("Cost Forecast", MARGIN, y + 16f, headingPaint)
            y += 24f

            fun kv(label: String, value: String) {
                canvas.drawText(label, MARGIN, y + 11f, labelPaint)
                canvas.drawText(value, MARGIN + CONTENT_WIDTH * 0.5f, y + 11f, boldPaint)
                y += 16f
            }

            kv("Month-End Estimate", "$${String.format("%.2f", costForecast.predictedMonthTotal)}")
            kv("Spent So Far", "$${String.format("%.2f", costForecast.actualToDate)}")
            kv("Confidence Range", "$${String.format("%.2f", costForecast.lowerBound)} — $${String.format("%.2f", costForecast.upperBound)}")
            kv("Progress", "${costForecast.currentDayOfMonth}/${costForecast.daysInMonth} days")
            y += 8f
        }

        // Provider breakdown
        divider()
        y += 4f
        canvas.drawText("Provider Breakdown", MARGIN, y + 16f, headingPaint)
        y += 24f

        // Table header
        val provCols = floatArrayOf(0f, 0.3f, 0.5f, 0.7f, 0.85f)
        val provHeaders = arrayOf("Provider", "Week Usage", "Est. Cost", "Remaining", "Quota")
        for (i in provHeaders.indices) {
            canvas.drawText(provHeaders[i], MARGIN + CONTENT_WIDTH * provCols[i], y + 9f, smallBoldPaint)
        }
        y += 14f
        divider(thin = true)

        val sortedProviders = providers.sortedByDescending { it.estimatedCostWeek }
        for (p in sortedProviders) {
            checkSpace(14f)
            val row = arrayOf(
                p.provider.take(20),
                formatTokens(p.weekUsage),
                "$${String.format("%.2f", p.estimatedCostWeek)}",
                p.remaining?.let { formatTokens(it) } ?: "N/A",
                p.quota?.let { formatTokens(it) } ?: "N/A",
            )
            for (i in row.indices) {
                canvas.drawText(row[i], MARGIN + CONTENT_WIDTH * provCols[i], y + 9f, smallPaint)
            }
            y += 13f
        }
        y += 8f

        // Top sessions
        checkSpace(40f)
        divider()
        y += 4f
        canvas.drawText("Top Sessions by Cost", MARGIN, y + 16f, headingPaint)
        y += 24f

        val sessCols = floatArrayOf(0f, 0.25f, 0.5f, 0.65f, 0.85f)
        val sessHeaders = arrayOf("Provider", "Project", "Cost", "Usage", "Status")
        for (i in sessHeaders.indices) {
            canvas.drawText(sessHeaders[i], MARGIN + CONTENT_WIDTH * sessCols[i], y + 9f, smallBoldPaint)
        }
        y += 14f
        divider(thin = true)

        val topSessions = sessions.sortedByDescending { it.estimatedCost }.take(15)
        for (s in topSessions) {
            checkSpace(14f)
            val row = arrayOf(
                s.provider.take(18),
                s.project.take(18),
                "$${String.format("%.4f", s.estimatedCost)}",
                formatTokens(s.totalUsage),
                s.status.take(10),
            )
            for (i in row.indices) {
                canvas.drawText(row[i], MARGIN + CONTENT_WIDTH * sessCols[i], y + 9f, smallPaint)
            }
            y += 13f
        }
        y += 8f

        // Daily cost trend
        if (dailyUsage.isNotEmpty()) {
            checkSpace(40f)
            divider()
            y += 4f
            canvas.drawText("Daily Cost Trend (Last 30 Days)", MARGIN, y + 16f, headingPaint)
            y += 24f

            val costByDate = dailyUsage.groupBy { it.date }.mapValues { (_, items) -> items.sumOf { it.cost } }
            val sortedDates = costByDate.keys.sorted().takeLast(30)
            val maxCost = costByDate.values.maxOrNull() ?: 1.0

            for (date in sortedDates) {
                checkSpace(13f)
                val cost = costByDate[date] ?: 0.0
                val barWidth = if (maxCost > 0) (cost / maxCost * (CONTENT_WIDTH - 130)).toFloat() else 0f

                canvas.drawText(date.takeLast(5), MARGIN, y + 8f, labelPaint)
                canvas.drawRect(MARGIN + 45f, y, MARGIN + 45f + barWidth, y + 8f, barPaint)
                canvas.drawText("$${String.format("%.2f", cost)}", MARGIN + 50f + CONTENT_WIDTH - 130f, y + 8f, labelPaint)
                y += 12f
            }
        }

        // Footer
        checkSpace(30f)
        y += 10f
        divider()
        canvas.drawText("CLI Pulse v1.9 • ${dateDisplayFormat.format(Date())}", MARGIN, y + 8f, labelPaint)

        doc.finishPage(page)

        // Write to file
        val exportDir = File(context.cacheDir, "cli_pulse_exports").also { it.mkdirs() }
        val file = File(exportDir, "cli-pulse-report-${dateFormat.format(Date())}.pdf")
        return try {
            FileOutputStream(file).use { doc.writeTo(it) }
            doc.close()
            file
        } catch (_: Exception) {
            doc.close()
            null
        }
    }

    private fun formatTokens(value: Int): String = when {
        value >= 1_000_000 -> String.format("%.1fM", value / 1_000_000.0)
        value >= 1_000 -> String.format("%.1fK", value / 1_000.0)
        else -> "$value"
    }
}
