#if DEBUG
import Foundation

/// Debug-only file logger for activation trace.
/// Line-by-line append + immediate flush. No in-memory accumulation.
/// Max file size ~256KB with truncate-on-overflow.
final class ActivationTraceLogger {

    static let shared = ActivationTraceLogger()

    private let fileHandle: FileHandle?
    private let filePath: String
    private let maxFileSize: UInt64 = 256 * 1024  // 256KB

    private init() {
        // App group shared container — accessible from both main app and extension
        let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.translatorkeyboard.shared"
        )
        let logDir = container?.appendingPathComponent("DebugLogs", isDirectory: true)

        if let logDir = logDir {
            try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        }

        let path = logDir?.appendingPathComponent("activation_trace_latest.log").path ?? ""
        self.filePath = path

        // Create file if needed
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }

        // Check size — truncate if over limit
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let size = attrs[.size] as? UInt64,
           size > maxFileSize {
            // Truncate: overwrite with empty
            FileManager.default.createFile(atPath: path, contents: nil)
        }

        self.fileHandle = FileHandle(forWritingAtPath: path)
        self.fileHandle?.seekToEndOfFile()

        // Print path to console for discoverability
        NSLog("[ActivationTrace] fileLogPath=%@", path)
    }

    /// Write a session header
    func writeSessionHeader() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let ts = ISO8601DateFormatter().string(from: Date())
        writeLine("===== Activation Session START pid=\(pid) time=\(ts) =====")
    }

    /// Append a single log line (immediate flush)
    func log(_ message: String) {
        writeLine(message)
    }

    private func writeLine(_ line: String) {
        guard let handle = fileHandle else { return }
        let entry = line + "\n"
        if let data = entry.data(using: .utf8) {
            handle.write(data)
            // Immediate flush — 로그 유실 방지
            handle.synchronizeFile()
        }
    }

    deinit {
        fileHandle?.closeFile()
    }
}
#endif
