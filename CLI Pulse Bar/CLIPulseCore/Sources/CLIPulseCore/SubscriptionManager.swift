import Foundation
import StoreKit
import SwiftUI

public enum SubscriptionTier: String, Codable, Sendable {
    case free = "free"
    case pro = "pro"
    case team = "team"

    var tierRank: Int {
        switch self {
        case .free: return 0
        case .pro: return 1
        case .team: return 2
        }
    }
}

@MainActor
public final class SubscriptionManager: ObservableObject {
    public static let shared = SubscriptionManager()

    // Product IDs (must match App Store Connect)
    public static let proMonthlyID = "com.clipulse.pro.monthly"
    public static let proYearlyID = "com.clipulse.pro.yearly"
    public static let teamMonthlyID = "com.clipulse.team.monthly"
    public static let teamYearlyID = "com.clipulse.team.yearly"

    private static let allProductIDs: Set<String> = [
        proMonthlyID, proYearlyID, teamMonthlyID, teamYearlyID
    ]

    @Published public var currentTier: SubscriptionTier = .free
    @Published public var products: [Product] = []
    @Published public var purchasedSubscriptions: [StoreKit.Transaction] = []
    @Published public var isLoading = false

    public var isProOrAbove: Bool { currentTier == .pro || currentTier == .team }
    public var isTeam: Bool { currentTier == .team }

    // Tier limits
    public var maxProviders: Int { currentTier == .free ? 3 : -1 }
    public var maxDevices: Int {
        switch currentTier {
        case .free: return 1
        case .pro: return 5
        case .team: return -1
        }
    }
    public var dataRetentionDays: Int {
        switch currentTier {
        case .free: return 7
        case .pro: return 90
        case .team: return 365
        }
    }

    // Convenience product accessors
    public var proMonthly: Product? { products.first { $0.id == Self.proMonthlyID } }
    public var proYearly: Product? { products.first { $0.id == Self.proYearlyID } }
    public var teamMonthly: Product? { products.first { $0.id == Self.teamMonthlyID } }
    public var teamYearly: Product? { products.first { $0.id == Self.teamYearlyID } }

    private var updateListenerTask: Task<Void, Error>?

    public init() {
        updateListenerTask = listenForTransactions()
        Task { await loadProducts() }
        Task { await updateCurrentEntitlements() }
    }

    deinit {
        updateListenerTask?.cancel()
    }

    // MARK: - Load Products

    public func loadProducts() async {
        isLoading = true
        do {
            let storeProducts = try await Product.products(for: Self.allProductIDs)
            products = storeProducts.sorted { $0.price < $1.price }
        } catch {
            // Products not available yet (e.g., not configured in App Store Connect)
            products = []
        }
        isLoading = false
    }

    // MARK: - Purchase

    public func purchase(_ product: Product) async throws -> StoreKit.Transaction? {
        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await updateCurrentEntitlements()
            await transaction.finish()
            return transaction

        case .userCancelled:
            return nil

        case .pending:
            return nil

        @unknown default:
            return nil
        }
    }

    // MARK: - Restore

    public func restorePurchases() async {
        isLoading = true
        try? await AppStore.sync()
        await updateCurrentEntitlements()
        isLoading = false
    }

    // MARK: - Entitlements

    public func updateCurrentEntitlements() async {
        var activeSubs: [StoreKit.Transaction] = []
        var highestTier: SubscriptionTier = .free
        var highestJWS: String?
        var highestProductID: String?

        for await result in StoreKit.Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }

            if transaction.productType == .autoRenewable {
                activeSubs.append(transaction)

                let txTier: SubscriptionTier
                if transaction.productID == Self.teamMonthlyID ||
                   transaction.productID == Self.teamYearlyID {
                    txTier = .team
                } else if transaction.productID == Self.proMonthlyID ||
                          transaction.productID == Self.proYearlyID {
                    txTier = .pro
                } else {
                    txTier = .free
                }

                if txTier.tierRank > highestTier.tierRank {
                    highestTier = txTier
                    highestJWS = result.jwsRepresentation
                    highestProductID = transaction.productID
                }
            }
        }

        purchasedSubscriptions = activeSubs

        // Server-side receipt validation: send the signed JWS (not raw JSON)
        if let jwsString = highestJWS, !jwsString.isEmpty,
           let productID = highestProductID, let api = apiClient {
            let result = await api.validateReceipt(
                transactionJWS: jwsString,
                productId: productID
            )
            if result.verified {
                let serverTier = SubscriptionTier(rawValue: result.tier) ?? .free
                currentTier = serverTier
                return
            }
        }

        // Fallback: check server-side tier override (admin grant via profiles.tier)
        let serverTier = await fetchServerTier()
        if serverTier.tierRank > highestTier.tierRank {
            highestTier = serverTier
        }

        currentTier = highestTier
    }

    /// Server-side tier override — set by admin in profiles.tier
    public var apiClient: APIClient?

    private func fetchServerTier() async -> SubscriptionTier {
        guard let api = apiClient else { return .free }
        let raw = await api.serverTier()
        return SubscriptionTier(rawValue: raw) ?? .free
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached { [weak self] in
            for await result in StoreKit.Transaction.updates {
                guard let self else { break }
                if let transaction = try? await self.checkVerified(result) {
                    await self.updateCurrentEntitlements()
                    await transaction.finish()
                }
            }
        }
    }

    // MARK: - Verification

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }

    // MARK: - Tier Display Helpers

    public func tierName(for tier: SubscriptionTier) -> String {
        switch tier {
        case .free: return L10n.subscription.free
        case .pro: return L10n.subscription.pro
        case .team: return L10n.subscription.team
        }
    }

    public func tierDescription(for tier: SubscriptionTier) -> String {
        switch tier {
        case .free: return L10n.subscription.freeDescription
        case .pro: return L10n.subscription.proDescription
        case .team: return L10n.subscription.teamDescription
        }
    }
}
