import UIKit
import GoogleMobileAds

protocol AdManagerDelegate: AnyObject {
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

    private override init() {
        super.init()
    }

    func loadRewardedAd() {
        guard !isLoading else { return }
        guard AdConfiguration.isConfigured else {
            print("[AdManager] Ad configuration not set — ads disabled")
            return
        }
        guard AdConsentManager.shared.canRequestAds else {
            print("[AdManager] Cannot request ads — consent not granted")
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
        }
    }

    func showRewardedAd(from viewController: UIViewController, mode: RewardMode) {
        currentMode = mode

        guard isAdReady, let rewardedAd = rewardedAd else {
            loadRewardedAd()
            delegate?.adManagerDidFailToLoad(self)
            return
        }

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

    private func grantReward(mode: RewardMode) {
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
        loadRewardedAd()
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        print("[AdManager] Failed to present ad: \(error.localizedDescription)")
        isAdReady = false
        rewardedAd = nil
        delegate?.adManagerDidFailToLoad(self)
        loadRewardedAd()
    }
}
