import Foundation

/// Blackbox anomaly logger for rare blank-keyboard diagnosis.
/// - Ring buffer: 최근 N개 이벤트만 메모리 유지 (FIFO)
/// - Anomaly 감지 시에만 App Group 파일로 flush
/// - 정상 세션에서는 디스크 IO 없음
/// - Release에서도 동작하지만 극도로 경량 (메모리 ~8KB 이하)
final class BlackboxAnomalyLogger {

    static let shared = BlackboxAnomalyLogger()

    // MARK: - Configuration

    private let maxEntries = 150
    private let maxAnomalyFiles = 15

    // MARK: - State

    private let sessionID: String
    private var entries: [String] = []
    private var hasFlushed = false

    private init() {
        sessionID = "\(ProcessInfo.processInfo.processIdentifier)_\(Int(Date().timeIntervalSince1970))"
        entries.reserveCapacity(maxEntries)
    }

    // MARK: - Record

    /// 이벤트 기록 — 메모리 ring buffer에만 추가
    func record(_ event: String) {
        let ts = String(format: "%.2f", CFAbsoluteTimeGetCurrent().truncatingRemainder(dividingBy: 100000))
        let line = "[\(ts)] \(event)"
        if entries.count >= maxEntries {
            entries.removeFirst()
        }
        entries.append(line)
    }

    // MARK: - Anomaly Detection + Flush

    /// Anomaly 조건 체크 + 감지 시 파일 flush
    /// - Parameters:
    ///   - allKeyButtonsCount: 현재 key button 수
    ///   - containerSubviewsCount: keyboardContainer subview 수
    ///   - toolbarHidden: toolbar hidden 여부
    ///   - keyboardLayoutHidden: keyboardLayoutView hidden 여부
    ///   - snapshot: 추가 상태 key-value (mode, page, language 등)
    func checkAndFlushIfAnomaly(
        allKeyButtonsCount: Int,
        containerSubviewsCount: Int,
        toolbarHidden: Bool,
        keyboardLayoutHidden: Bool,
        snapshot: [String: String]
    ) {
        // Anomaly 조건: shell은 visible인데 key matrix가 비어 있음
        let isShellVisible = !toolbarHidden && !keyboardLayoutHidden
        let isKeyMatrixEmpty = allKeyButtonsCount == 0 || containerSubviewsCount == 0

        guard isShellVisible && isKeyMatrixEmpty else { return }

        // Anomaly 감지 — flush
        flushToFile(reason: "blankKeyboard", snapshot: snapshot)
    }

    /// 명시적 anomaly flush (disconnect 등)
    func flushForDisconnect(snapshot: [String: String]) {
        flushToFile(reason: "remoteDisconnect", snapshot: snapshot)
    }

    #if DEBUG
    /// 테스트용 강제 flush
    func debugForceFlush(snapshot: [String: String] = [:]) {
        flushToFile(reason: "debugForced", snapshot: snapshot)
    }
    #endif

    // MARK: - File Flush

    private func flushToFile(reason: String, snapshot: [String: String]) {
        guard !hasFlushed else { return }  // 세션당 1회만
        hasFlushed = true

        guard let dir = anomalyDir() else { return }

        let fileName = "anomaly_\(reason)_\(sessionID).log"
        let fileURL = dir.appendingPathComponent(fileName)

        var content = "===== ANOMALY: \(reason) =====\n"
        content += "sessionID: \(sessionID)\n"
        content += "pid: \(ProcessInfo.processInfo.processIdentifier)\n"
        content += "time: \(ISO8601DateFormatter().string(from: Date()))\n"
        content += "\n--- SNAPSHOT ---\n"
        for (key, value) in snapshot.sorted(by: { $0.key < $1.key }) {
            content += "\(key): \(value)\n"
        }
        content += "\n--- RING BUFFER (\(entries.count) entries) ---\n"
        for entry in entries {
            content += entry + "\n"
        }
        content += "\n===== END =====\n"

        try? content.write(to: fileURL, atomically: true, encoding: .utf8)

        // 오래된 파일 순환 삭제
        cleanupOldFiles(in: dir)

        #if DEBUG
        NSLog("[BlackboxAnomaly] flushed reason=%@ file=%@", reason, fileName)
        #endif
    }

    // MARK: - File Management

    private func anomalyDir() -> URL? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.translatorkeyboard.shared"
        ) else { return nil }

        let dir = container.appendingPathComponent("AnomalyLogs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanupOldFiles(in dir: URL) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.creationDateKey]
        ) else { return }

        let anomalyFiles = files
            .filter { $0.lastPathComponent.hasPrefix("anomaly_") }
            .sorted { a, b in
                let da = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return da < db
            }

        if anomalyFiles.count > maxAnomalyFiles {
            let toRemove = anomalyFiles.prefix(anomalyFiles.count - maxAnomalyFiles)
            for file in toRemove {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}
