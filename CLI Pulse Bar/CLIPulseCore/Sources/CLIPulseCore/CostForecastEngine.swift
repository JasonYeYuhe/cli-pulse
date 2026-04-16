import Foundation

/// Predicts month-end cost from daily usage history using simple linear regression.
public struct CostForecast: Sendable {
    /// Predicted total cost for the current month
    public let predictedMonthTotal: Double
    /// Lower bound (1 standard deviation)
    public let lowerBound: Double
    /// Upper bound (1 standard deviation)
    public let upperBound: Double
    /// Actual cost so far this month
    public let actualToDate: Double
    /// Number of days of data used for prediction
    public let dataPointCount: Int
    /// Day of month (1-based)
    public let currentDayOfMonth: Int
    /// Total days in month
    public let daysInMonth: Int
    /// True when we have enough data for a meaningful prediction (>= 3 days)
    public let isReliable: Bool
}

public enum CostForecastEngine {

    /// Generate a cost forecast from daily usage data.
    ///
    /// - Parameters:
    ///   - dailyUsage: Raw per-provider/model daily usage entries
    ///   - referenceDate: Date to forecast from (defaults to today)
    /// - Returns: A CostForecast, or nil if insufficient data
    public static func forecast(
        from dailyUsage: [DailyUsage],
        referenceDate: Date = Date()
    ) -> CostForecast? {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: referenceDate)
        let month = calendar.component(.month, from: referenceDate)
        let dayOfMonth = calendar.component(.day, from: referenceDate)

        guard let daysInMonth = calendar.range(of: .day, in: .month, for: referenceDate)?.count else {
            return nil
        }

        // Aggregate cost per date
        let costByDate = aggregateCostByDate(dailyUsage)

        // Build time series for current month: day_of_month -> cost
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone.current

        var dataPoints: [(x: Double, y: Double)] = []
        var actualToDate: Double = 0

        for day in 1...dayOfMonth {
            let dateString = String(format: "%04d-%02d-%02d", year, month, day)
            let cost = costByDate[dateString] ?? 0
            actualToDate += cost
            dataPoints.append((x: Double(day), y: cost))
        }

        let isReliable = dataPoints.count >= 3 && actualToDate > 0

        // If we only have today or less, do simple average projection
        guard !dataPoints.isEmpty else { return nil }

        // Compute cumulative projection
        let avgDailyCost = actualToDate / Double(dayOfMonth)
        let simpleProjection = avgDailyCost * Double(daysInMonth)

        // Linear regression on daily costs to capture trend
        let regression = linearRegression(dataPoints)
        let remainingDays = daysInMonth - dayOfMonth

        // Project remaining days using regression slope
        var projected = actualToDate
        for day in (dayOfMonth + 1)...daysInMonth {
            let predicted = regression.slope * Double(day) + regression.intercept
            projected += max(predicted, 0) // Don't let predicted daily cost go negative
        }

        // Blend: weight regression more when we have more data
        let regressionWeight = min(Double(dataPoints.count) / 14.0, 0.8)
        let blended = projected * regressionWeight + simpleProjection * (1.0 - regressionWeight)

        // Standard error for confidence interval
        let residuals = dataPoints.map { point in
            point.y - (regression.slope * point.x + regression.intercept)
        }
        let stdDev = standardDeviation(residuals.map(\.self))
        let marginOfError = stdDev * sqrt(Double(remainingDays)) * 1.0

        let lowerBound = max(blended - marginOfError, actualToDate)
        let upperBound = blended + marginOfError

        return CostForecast(
            predictedMonthTotal: max(blended, actualToDate),
            lowerBound: lowerBound,
            upperBound: upperBound,
            actualToDate: actualToDate,
            dataPointCount: dataPoints.count,
            currentDayOfMonth: dayOfMonth,
            daysInMonth: daysInMonth,
            isReliable: isReliable
        )
    }

    // MARK: - Helpers

    private static func aggregateCostByDate(_ entries: [DailyUsage]) -> [String: Double] {
        var result: [String: Double] = [:]
        for entry in entries {
            result[entry.date, default: 0] += entry.cost
        }
        return result
    }

    private static func linearRegression(_ points: [(x: Double, y: Double)]) -> (slope: Double, intercept: Double) {
        let n = Double(points.count)
        guard n > 1 else {
            let y = points.first?.y ?? 0
            return (slope: 0, intercept: y)
        }

        let sumX = points.reduce(0.0) { $0 + $1.x }
        let sumY = points.reduce(0.0) { $0 + $1.y }
        let sumXY = points.reduce(0.0) { $0 + $1.x * $1.y }
        let sumX2 = points.reduce(0.0) { $0 + $1.x * $1.x }

        let denominator = n * sumX2 - sumX * sumX
        guard abs(denominator) > 1e-10 else {
            return (slope: 0, intercept: sumY / n)
        }

        let slope = (n * sumXY - sumX * sumY) / denominator
        let intercept = (sumY - slope * sumX) / n
        return (slope: slope, intercept: intercept)
    }

    private static func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0.0, +) / Double(values.count)
        let variance = values.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count - 1)
        return sqrt(variance)
    }
}
