import Foundation

enum AdditionalKeyboardBootstrap {
    static func runOnceIfNeeded() {
        let key = AppConstants.UserDefaultsKeys.additionalKeyboardDefaultsBootstrapped
        guard !AppGroupManager.shared.bool(forKey: key) else { return }

        // Mark as done regardless of language
        AppGroupManager.shared.set(true, forKey: key)

        // Only apply defaults for Korean system language
        let preferred = Locale.preferredLanguages.first ?? ""
        guard preferred.hasPrefix("ko") else { return }

        // Don't overwrite if user already set a value
        let enabledKey = "additional_keyboard_language_enabled"
        let langKey = AppConstants.UserDefaultsKeys.primaryKeyboardLanguage

        if AppGroupManager.shared.string(forKey: langKey) == nil {
            AppGroupManager.shared.set(true, forKey: enabledKey)
            AppGroupManager.shared.set("ko", forKey: langKey)
        }
    }
}
