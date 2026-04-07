import Foundation

/// Static pricing table for AI tool subscriptions.
/// Maps (provider, plan_type) to monthly cost in USD.
/// Data source: each collector already returns plan_type from the provider API.
public enum SubscriptionPricing {

    /// Returns the monthly subscription cost for a given provider and plan.
    /// Returns nil for free tiers or unknown plans.
    public static func monthlyCost(provider: String, plan: String?) -> Double? {
        guard let plan = plan?.trimmingCharacters(in: .whitespacesAndNewlines),
              !plan.isEmpty else { return nil }
        let normalizedProvider = provider.lowercased()
        let normalizedPlan = plan.lowercased()

        for (provKey, plans) in table {
            guard provKey.lowercased() == normalizedProvider else { continue }
            for (planKey, cost) in plans {
                if planKey.lowercased() == normalizedPlan { return cost }
            }
        }
        return nil
    }

    /// All known subscription plans and their monthly costs.
    public static let table: [String: [String: Double]] = [
        "Claude": [
            "Max 5x": 100,
            "Max 20x": 200,
            "Pro": 20,
            "Team": 30,
            "Enterprise": 0,  // custom pricing
        ],
        "Codex": [
            "Plus": 20,
            "Pro": 200,
            "Team": 30,
            "Enterprise": 0,
        ],
        "Gemini": [
            "Pro": 20,
            "Advanced": 20,
            "Business": 30,
            "Enterprise": 0,
        ],
        "Cursor": [
            "Pro": 20,
            "Business": 40,
            "Enterprise": 0,
        ],
        "Copilot": [
            "Individual": 10,
            "Business": 19,
            "Enterprise": 39,
        ],
        "JetBrains AI": [
            "Pro": 10,
            "Ultimate": 20,
        ],
        "Warp": [
            "Pro": 15,
            "Team": 22,
        ],
        "Augment": [
            "Dev": 50,
            "Team": 60,
        ],
        "OpenRouter": [:],  // pay-per-token, no subscription
        "Ollama": [:],      // free / local
        "Kilo": [
            "Pro": 15,
        ],
        "Kimi": [
            "Premium": 10,
        ],
        "Kimi K2": [
            "Premium": 10,
        ],
        "Perplexity": [
            "Pro": 20,
        ],
        "Amp": [
            "Pro": 20,
        ],
    ]
}
