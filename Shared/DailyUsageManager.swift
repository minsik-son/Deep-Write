import Foundation

enum RewardMode: String {
    case correction
    case translation
    case compose
}

final class DailyUsageManager {
    static let shared = DailyUsageManager()

    private let defaults: UserDefaults?

    private let correctionCountKey = "daily_correction_count"
    private let translationCountKey = "daily_translation_count"
    private let rewardedAdCorrectionCountKey = "daily_rewarded_ad_correction_count"
    private let rewardedAdTranslationCountKey = "daily_rewarded_ad_translation_count"
    private let bonusCorrectionKey = "bonus_correction_count"
    private let bonusTranslationKey = "bonus_translation_count"
    private let composeCountKey = "daily_compose_count"
    private let rewardedAdComposeCountKey = "daily_rewarded_ad_compose_count"
    private let bonusComposeKey = "bonus_compose_count"
    private let chatReplyCountKey = "daily_chat_reply_count"
    private let rewardedAdChatReplyCountKey = "daily_rewarded_ad_chat_reply_count"
    private let bonusChatReplyKey = "bonus_chat_reply_count"
    private let lastResetDateKey = "daily_usage_last_reset"

    private let keychainUsageDataKey = "kc_daily_usage_data"

    private init() {
        defaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier)
        restoreFromKeychainIfNeeded()
        resetIfNewDay()
    }

    // MARK: - Usage Counts

    var correctionCount: Int {
        resetIfNewDay()
        return defaults?.integer(forKey: correctionCountKey) ?? 0
    }

    var translationCount: Int {
        resetIfNewDay()
        return defaults?.integer(forKey: translationCountKey) ?? 0
    }

    var remainingCorrections: Int {
        let limit = FeatureGate.shared.dailyCorrectionLimit
        let bonus = defaults?.integer(forKey: bonusCorrectionKey) ?? 0
        let used = correctionCount
        return max(0, (limit + bonus) - used)
    }

    var remainingTranslations: Int {
        let limit = FeatureGate.shared.dailyTranslationLimit
        let bonus = defaults?.integer(forKey: bonusTranslationKey) ?? 0
        let used = translationCount
        return max(0, (limit + bonus) - used)
    }

    // MARK: - Record Usage

    func recordCorrection() {
        resetIfNewDay()
        let count = (defaults?.integer(forKey: correctionCountKey) ?? 0) + 1
        defaults?.set(count, forKey: correctionCountKey)
        syncToKeychain()
    }

    func recordTranslation() {
        resetIfNewDay()
        let count = (defaults?.integer(forKey: translationCountKey) ?? 0) + 1
        defaults?.set(count, forKey: translationCountKey)
        syncToKeychain()
    }

    // MARK: - Limit Check

    func canUseCorrection() -> Bool {
        if FeatureGate.shared.isPremiumUnlimited { return true }
        return remainingCorrections > 0
    }

    func canUseTranslation() -> Bool {
        if FeatureGate.shared.isPremiumUnlimited { return true }
        return remainingTranslations > 0
    }

    // MARK: - AI 작성 사용량

    var composeCount: Int {
        resetIfNewDay()
        return defaults?.integer(forKey: composeCountKey) ?? 0
    }

    var remainingComposes: Int {
        if FeatureGate.shared.isComposeUnlimited { return Int.max }
        let limit = FeatureGate.shared.dailyComposeLimit
        let bonus = defaults?.integer(forKey: bonusComposeKey) ?? 0
        let used = composeCount
        return max(0, (limit + bonus) - used)
    }

    func recordChatReply() {
        resetIfNewDay()
        let count = (defaults?.integer(forKey: chatReplyCountKey) ?? 0) + 1
        defaults?.set(count, forKey: chatReplyCountKey)
        syncToKeychain()
    }

    func recordCompose() {
        resetIfNewDay()
        let count = (defaults?.integer(forKey: composeCountKey) ?? 0) + 1
        defaults?.set(count, forKey: composeCountKey)
        syncToKeychain()
    }

    func canUseCompose() -> Bool {
        if FeatureGate.shared.isComposeUnlimited { return true }
        return remainingComposes > 0
    }

    /// 리워드 광고 시청 완료 → AI 작성 3회 충전
    func recordComposeRewardedAd() {
        resetIfNewDay()
        let count = (defaults?.integer(forKey: rewardedAdComposeCountKey) ?? 0) + 1
        defaults?.set(count, forKey: rewardedAdComposeCountKey)

        let bonus = FeatureGate.shared.composeRewardPerAd
        let currentBonus = defaults?.integer(forKey: bonusComposeKey) ?? 0
        defaults?.set(currentBonus + bonus, forKey: bonusComposeKey)
        syncToKeychain()
    }

    var composeRewardedAdCount: Int {
        resetIfNewDay()
        return defaults?.integer(forKey: rewardedAdComposeCountKey) ?? 0
    }

    var canWatchComposeRewardedAd: Bool {
        guard FeatureGate.shared.canShowRewardedAd else { return false }
        guard composeRewardedAdCount < FeatureGate.shared.maxDailyComposeAds else { return false }
        return remainingComposes == 0
    }

    // MARK: - Rewarded Ads (Mode-specific)

    func rewardedAdCount(for mode: RewardMode) -> Int {
        resetIfNewDay()
        let key = mode == .correction ? rewardedAdCorrectionCountKey : rewardedAdTranslationCountKey
        return defaults?.integer(forKey: key) ?? 0
    }

    func canWatchRewardedAd(for mode: RewardMode) -> Bool {
        guard FeatureGate.shared.canShowRewardedAd else { return false }
        guard rewardedAdCount(for: mode) < FeatureGate.shared.maxDailyRewardedAds else { return false }
        // 보너스가 남아 있으면 먼저 소진해야 함
        switch mode {
        case .correction: return remainingCorrections == 0
        case .translation: return remainingTranslations == 0
        case .compose: return false // compose는 별도 메서드 사용
        }
    }

    func recordRewardedAd(for mode: RewardMode) {
        let key = mode == .correction ? rewardedAdCorrectionCountKey : rewardedAdTranslationCountKey
        let count = (defaults?.integer(forKey: key) ?? 0) + 1
        defaults?.set(count, forKey: key)

        let bonus = FeatureGate.shared.rewardedAdBonusCount
        let bonusKey = mode == .correction ? bonusCorrectionKey : bonusTranslationKey
        let currentBonus = defaults?.integer(forKey: bonusKey) ?? 0
        defaults?.set(currentBonus + bonus, forKey: bonusKey)
        syncToKeychain()
    }

    // MARK: - Midnight Reset

    private func resetIfNewDay() {
        let today = Calendar.current.startOfDay(for: Date())
        let lastReset = defaults?.object(forKey: lastResetDateKey) as? Date ?? .distantPast

        if today > lastReset {
            defaults?.set(0, forKey: correctionCountKey)
            defaults?.set(0, forKey: translationCountKey)
            defaults?.set(0, forKey: rewardedAdCorrectionCountKey)
            defaults?.set(0, forKey: rewardedAdTranslationCountKey)
            defaults?.set(0, forKey: bonusCorrectionKey)
            defaults?.set(0, forKey: bonusTranslationKey)
            defaults?.set(0, forKey: composeCountKey)
            defaults?.set(0, forKey: rewardedAdComposeCountKey)
            defaults?.set(0, forKey: bonusComposeKey)
            defaults?.set(0, forKey: chatReplyCountKey)
            defaults?.set(0, forKey: rewardedAdChatReplyCountKey)
            defaults?.set(0, forKey: bonusChatReplyKey)
            defaults?.set(today, forKey: lastResetDateKey)
            syncToKeychain()
        }
    }

    // MARK: - Keychain Sync

    private func restoreFromKeychainIfNeeded() {
        // UserDefaults에 날짜가 있으면 정상 상태 (재설치 아님)
        if defaults?.object(forKey: lastResetDateKey) as? Date != nil {
            return
        }

        // UserDefaults 비어있고 Keychain에 데이터 있으면 → 재설치
        guard let usageData = KeychainHelper.shared.getCodable(DailyUsageData.self, forKey: keychainUsageDataKey) else {
            return
        }

        // Keychain 날짜가 오늘이면 카운트 복원
        if Calendar.current.isDateInToday(usageData.lastResetDate) {
            defaults?.set(usageData.lastResetDate, forKey: lastResetDateKey)
            defaults?.set(usageData.correctionCount, forKey: correctionCountKey)
            defaults?.set(usageData.translationCount, forKey: translationCountKey)
            defaults?.set(usageData.bonusCorrection, forKey: bonusCorrectionKey)
            defaults?.set(usageData.bonusTranslation, forKey: bonusTranslationKey)
            defaults?.set(usageData.rewardedAdCorrection, forKey: rewardedAdCorrectionCountKey)
            defaults?.set(usageData.rewardedAdTranslation, forKey: rewardedAdTranslationCountKey)
            defaults?.set(usageData.composeCount, forKey: composeCountKey)
            defaults?.set(usageData.bonusCompose, forKey: bonusComposeKey)
            defaults?.set(usageData.rewardedAdCompose, forKey: rewardedAdComposeCountKey)
            defaults?.set(usageData.chatReplyCount, forKey: chatReplyCountKey)
            defaults?.set(usageData.bonusChatReply, forKey: bonusChatReplyKey)
            defaults?.set(usageData.rewardedAdChatReply, forKey: rewardedAdChatReplyCountKey)
            defaults?.synchronize()
        }
        // 날짜가 오늘이 아니면 → 리셋 대상이므로 복원하지 않음 (resetIfNewDay가 처리)
    }

    private func syncToKeychain() {
        let usageData = DailyUsageData(
            lastResetDate: defaults?.object(forKey: lastResetDateKey) as? Date ?? Date(),
            correctionCount: defaults?.integer(forKey: correctionCountKey) ?? 0,
            translationCount: defaults?.integer(forKey: translationCountKey) ?? 0,
            bonusCorrection: defaults?.integer(forKey: bonusCorrectionKey) ?? 0,
            bonusTranslation: defaults?.integer(forKey: bonusTranslationKey) ?? 0,
            rewardedAdCorrection: defaults?.integer(forKey: rewardedAdCorrectionCountKey) ?? 0,
            rewardedAdTranslation: defaults?.integer(forKey: rewardedAdTranslationCountKey) ?? 0,
            composeCount: defaults?.integer(forKey: composeCountKey) ?? 0,
            bonusCompose: defaults?.integer(forKey: bonusComposeKey) ?? 0,
            rewardedAdCompose: defaults?.integer(forKey: rewardedAdComposeCountKey) ?? 0,
            chatReplyCount: defaults?.integer(forKey: chatReplyCountKey) ?? 0,
            bonusChatReply: defaults?.integer(forKey: bonusChatReplyKey) ?? 0,
            rewardedAdChatReply: defaults?.integer(forKey: rewardedAdChatReplyCountKey) ?? 0
        )

        DispatchQueue.global(qos: .utility).async {
            KeychainHelper.shared.setCodable(usageData, forKey: "kc_daily_usage_data")
        }
    }
}
