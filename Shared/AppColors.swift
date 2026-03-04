import UIKit

enum AppColors {
    static let bg = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.039, green: 0.039, blue: 0.047, alpha: 1)       // dark: #0A0A0C
        : UIColor(red: 0.965, green: 0.965, blue: 0.975, alpha: 1)       // light: #F6F6F9
    }
    static let surface = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.075, green: 0.075, blue: 0.086, alpha: 1)       // dark: #131316
        : .white                                                          // light: #FFFFFF
    }
    static let card = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.086, green: 0.086, blue: 0.102, alpha: 1)       // dark: #16161A
        : .white                                                          // light: #FFFFFF
    }
    static let cardHover = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.110, green: 0.110, blue: 0.133, alpha: 1)       // dark: #1C1C22
        : UIColor(red: 0.949, green: 0.949, blue: 0.957, alpha: 1)       // light: #F2F2F4
    }
    static let border = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor.white.withAlphaComponent(0.06)
        : UIColor.black.withAlphaComponent(0.06)
    }
    static let borderActive = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor.white.withAlphaComponent(0.12)
        : UIColor.black.withAlphaComponent(0.15)
    }
    static let text = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.941, green: 0.941, blue: 0.949, alpha: 1)       // dark: #F0F0F2
        : UIColor(red: 0.098, green: 0.122, blue: 0.157, alpha: 1)       // light: #191F28
    }
    static let textSub = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.541, green: 0.541, blue: 0.588, alpha: 1)       // dark: #8A8A96
        : UIColor(red: 0.420, green: 0.467, blue: 0.518, alpha: 1)       // light: #6B7684
    }
    static let textMuted = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.333, green: 0.333, blue: 0.373, alpha: 1)       // dark: #55555F
        : UIColor(red: 0.690, green: 0.722, blue: 0.757, alpha: 1)       // light: #B0B8C1
    }
    static let accent = UIColor(red: 0.192, green: 0.510, blue: 0.965, alpha: 1)            // #3182F6
    static let accentSoft = UIColor(red: 0.192, green: 0.510, blue: 0.965, alpha: 0.08)
    static let green = UIColor(red: 0.0, green: 0.782, blue: 0.506, alpha: 1)               // #00C781
    static let red = UIColor(red: 0.941, green: 0.267, blue: 0.322, alpha: 1)               // #F04452
    static let orange = UIColor(red: 1.0, green: 0.624, blue: 0.263, alpha: 1)              // #FF9F43
    static let blue = UIColor(red: 0.329, green: 0.627, blue: 1.0, alpha: 1)                // #54A0FF
    static let pink = UIColor(red: 1.0, green: 0.420, blue: 0.616, alpha: 1)                // #FF6B9D
}

enum AppSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

enum AppFont {
    static let title = UIFont.systemFont(ofSize: 26, weight: .bold)
    static let heading = UIFont.systemFont(ofSize: 18, weight: .bold)
    static let body = UIFont.systemFont(ofSize: 15, weight: .regular)
    static let bodyMedium = UIFont.systemFont(ofSize: 15, weight: .medium)
    static let caption = UIFont.systemFont(ofSize: 13, weight: .regular)
    static let captionSemiBold = UIFont.systemFont(ofSize: 13, weight: .semibold)
    static let small = UIFont.systemFont(ofSize: 12, weight: .regular)
    static let tabLabel = UIFont.systemFont(ofSize: 10, weight: .regular)
}

enum AppRadius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
}
