import Foundation

enum UserTier: String {
    case free = "free"
    case pro = "pro"
    case premium = "premium"
}

final class SubscriptionStatus {
    static let shared = SubscriptionStatus()

    private let appGroup = AppGroupManager.shared

    private init() {}

    var currentTier: UserTier {
        guard let tierString = appGroup.string(forKey: AppConstants.UserDefaultsKeys.subscriptionTier),
              let tier = UserTier(rawValue: tierString) else {
            return .free
        }

        if tier != .free {
            guard let expiry = appGroup.date(forKey: AppConstants.UserDefaultsKeys.subscriptionExpiry),
                  expiry > Date() else {
                return .free
            }
        }

        return tier
    }

    var isPro: Bool {
        #if DEBUG
        return true
        #else
        return currentTier == .pro || currentTier == .premium
        #endif
    }

    func updateTier(_ tier: UserTier, expiryDate: Date? = nil) {
        appGroup.set(tier.rawValue, forKey: AppConstants.UserDefaultsKeys.subscriptionTier)
        if let expiry = expiryDate {
            appGroup.set(expiry, forKey: AppConstants.UserDefaultsKeys.subscriptionExpiry)
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Notification.Name("subscriptionStatusDidChange"), object: nil)
        }
    }
}
