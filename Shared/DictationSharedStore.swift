import Foundation
import OSLog

// DEBUG TRACE: VoiceRecognition investigation
private let storeLog = Logger(
    subsystem: "com.translatorkeyboard.app.voice",
    category: "store"
)

enum DictationSharedStoreError: LocalizedError {
    case containerUnavailable(target: String)

    var errorDescription: String? {
        switch self {
        case .containerUnavailable(let target):
            return "App group container unavailable for \(target)"
        }
    }
}

final class DictationSharedStore {

    private let fileManager = FileManager.default

    private var containerURL: URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: AppConstants.appGroupIdentifier)
    }

    private func resolveURL(file: String, target: String) throws -> URL {
        guard let url = containerURL?.appendingPathComponent(file) else {
            storeLog.error("event=containerUnavailable target=\(target, privacy: .public)")
            throw DictationSharedStoreError.containerUnavailable(target: target)
        }
        return url
    }

    // MARK: - Write

    func writeCommand(_ payload: DictationCommandPayload) throws {
        let url = try resolveURL(file: DictationConstants.SharedFiles.command, target: "command")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        try data.write(to: url, options: .atomic)
        hardenFile(at: url)
        // DEBUG TRACE: VoiceRecognition investigation
        storeLog.debug("event=writeCommand action=\(String(describing: payload.action), privacy: .public) sid=\(payload.sessionId.prefix(8), privacy: .public)")
        DarwinNotificationBridge.shared.post(DictationConstants.Notifications.commandChanged)
    }

    func writeState(_ payload: DictationStatePayload) throws {
        let url = try resolveURL(file: DictationConstants.SharedFiles.state, target: "state")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        try data.write(to: url, options: .atomic)
        hardenFile(at: url)
        // DEBUG TRACE: VoiceRecognition investigation
        storeLog.debug("event=writeState phase=\(String(describing: payload.phase), privacy: .public) ver=\(payload.version, privacy: .public) sid=\(payload.sessionId.prefix(8), privacy: .public)")
        DarwinNotificationBridge.shared.post(DictationConstants.Notifications.stateChanged)
    }

    // MARK: - Read

    func readCommand() -> DictationCommandPayload? {
        return autoreleasepool {
            guard let url = containerURL?.appendingPathComponent(DictationConstants.SharedFiles.command) else { return nil }
            guard let data = try? Data(contentsOf: url) else { return nil }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try? decoder.decode(DictationCommandPayload.self, from: data)
        }
    }

    func readState() -> DictationStatePayload? {
        return autoreleasepool {
            guard let url = containerURL?.appendingPathComponent(DictationConstants.SharedFiles.state) else { return nil }
            guard let data = try? Data(contentsOf: url) else { return nil }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try? decoder.decode(DictationStatePayload.self, from: data)
        }
    }

    // MARK: - Clear

    func clearCommand() {
        // DEBUG TRACE: VoiceRecognition investigation
        storeLog.debug("event=clearCommand")
        guard let url = containerURL?.appendingPathComponent(DictationConstants.SharedFiles.command) else { return }
        try? fileManager.removeItem(at: url)
    }

    func clearState() {
        // DEBUG TRACE: VoiceRecognition investigation
        storeLog.debug("event=clearState")
        guard let url = containerURL?.appendingPathComponent(DictationConstants.SharedFiles.state) else { return }
        try? fileManager.removeItem(at: url)
    }

    func clearAllIfStale(now: Date = Date()) {
        if let state = readState() {
            let age = now.timeIntervalSince(state.updatedAt)
            if age > DictationConstants.Limits.stalePayloadTTL {
                clearState()
            }
        }

        if let command = readCommand() {
            let age = now.timeIntervalSince(command.requestedAt)
            if age > DictationConstants.Limits.stalePayloadTTL {
                clearCommand()
            }
        }
    }

    // MARK: - Kill Signal

    func writeKill(_ payload: DictationKillSignal) throws {
        let url = try resolveURL(file: DictationConstants.SharedFiles.kill, target: "kill")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        try data.write(to: url, options: .atomic)
        hardenFile(at: url)
        // DEBUG TRACE: VoiceRecognition investigation
        storeLog.debug("event=writeKill sid=\(payload.sessionId.prefix(8), privacy: .public) reason=\(payload.reason, privacy: .public)")
        DarwinNotificationBridge.shared.post(DictationConstants.Notifications.killChanged)
    }

    func readKill() -> DictationKillSignal? {
        return autoreleasepool {
            guard let url = containerURL?.appendingPathComponent(DictationConstants.SharedFiles.kill) else { return nil }
            guard let data = try? Data(contentsOf: url) else { return nil }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try? decoder.decode(DictationKillSignal.self, from: data)
        }
    }

    func clearKill() {
        // DEBUG TRACE: VoiceRecognition investigation
        storeLog.debug("event=clearKill")
        guard let url = containerURL?.appendingPathComponent(DictationConstants.SharedFiles.kill) else { return }
        try? fileManager.removeItem(at: url)
    }

    // MARK: - File Hardening

    private func hardenFile(at url: URL) {
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableURL = url
        try? mutableURL.setResourceValues(resourceValues)
        try? fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }
}
