package com.clipulse.android.data.model

import java.util.Calendar
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

data class CostForecast(
    val predictedMonthTotal: Double,
    val lowerBound: Double,
    val upperBound: Double,
    val actualToDate: Double,
    val dataPointCount: Int,
    val currentDayOfMonth: Int,
    val daysInMonth: Int,
    val isReliable: Boolean,
)

object CostForecastEngine {

    fun forecast(dailyUsage: List<DailyUsage>, calendar: Calendar = Calendar.getInstance()): CostForecast? {
        val year = calendar.get(Calendar.YEAR)
        val month = calendar.get(Calendar.MONTH) + 1 // Calendar.MONTH is 0-based
        val dayOfMonth = calendar.get(Calendar.DAY_OF_MONTH)
        val daysInMonth = calendar.getActualMaximum(Calendar.DAY_OF_MONTH)

        // Aggregate cost per date
        val costByDate = dailyUsage.groupBy { it.date }.mapValues { (_, items) -> items.sumOf { it.cost } }

        // Build time series for current month
        val dataPoints = mutableListOf<Pair<Double, Double>>() // (x=day, y=cost)
        var actualToDate = 0.0

        for (day in 1..dayOfMonth) {
            val dateString = "%04d-%02d-%02d".format(year, month, day)
            val cost = costByDate[dateString] ?: 0.0
            actualToDate += cost
            dataPoints.add(day.toDouble() to cost)
        }

        if (dataPoints.isEmpty()) return null

        val isReliable = dataPoints.size >= 3 && actualToDate > 0

        // Simple average projection
        val avgDailyCost = actualToDate / dayOfMonth
        val simpleProjection = avgDailyCost * daysInMonth

        // Linear regression on daily costs
        val (slope, intercept) = linearRegression(dataPoints)
        val remainingDays = daysInMonth - dayOfMonth

        // Project remaining days using regression
        var projected = actualToDate
        for (day in (dayOfMonth + 1)..daysInMonth) {
            val predicted = slope * day + intercept
            projected += max(predicted, 0.0)
        }

        // Blend regression + simple projection
        val regressionWeight = min(dataPoints.size / 14.0, 0.8)
        val blended = projected * regressionWeight + simpleProjection * (1.0 - regressionWeight)

        // Standard error for confidence interval
        val residuals = dataPoints.map { (x, y) -> y - (slope * x + intercept) }
        val stdDev = standardDeviation(residuals)
        val marginOfError = stdDev * sqrt(remainingDays.toDouble())

        val lower = max(blended - marginOfError, actualToDate)
        val upper = blended + marginOfError

        return CostForecast(
            predictedMonthTotal = max(blended, actualToDate),
            lowerBound = lower,
            upperBound = upper,
            actualToDate = actualToDate,
            dataPointCount = dataPoints.size,
            currentDayOfMonth = dayOfMonth,
            daysInMonth = daysInMonth,
            isReliable = isReliable,
        )
    }

    private fun linearRegression(points: List<Pair<Double, Double>>): Pair<Double, Double> {
        val n = points.size.toDouble()
        if (n <= 1) return 0.0 to (points.firstOrNull()?.second ?: 0.0)

        val sumX = points.sumOf { it.first }
        val sumY = points.sumOf { it.second }
        val sumXY = points.sumOf { it.first * it.second }
        val sumX2 = points.sumOf { it.first * it.first }

        val denom = n * sumX2 - sumX * sumX
        if (abs(denom) < 1e-10) return 0.0 to (sumY / n)

        val slope = (n * sumXY - sumX * sumY) / denom
        val intercept = (sumY - slope * sumX) / n
        return slope to intercept
    }

    private fun standardDeviation(values: List<Double>): Double {
        if (values.size <= 1) return 0.0
        val mean = values.sum() / values.size
        val variance = values.sumOf { (it - mean) * (it - mean) } / (values.size - 1)
        return sqrt(variance)
    }
}
