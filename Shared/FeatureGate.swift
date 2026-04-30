import Foundation

final class FeatureGate {
    static let shared = FeatureGate()
    private init() {}

    private var currentTier: UserTier {
        return SubscriptionStatus.shared.currentTier
    }

    // MARK: - Daily Usage Caps

    var dailyCorrectionLimit: Int {
        if AdminMode.shared.isEnabled { return Int.max }
        switch currentTier {
        case .free: return 10
        case .pro: return 100
        case .premium: return Int.max  // 무제한
        }
    }

    var dailyTranslationLimit: Int {
        if AdminMode.shared.isEnabled { return Int.max }
        switch currentTier {
        case .free: return 10
        case .pro: return 100
        case .premium: return Int.max  // 무제한
        }
    }

    var isPremiumUnlimited: Bool {
        return currentTier == .premium
    }

    // MARK: - Storage Limits

    var maxSavedPhrases: Int {
        if AdminMode.shared.isEnabled { return Int.max }
        switch currentTier {
        case .free: return 5
        case .pro, .premium: return Int.max
        }
    }

    var maxClipboardItems: Int {
        if AdminMode.shared.isEnabled { return Int.max }
        switch currentTier {
        case .free: return 5
        case .pro, .premium: return 30
        }
    }

    var maxHistoryItems: Int {
        if AdminMode.shared.isEnabled { return Int.max }
        switch currentTier {
        case .free: return 50
        case .pro, .premium: return 200
        }
    }

    // MARK: - Feature Locks

    var availableTones: [ToneStyle] {
        return ToneStyle.allCases  // 전 티어 개방
    }

    func isToneLocked(_ tone: ToneStyle) -> Bool {
        return false  // 더 이상 잠금 없음
    }

    // MARK: - AI Model

    var apiModelName: String {
        return "gpt-5-nano"
    }

    // MARK: - AI 메시지 작성 제한

    var dailyComposeLimit: Int {
        if AdminMode.shared.isEnabled { return Int.max }
        switch currentTier {
        case .free: return 5      // 하루 최대 5회 (광고 기반)
        case .pro: return 50      // 하루 50회
        case .premium: return Int.max  // 무제한
        }
    }

    var isComposeUnlimited: Bool {
        return currentTier == .premium || AdminMode.shared.isEnabled
    }

    /// Free 유저: 광고 1회 시청 → AI 작성 3회 충전
    var composeRewardPerAd: Int {
        return 3
    }

    /// Free 유저: 하루 광고 시청 최대 횟수
    var maxDailyComposeAds: Int {
        return 2
    }

    // MARK: - Rewarded Ads

    var maxDailyRewardedAds: Int {
        return 3
    }

    var rewardedAdBonusCount: Int {
        return 5
    }

    var canShowRewardedAd: Bool {
        return currentTier == .free
    }

    // MARK: - Debounce

    var debounceDuration: TimeInterval {
        return 1.0
    }
}
