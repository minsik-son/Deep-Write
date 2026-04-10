import UIKit
import UserMessagingPlatform

final class AdConsentManager {
    static let shared = AdConsentManager()
    private init() {}

    private(set) var canRequestAds = false

    func updateConsent(from viewController: UIViewController, completion: @escaping (Bool) -> Void) {
        let params = RequestParameters()

        #if DEBUG
        let debugSettings = DebugSettings()
        debugSettings.geography = .EEA
        params.debugSettings = debugSettings
        #endif

        ConsentInformation.shared.requestConsentInfoUpdate(with: params) { [weak self] error in
            if let error = error {
                print("[AdConsent] Info update failed: \(error.localizedDescription)")
                completion(false)
                return
            }

            Task { @MainActor in
                do {
                    try await ConsentForm.loadAndPresentIfRequired(from: viewController)
                    let canRequest = ConsentInformation.shared.canRequestAds
                    self?.canRequestAds = canRequest
                    completion(canRequest)
                } catch {
                    print("[AdConsent] Form error: \(error.localizedDescription)")
                    completion(false)
                }
            }
        }
    }

    var privacyOptionsRequired: Bool {
        ConsentInformation.shared.privacyOptionsRequirementStatus == .required
    }

    func presentPrivacyOptions(from viewController: UIViewController) {
        ConsentForm.presentPrivacyOptionsForm(from: viewController) { error in
            if let error = error {
                print("[AdConsent] Privacy options error: \(error.localizedDescription)")
            }
        }
    }
}
