import Foundation

enum AppConstants {
    static let appGroupIdentifier = "group.com.translatorkeyboard.shared"
    static let mainBundleIdentifier = "com.translatorkeyboard.app"
    static let extensionBundleIdentifier = "com.translatorkeyboard.app.keyboard"

    enum UserDefaultsKeys {
        static let subscriptionTier = "subscription_tier"
        static let subscriptionExpiry = "subscription_expiry"
        static let selectedTheme = "selected_theme"
        static let dailySessionCount = "daily_session_count"
        static let lastSessionDate = "last_session_date"
        static let bonusSessions = "bonus_sessions"
        static let sourceLanguage = "source_language"
        static let targetLanguage = "target_language"
        static let autoComplete = "auto_complete"
        static let autoCapitalize = "auto_capitalize"
        static let hapticFeedback = "haptic_feedback"
        static let appLanguage = "app_language"
        static let keyboardLayout = "keyboard_layout"
        static let hasCompletedOnboarding = "has_completed_onboarding"
        static let savedPhrases = "saved_phrases"
        static let keyboardTheme = "keyboard_theme"
        static let showNumberRow = "show_number_row"
        static let showPeriodKey = "show_period_key"
        static let keyTapPreview = "key_tap_preview"
        static let latinAlternatives = "latin_alternatives"
        static let toneStyle = "tone_style"
        static let primaryKeyboardLanguage = "primary_keyboard_language"
        static let clipboardHistory = "clipboard_history"
        static let clipboardOnboardingShown = "clipboard_onboarding_shown"
        static let compositionSessionHistory = "composition_session_history"
        static let keyboardFullAccessEnabled = "keyboard_full_access_enabled"
        static let appDarkMode = "app_dark_mode"
        static let keyboardAppearanceMode = "keyboard_appearance_mode"
        static let quickNotes = "quick_notes"
        static let toolbarItems = "toolbar_items"
        static let keyboardLayoutVariantsByLanguage = "keyboard_layout_variants_by_language"
        static let additionalKeyboardDefaultsBootstrapped = "additional_keyboard_defaults_bootstrapped"
        static let correctionLanguageMode = "correction_language_mode"
        static let correctionLanguage = "correction_language"
    }

    enum KeyboardAppearanceMode: String, CaseIterable {
        case automatic
        case light
        case dark
    }

    enum API {
        static let baseURL = "https://proxy-server-for-tk.vercel.app"
        static let translateEndpoint = "/api/translate"
        static let correctEndpoint = "/api/correct"
        static let timeout: TimeInterval = 10
    }

    enum LegalLinks {
        static let baseURL = "https://oneboard-support.vercel.app"
        static let privacy = "\(baseURL)/privacy"
        static let terms = "\(baseURL)/terms"
        static let faq = "\(baseURL)/faq"
        static let support = "\(baseURL)/support"
    }

    enum Limits {
        static let maxCharacters = 500
        static let warningCharacters = 150
        static let cacheMaxItems = 100
        static let sessionIdleTimeout: TimeInterval = 30
        static let quickNoteMaxCount = 50
        static let quickNoteMaxLength = 500
    }
}

enum KeyboardLanguage: String, CaseIterable {
    case english = "en"
    case korean = "ko"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case italian = "it"
    case russian = "ru"

    var displayName: String {
        switch self {
        case .english: return "English"
        case .korean: return "한국어"
        case .spanish: return "Español"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .italian: return "Italiano"
        case .russian: return "Русский"
        }
    }

    var shortLabel: String {
        switch self {
        case .english: return "A"
        case .korean: return "한"
        case .spanish: return "ES"
        case .french: return "FR"
        case .german: return "DE"
        case .italian: return "IT"
        case .russian: return "RU"
        }
    }

    var isLatinBased: Bool {
        self != .korean && self != .russian
    }
}

enum LatinLayoutVariant: String, CaseIterable {
    case qwerty
    case qwertz
    case azerty

    static func supportedVariants(for language: KeyboardLanguage) -> [LatinLayoutVariant] {
        switch language {
        case .spanish: return [.qwerty, .qwertz, .azerty]
        case .french: return [.azerty, .qwerty, .qwertz]
        case .german: return [.qwertz, .qwerty]
        case .italian: return [.qwerty, .qwertz]
        default: return []
        }
    }

    static func defaultVariant(for language: KeyboardLanguage) -> LatinLayoutVariant? {
        switch language {
        case .spanish: return .qwerty
        case .french: return .azerty
        case .german: return .qwertz
        case .italian: return .qwerty
        default: return nil
        }
    }
}
