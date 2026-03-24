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
        static let quickNotes = "quick_notes"
    }

    enum API {
        static let baseURL = "https://proxy-server-for-tk.vercel.app"
        static let translateEndpoint = "/api/translate"
        static let correctEndpoint = "/api/correct"
        static let timeout: TimeInterval = 10
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
