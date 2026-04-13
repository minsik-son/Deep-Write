import AppTrackingTransparency
import OSLog

final class ATTManager {
    static let shared = ATTManager()
    private init() {}

    private let logger = Logger(
        subsystem: "com.translatorkeyboard.app",
        category: "ATT"
    )

    func requestTrackingAuthorizationIfNeeded(completion: @escaping () -> Void) {
        guard #available(iOS 14, *) else {
            logger.debug("iOS < 14, skipping ATT")
            completion()
            return
        }

        let status = ATTrackingManager.trackingAuthorizationStatus

        switch status {
        case .notDetermined:
            logger.debug("ATT status=notDetermined, requesting authorization")
            ATTrackingManager.requestTrackingAuthorization { [weak self] newStatus in
                self?.logger.debug("ATT result=\(String(describing: newStatus.rawValue))")
                DispatchQueue.main.async {
                    completion()
                }
            }
        default:
            logger.debug("ATT status already determined: \(String(describing: status.rawValue))")
            completion()
        }
    }
}
