import UIKit
import GoogleMobileAds

protocol AdManagerDelegate: AnyObject {
    func adManagerDidLoad(_ manager: AdManager)
    func adManagerDidRewardUser(_ manager: AdManager)
    func adManagerDidFailToLoad(_ manager: AdManager)
    func adManagerDidDismissAd(_ manager: AdManager)
    func adManagerReachedDailyLimit(_ manager: AdManager)
}

final class AdManager: NSObject {
    static let shared = AdManager()
    weak var delegate: AdManagerDelegate?

    private var rewardedAd: RewardedAd?
    private var isLoading = false
    private(set) var isAdReady = false
    private(set) var currentMode: RewardMode = .correction

    /// When true, reward callback will NOT update DailyUsageManager (for DEBUG test button)
    var isTestMode = false

    // MARK: - Bootstrap State

    /// MobileAds SDK가 process lifecycle에서 start된 적 있는지
    private var isMobileAdsStarted = false
    /// ATT + UMP consent 완료 후 광고 요청 가능한 상태인지
    private(set) var isBootstrapped = false

    private override init() {
        super.init()
    }

    // MARK: - Bootstrap (ATT → UMP → MobileAds.start)

    /// ATT/UMP consent를 확인하고 MobileAds SDK를 시작한 뒤 completion(true)를 호출.
    /// 실패 시 completion(false). process lifecycle에서 MobileAds.start는 1회만 호출.
    func prepareForAdRequests(from viewController: UIViewController, completion: @escaping (Bool) -> Void) {
        // 이미 bootstrap 완료 상태면 즉시 성공
        if isBootstrapped {
            completion(true)
            return
        }

        // 1. ATT
        ATTManager.shared.requestTrackingAuthorizationIfNeeded { [weak self] in
            guard let self = self else { completion(false); return }

            // 2. UMP
            AdConsentManager.shared.updateConsent(from: viewController) { [weak self] canRequest in
                guard let self = self else { completion(false); return }

                guard canRequest else {
                    print("[AdManager] Bootstrap: consent denied or failed")
                    completion(false)
                    return
                }

                // 3. MobileAds.start (1회만)
                if !self.isMobileAdsStarted {
                    self.isMobileAdsStarted = true
                    MobileAds.shared.start { _ in
                        self.isBootstrapped = true
                        completion(true)
                    }
                } else {
                    self.isBootstrapped = true
                    completion(true)
                }
            }
        }
    }

    // MARK: - Load

    func loadRewardedAd() {
        guard !isLoading else { return }
        guard AdConfiguration.isConfigured else {
            print("[AdManager] Ad configuration not set — ads disabled")
            return
        }
        // Consent/bootstrap guard — bypass 방지
        guard isBootstrapped else {
            print("[AdManager] loadRewardedAd skipped — not bootstrapped (ATT/UMP/MobileAds.start incomplete)")
            return
        }

        isLoading = true
        let adUnitID = AdConfiguration.rewardedAdUnitID

        RewardedAd.load(with: adUnitID, request: Request()) { [weak self] ad, error in
            guard let self = self else { return }
            self.isLoading = false

            if let error = error {
                print("[AdManager] Failed to load rewarded ad: \(error.localizedDescription)")
                self.isAdReady = false
                self.delegate?.adManagerDidFailToLoad(self)
                return
            }

            self.rewardedAd = ad
            self.rewardedAd?.fullScreenContentDelegate = self
            self.isAdReady = true
            self.delegate?.adManagerDidLoad(self)
        }
    }

    // MARK: - Show

    func showRewardedAd(from viewController: UIViewController, mode: RewardMode) {
        currentMode = mode

        guard isAdReady, let rewardedAd = rewardedAd else {
            // Not ready yet — trigger load but do NOT report failure
            loadRewardedAd()
            return
        }

        if !isTestMode {
            let canWatch: Bool
            if mode == .compose {
                canWatch = DailyUsageManager.shared.canWatchComposeRewardedAd
            } else {
                canWatch = DailyUsageManager.shared.canWatchRewardedAd(for: mode)
            }

            guard canWatch else {
                delegate?.adManagerReachedDailyLimit(self)
                return
            }
        }

        rewardedAd.present(from: viewController) { [weak self] in
            guard let self = self else { return }
            self.grantReward(mode: mode)
        }
    }

    func canShowAd(for mode: RewardMode) -> Bool {
        guard AdConfiguration.isConfigured else { return false }
        if mode == .compose {
            return isAdReady && DailyUsageManager.shared.canWatchComposeRewardedAd
        }
        return isAdReady && DailyUsageManager.shared.canWatchRewardedAd(for: mode)
    }

    // MARK: - Reward (변경 금지)

    private func grantReward(mode: RewardMode) {
        guard !isTestMode else {
            print("[AdManager] TEST MODE — reward callback received, no usage recorded")
            delegate?.adManagerDidRewardUser(self)
            return
        }
        switch mode {
        case .compose:
            DailyUsageManager.shared.recordComposeRewardedAd()
        case .correction, .translation:
            DailyUsageManager.shared.recordRewardedAd(for: mode)
        }
        delegate?.adManagerDidRewardUser(self)
    }
}

extension AdManager: FullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        isAdReady = false
        rewardedAd = nil
        delegate?.adManagerDidDismissAd(self)
        loadRewardedAd()  // bootstrap guard가 자동 적용됨
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        print("[AdManager] Failed to present ad: \(error.localizedDescription)")
        isAdReady = false
        rewardedAd = nil
        delegate?.adManagerDidFailToLoad(self)
        loadRewardedAd()  // bootstrap guard가 자동 적용됨
    }
}
