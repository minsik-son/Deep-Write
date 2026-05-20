#if DEBUG
import Foundation

/// Reads the keyboard extension's latest startup trace from App Group
/// and prints the tail to the main app's Xcode console.
/// Called from SceneDelegate.sceneDidBecomeActive so that even when the
/// extension console is unavailable (grey/inactive), the trace is visible.
enum KeyboardStartupTraceReader {

    static func dumpLatestTraceToConsole() {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.translatorkeyboard.shared"
        ) else {
            NSLog("[KeyboardStartupTraceDump] ERROR: App Group container not found")
            return
        }

        let logPath = container
            .appendingPathComponent("DebugLogs", isDirectory: true)
            .appendingPathComponent("activation_trace_latest.log")
            .path

        guard FileManager.default.fileExists(atPath: logPath) else {
            NSLog("[KeyboardStartupTraceDump] path=%@ FILE_NOT_FOUND", logPath)
            return
        }

        // File metadata
        let attrs = try? FileManager.default.attributesOfItem(atPath: logPath)
        let fileSize = (attrs?[.size] as? UInt64) ?? 0
        let modDate = (attrs?[.modificationDate] as? Date)?.description ?? "unknown"

        NSLog("[KeyboardStartupTraceDump] path=%@", logPath)
        NSLog("[KeyboardStartupTraceDump] size=%llu bytes modified=%@", fileSize, modDate)

        guard fileSize > 0 else {
            NSLog("[KeyboardStartupTraceDump] EMPTY_FILE")
            return
        }

        // Read last 120 lines
        guard let data = FileManager.default.contents(atPath: logPath),
              let content = String(data: data, encoding: .utf8) else {
            NSLog("[KeyboardStartupTraceDump] ERROR: cannot read file")
            return
        }

        let lines = content.components(separatedBy: "\n")
        let tailCount = min(lines.count, 120)
        let tail = lines.suffix(tailCount)

        NSLog("[KeyboardStartupTraceDump] tail-start (last %d of %d lines)", tailCount, lines.count)
        for line in tail where !line.isEmpty {
            NSLog("[KeyboardStartupTraceDump] %@", line)
        }
        NSLog("[KeyboardStartupTraceDump] tail-end")
    }
}
#endif
