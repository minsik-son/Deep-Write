import UIKit

extension AppColors {

    /// 티어별 Accent 컬러 (Free=파란, Pro=골드, Premium=퍼플)
    static var tierAccent: UIColor {
        switch SubscriptionStatus.shared.currentTier {
        case .free:    return accent                                                                    // #3182F6
        case .pro:     return UIColor(red: 0.773, green: 0.580, blue: 0.227, alpha: 1)                // #C5943A
        case .premium: return UIColor(red: 0.545, green: 0.361, blue: 0.784, alpha: 1)                // #8B5CC8
        }
    }

    /// tierAccent의 소프트 버전 (8% alpha)
    static var tierAccentSoft: UIColor {
        return tierAccent.withAlphaComponent(0.08)
    }

    /// 티어별 보조 블루 (아이콘 등)
    static var tierBlue: UIColor {
        switch SubscriptionStatus.shared.currentTier {
        case .free:    return blue                                                                      // #54A0FF
        case .pro:     return UIColor(red: 0.831, green: 0.663, blue: 0.306, alpha: 1)                // #D4A94E
        case .premium: return UIColor(red: 0.655, green: 0.494, blue: 0.859, alpha: 1)                // #A77EDB
        }
    }
}
