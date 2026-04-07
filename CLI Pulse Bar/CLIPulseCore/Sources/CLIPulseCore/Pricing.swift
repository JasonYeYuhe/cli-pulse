import Foundation

/// Public pricing API for token cost calculations.
/// Delegates to CostUsageScanner.Pricing on macOS; returns nil on other platforms.
public enum TokenPricing {

    /// Calculate cost for Codex (OpenAI) model usage.
    public static func codexCost(model: String, inputTokens: Int, cachedInputTokens: Int, outputTokens: Int) -> Double? {
        #if os(macOS)
        return CostUsageScanner.Pricing.codexCostUSD(model: model, inputTokens: inputTokens, cachedInputTokens: cachedInputTokens, outputTokens: outputTokens)
        #else
        return nil
        #endif
    }

    /// Calculate cost for Claude (Anthropic) model usage.
    public static func claudeCost(model: String, inputTokens: Int, cacheReadInputTokens: Int, cacheCreationInputTokens: Int, outputTokens: Int) -> Double? {
        #if os(macOS)
        return CostUsageScanner.Pricing.claudeCostUSD(model: model, inputTokens: inputTokens, cacheReadInputTokens: cacheReadInputTokens, cacheCreationInputTokens: cacheCreationInputTokens, outputTokens: outputTokens)
        #else
        return nil
        #endif
    }

    /// Format a cost value for display.
    public static func formatCost(_ cost: Double) -> String {
        if cost < 0.01 {
            return cost > 0 ? String(format: "$%.4f", cost) : "$0.00"
        } else if cost < 1.0 {
            return String(format: "$%.2f", cost)
        } else {
            return String(format: "$%.2f", cost)
        }
    }
}
