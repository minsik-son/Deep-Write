#if DEBUG
import Foundation

/// Logs App Group key metadata to ActivationTraceLogger at viewDidLoad.
/// Only records type/size/non-sensitive enum values — never user text content.
enum KeyboardStartupSettingsSnapshot {

    static func record() {
        let logger = ActivationTraceLogger.shared
        guard let defaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier) else {
            logger.mark("appGroupSnapshot", details: "FAILED defaults=nil")
            return
        }

        let configKeys: [String] = [
            AppConstants.UserDefaultsKeys.keyboardTheme,
            AppConstants.UserDefaultsKeys.subscriptionTier,
            AppConstants.UserDefaultsKeys.subscriptionExpiry,
            AppConstants.UserDefaultsKeys.keyboardLayout,
            AppConstants.UserDefaultsKeys.primaryKeyboardLanguage,
            AppConstants.UserDefaultsKeys.sourceLanguage,
            AppConstants.UserDefaultsKeys.targetLanguage,
            AppConstants.UserDefaultsKeys.showNumberRow,
            AppConstants.UserDefaultsKeys.showPeriodKey,
            AppConstants.UserDefaultsKeys.keyTapPreview,
            AppConstants.UserDefaultsKeys.latinAlternatives,
            AppConstants.UserDefaultsKeys.keyboardAppearanceMode,
            AppConstants.UserDefaultsKeys.additionalKeyboardDefaultsBootstrapped,
        ]

        for key in configKeys {
            let obj = defaults.object(forKey: key)
            if let obj = obj {
                let typeName = String(describing: type(of: obj))
                let desc: String
                if let s = obj as? String {
                    desc = "type=String bytes=\(s.utf8.count) value=\(s)"
                } else if let n = obj as? NSNumber {
                    desc = "type=Number value=\(n)"
                } else if let d = obj as? Data {
                    desc = "type=Data bytes=\(d.count)"
                } else if let b = obj as? Bool {
                    desc = "type=Bool value=\(b)"
                } else {
                    desc = "type=\(typeName)"
                }
                logger.log("[KeyboardStartupTrace] phase=appGroupSnapshot key=\(key) \(desc)")
            } else {
                logger.log("[KeyboardStartupTrace] phase=appGroupSnapshot key=\(key) value=nil")
            }
        }

        // User data keys — count/size only, no text content
        let dataKeys: [(String, String)] = [
            (AppConstants.UserDefaultsKeys.toolbarItems, "toolbarItems"),
            (AppConstants.UserDefaultsKeys.keyboardLayoutVariantsByLanguage, "layoutVariants"),
        ]
        for (key, label) in dataKeys {
            let obj = defaults.object(forKey: key)
            if let data = obj as? Data {
                logger.log("[KeyboardStartupTrace] phase=appGroupSnapshot key=\(label) type=Data bytes=\(data.count)")
            } else if let arr = obj as? [Any] {
                logger.log("[KeyboardStartupTrace] phase=appGroupSnapshot key=\(label) type=Array count=\(arr.count)")
            } else if obj != nil {
                logger.log("[KeyboardStartupTrace] phase=appGroupSnapshot key=\(label) type=\(String(describing: type(of: obj!)))")
            } else {
                logger.log("[KeyboardStartupTrace] phase=appGroupSnapshot key=\(label) value=nil")
            }
        }

        // Clipboard / saved phrases / quick notes — count only
        if let clipData = defaults.object(forKey: AppConstants.UserDefaultsKeys.clipboardHistory) as? Data {
            logger.log("[KeyboardStartupTrace] phase=appGroupSnapshot key=clipboardHistory type=Data bytes=\(clipData.count)")
        } else {
            logger.log("[KeyboardStartupTrace] phase=appGroupSnapshot key=clipboardHistory value=nil")
        }

        if let phrasesData = defaults.object(forKey: AppConstants.UserDefaultsKeys.savedPhrases) as? Data {
            logger.log("[KeyboardStartupTrace] phase=appGroupSnapshot key=savedPhrases type=Data bytes=\(phrasesData.count)")
        } else {
            logger.log("[KeyboardStartupTrace] phase=appGroupSnapshot key=savedPhrases value=nil")
        }

        if let notesData = defaults.object(forKey: AppConstants.UserDefaultsKeys.quickNotes) as? Data {
            logger.log("[KeyboardStartupTrace] phase=appGroupSnapshot key=quickNotes type=Data bytes=\(notesData.count)")
        } else {
            logger.log("[KeyboardStartupTrace] phase=appGroupSnapshot key=quickNotes value=nil")
        }

        logger.mark("appGroupSnapshot.end")
    }
}
#endif
