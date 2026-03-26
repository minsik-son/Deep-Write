import StoreKit
import Foundation

final class StoreKitManager {
    static let shared = StoreKitManager()

    enum ProductID: String, CaseIterable {
        case monthlyPro = "com.translatorkeyboard.pro.monthly"
        case yearlyPro = "com.translatorkeyboard.pro.annual"
        case monthlyPremium = "com.translatorkeyboard.premium.monthly"
    }

    private(set) var products: [Product] = []
    private var updateListenerTask: Task<Void, Error>?

    private init() {
        updateListenerTask = listenForTransactionUpdates()
    }

    deinit {
        updateListenerTask?.cancel()
    }

    func loadProducts() async throws {
        let productIds = ProductID.allCases.map { $0.rawValue }
        products = try await Product.products(for: Set(productIds))
        products.sort { $0.price < $1.price }
    }

    func purchase(_ product: Product) async throws -> Transaction? {
        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await updateSubscriptionStatus(transaction)
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

    func restorePurchases() async throws {
        try await AppStore.sync()
        await updateCurrentEntitlements()
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreKitError.notEntitled
        case .verified(let item):
            return item
        }
    }

    private func listenForTransactionUpdates() -> Task<Void, Error> {
        Task.detached {
            for await result in Transaction.updates {
                do {
                    let transaction = try self.checkVerified(result)
                    await self.updateSubscriptionStatus(transaction)
                    await transaction.finish()
                } catch {
                    // Transaction verification failed
                }
            }
        }
    }

    private func updateSubscriptionStatus(_ transaction: Transaction) async {
        if transaction.revocationDate != nil {
            SubscriptionStatus.shared.updateTier(.free)
            return
        }

        if let expirationDate = transaction.expirationDate {
            if expirationDate > Date() {
                let tier: UserTier
                if transaction.productID.contains("premium") {
                    tier = .premium
                } else {
                    tier = .pro
                }
                SubscriptionStatus.shared.updateTier(tier, expiryDate: expirationDate)
            } else {
                SubscriptionStatus.shared.updateTier(.free)
            }
        }
    }

    private func updateCurrentEntitlements() async {
        var hasActiveSubscription = false

        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)
                if let expirationDate = transaction.expirationDate, expirationDate > Date() {
                    let tier: UserTier = transaction.productID.contains("premium") ? .premium : .pro
                    SubscriptionStatus.shared.updateTier(tier, expiryDate: expirationDate)
                    hasActiveSubscription = true
                }
            } catch {
                continue
            }
        }

        if !hasActiveSubscription {
            SubscriptionStatus.shared.updateTier(.free)
        }
    }
}
