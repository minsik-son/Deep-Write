import Foundation

enum AdConfiguration {
    // MARK: - Test IDs (Google official sample — DEBUG only)
    private static let testAppID = "ca-app-pub-3940256099942544~1458002511"
    private static let testRewardedAdUnitID = "ca-app-pub-3940256099942544/1712485313"

    // MARK: - Production IDs
    // ⚠️ RELEASE BLOCKER: Replace with real AdMob IDs before App Store submission
    static let productionAppID = "ca-app-pub-9921649727270589~7890214484"
    static let productionRewardedAdUnitID = "ca-app-pub-9921649727270589/6599417186"

    // MARK: - Configuration Status
    /// Returns true only when production IDs are properly set for release,
    /// or when running in DEBUG mode with test IDs.
    static var isConfigured: Bool {
        #if DEBUG
        return true
        #else
        return !productionAppID.isEmpty && !productionRewardedAdUnitID.isEmpty
        #endif
    }

    // MARK: - Active IDs
    static var appID: String {
        #if DEBUG
        return testAppID
        #else
        return productionAppID
        #endif
    }

    static var rewardedAdUnitID: String {
        #if DEBUG
        return testRewardedAdUnitID
        #else
        return productionRewardedAdUnitID
        #endif
    }

    static var isUsingTestIDs: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}
