import Foundation

enum DictationCommandAction: String, Codable {
    case start
    case pause
    case resume
    case stop
    case cancel
    case clear
    case deleteLastWord
}

enum DictationPhase: String, Codable {
    case idle
    case launchingApp
    case preparing
    case recording
    case paused
    case finalizing
    case completed
    case error
}

struct DictationCommandPayload: Codable {
    let sessionId: String
    let action: DictationCommandAction
    let locale: String
    let sourceAppBundleId: String?
    let requestedAt: Date
}

struct DictationStatePayload: Codable {
    let sessionId: String
    let phase: DictationPhase
    let locale: String
    let partialText: String
    let finalText: String?
    let errorMessage: String?
    let errorCode: Int?
    let audioLevel: Float?
    let version: UInt64
    let updatedAt: Date
}

struct DictationKillSignal: Codable {
    let sessionId: String
    let reason: String  // "user_stop", "user_cancel"
    let timestampAt: Date
}
