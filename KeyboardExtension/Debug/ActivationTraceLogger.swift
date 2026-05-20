#if DEBUG
import Foundation
import QuartzCore

/// Debug-only file logger for activation trace.
/// Line-by-line append + immediate flush. No in-memory accumulation.
/// Max file size ~256KB with tail-preserve on overflow.
final class ActivationTraceLogger {

    static let shared = ActivationTraceLogger()

    /// Process-wide reference time for delta computation.
    /// Set once at first access; survives across VC lifecycles within the same process.
    static let processStartTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()

    private let fileHandle: FileHandle?
    let filePath: String
    private let maxFileSize: UInt64 = 256 * 1024  // 256KB
    private let pid = ProcessInfo.processInfo.processIdentifier

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

        // Check size — tail-preserve if over limit
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let size = attrs[.size] as? UInt64,
           size > maxFileSize {
            // Keep last 128KB
            if let data = FileManager.default.contents(atPath: path) {
                let keepBytes = min(data.count, 128 * 1024)
                let tail = data.suffix(keepBytes)
                let header = "===== LOG TRUNCATED (kept last \(keepBytes) bytes) =====\n".data(using: .utf8) ?? Data()
                try? (header + tail).write(to: URL(fileURLWithPath: path))
            }
        }

        self.fileHandle = FileHandle(forWritingAtPath: path)
        self.fileHandle?.seekToEndOfFile()

        // Print path to console for discoverability
        NSLog("[ActivationTrace] fileLogPath=%@", path)
    }

    /// Write a session header
    func writeSessionHeader() {
        let ts = ISO8601DateFormatter().string(from: Date())
        writeLine("===== Activation Session START pid=\(pid) time=\(ts) =====")
    }

    /// Structured phase marker with timestamp and delta.
    /// - Parameters:
    ///   - phase: e.g. "viewDidLoad.start", "KLV.firstNonZeroBounds"
    ///   - details: optional short diagnostic info (NO user text/clipboard/AI body)
    func mark(_ phase: String, details: String = "") {
        let t = CACurrentMediaTime()
        let dt = (CFAbsoluteTimeGetCurrent() - Self.processStartTime) * 1000
        let suffix = details.isEmpty ? "" : " details=\(details)"
        writeLine(String(format: "[KeyboardStartupTrace] t=%.3f pid=%d phase=%@ dt=%.1fms%@",
                         t, pid, phase, dt, suffix))
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
            handle.synchronizeFile()
        }
    }

    deinit {
        fileHandle?.closeFile()
    }
}
#endif
