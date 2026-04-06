import Foundation

extension Notification.Name {
    static let languageDidChange = Notification.Name("languageDidChange")
}

enum AppLanguage: String, CaseIterable {
    case en = "en"
    case ko = "ko"
    case ja = "ja"
    case zhHans = "zh-Hans"
    case ru = "ru"
    case es = "es"
    case fr = "fr"
    case de = "de"
    case it = "it"

    var translationLanguageCode: String {
        switch self {
        case .zhHans: return "zh-CN"
        default: return rawValue
        }
    }

    var displayName: String {
        switch self {
        case .en: return "English"
        case .ko: return "한국어"
        case .ja: return "日本語"
        case .zhHans: return "中文(简体)"
        case .ru: return "Русский"
        case .es: return "Español"
        case .fr: return "Français"
        case .de: return "Deutsch"
        case .it: return "Italiano"
        }
    }
}

final class LocalizationManager {
    static let shared = LocalizationManager()
    private var bundle: Bundle = .main
    private var lastLoadedLanguage: String?

    private init() { loadBundle() }

    var currentLanguage: AppLanguage {
        get {
            if let code = AppGroupManager.shared.string(forKey: AppConstants.UserDefaultsKeys.appLanguage),
               let lang = AppLanguage(rawValue: code) {
                return lang
            }
            // Bootstrap: 저장값 없음 — device language 감지 후 저장
            let detected = Self.detectDeviceLanguage()
            AppGroupManager.shared.set(detected.rawValue, forKey: AppConstants.UserDefaultsKeys.appLanguage)
            return detected
        }
        set {
            AppGroupManager.shared.set(newValue.rawValue, forKey: AppConstants.UserDefaultsKeys.appLanguage)
            loadBundle()
            NotificationCenter.default.post(name: .languageDidChange, object: nil)
        }
    }

    /// Device preferred language → AppLanguage. 지원 외 언어는 English fallback.
    static func detectDeviceLanguage() -> AppLanguage {
        guard let preferred = Locale.preferredLanguages.first else { return .en }
        let lower = preferred.lowercased()
        // zh-Hans / zh-CN 계열
        if lower.hasPrefix("zh-hans") || lower.hasPrefix("zh-cn") { return .zhHans }
        // prefix 2글자 매칭
        let prefix = String(lower.prefix(2))
        switch prefix {
        case "ko": return .ko
        case "en": return .en
        case "ja": return .ja
        case "ru": return .ru
        case "es": return .es
        case "fr": return .fr
        case "de": return .de
        case "it": return .it
        default:   return .en
        }
    }

    func localized(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: nil, table: "Localizable")
    }

    private func loadBundle() {
        let langCode = currentLanguage.rawValue
        if let path = Bundle.main.path(forResource: langCode, ofType: "lproj"),
           let langBundle = Bundle(path: path) {
            bundle = langBundle
        } else {
            bundle = .main
        }
        lastLoadedLanguage = langCode
    }

    func reload() {
        let currentLang = currentLanguage.rawValue
        guard currentLang != lastLoadedLanguage else { return }
        loadBundle()
    }
}

func L(_ key: String) -> String {
    LocalizationManager.shared.localized(key)
}
