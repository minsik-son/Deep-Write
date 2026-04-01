import Foundation

final class DictationSharedStore {

    private let fileManager = FileManager.default

    private var containerURL: URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: AppConstants.appGroupIdentifier)
    }

    private var commandFileURL: URL? {
        containerURL?.appendingPathComponent(DictationConstants.SharedFiles.command)
    }

    private var stateFileURL: URL? {
        containerURL?.appendingPathComponent(DictationConstants.SharedFiles.state)
    }

    // MARK: - Write

    func writeCommand(_ payload: DictationCommandPayload) throws {
        guard let url = commandFileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        try data.write(to: url, options: .atomic)
        hardenFile(at: url)
        DarwinNotificationBridge.shared.post(DictationConstants.Notifications.commandChanged)
    }

    func writeState(_ payload: DictationStatePayload) throws {
        guard let url = stateFileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        try data.write(to: url, options: .atomic)
        hardenFile(at: url)
        DarwinNotificationBridge.shared.post(DictationConstants.Notifications.stateChanged)
    }

    // MARK: - Read

    func readCommand() -> DictationCommandPayload? {
        return autoreleasepool {
            guard let url = commandFileURL else { return nil }
            guard let data = try? Data(contentsOf: url) else { return nil }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try? decoder.decode(DictationCommandPayload.self, from: data)
        }
    }

    func readState() -> DictationStatePayload? {
        return autoreleasepool {
            guard let url = stateFileURL else { return nil }
            guard let data = try? Data(contentsOf: url) else { return nil }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try? decoder.decode(DictationStatePayload.self, from: data)
        }
    }

    // MARK: - Clear

    func clearCommand() {
        guard let url = commandFileURL else { return }
        try? fileManager.removeItem(at: url)
    }

    func clearState() {
        guard let url = stateFileURL else { return }
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

    private var killFileURL: URL? {
        containerURL?.appendingPathComponent(DictationConstants.SharedFiles.kill)
    }

    func writeKill(_ payload: DictationKillSignal) throws {
        guard let url = killFileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        try data.write(to: url, options: .atomic)
        hardenFile(at: url)
        DarwinNotificationBridge.shared.post(DictationConstants.Notifications.killChanged)
    }

    func readKill() -> DictationKillSignal? {
        return autoreleasepool {
            guard let url = killFileURL else { return nil }
            guard let data = try? Data(contentsOf: url) else { return nil }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try? decoder.decode(DictationKillSignal.self, from: data)
        }
    }

    func clearKill() {
        guard let url = killFileURL else { return }
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
