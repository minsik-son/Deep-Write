import Foundation

enum DictationConstants {
    enum Notifications {
        static let commandChanged = "com.translatorkeyboard.dictation.command"
        static let stateChanged = "com.translatorkeyboard.dictation.state"
        static let heartbeatChanged = "com.translatorkeyboard.dictation.heartbeat"
        static let killChanged = "com.translatorkeyboard.dictation.kill"
    }

    enum DefaultsKeys {
        static let dictationEnabled = "dictation_enabled"
        static let dictationPreferredLocale = "dictation_preferred_locale"
        static let dictationHeartbeatAt = "dictation_heartbeat_at"
    }

    enum SharedFiles {
        static let command = "dictation_command.json"
        static let state = "dictation_state.json"
        static let kill = "dictation_kill.json"
    }

    enum Limits {
        static let maxRecordingSeconds: TimeInterval = 60
        static let seamlessRestartThreshold: TimeInterval = 55
        static let silenceTimeout: TimeInterval = 60
        static let partialDebounceMs = 120
        static let extensionPartialThrottleMs = 100
        static let pollingInterval: TimeInterval = 0.5
        static let warmHeartbeatTTL: TimeInterval = 10
        static let coldStartAckTimeout: TimeInterval = 5.0
        static let warmStartAckTimeout: TimeInterval = 1.5
        static let watchdogTimeout: TimeInterval = 300
        static let returnGraceTimeout: TimeInterval = 60.0
        static let errorAutoResetDelay: TimeInterval = 3.0
        static let stalePayloadTTL: TimeInterval = 120
        static let killSignalTTL: TimeInterval = 30
    }

    static let supportedLocales: [String] = [
        "en-US", "ko-KR", "ja-JP", "zh-CN", "es-ES",
        "fr-FR", "de-DE", "it-IT", "ru-RU", "pt-BR",
        "ar-SA", "hi-IN", "th-TH", "vi-VN", "id-ID"
    ]

    static let noSpaceLocales: Set<String> = [
        "ja", "zh", "th"
    ]

    static let rtlLanguageCodes: Set<String> = [
        "ar"
    ]
}
