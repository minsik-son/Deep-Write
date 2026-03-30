import Foundation

protocol DictationServiceDelegate: AnyObject {
    func dictationService(_ service: DictationService, didChangePhase phase: DictationPhase)
    func dictationService(_ service: DictationService, didUpdatePartial text: String)
    func dictationService(_ service: DictationService, didFinishWith finalText: String)
    func dictationService(_ service: DictationService, didFailWith message: String)
}

final class DictationService: SpeechRecognitionManagerDelegate {

    weak var delegate: DictationServiceDelegate?

    private let speechManager = SpeechRecognitionManager()
    private let sharedStore = DictationSharedStore()
    private var heartbeatTimer: Timer?
    private var debounceTimer: Timer?

    // Transcript state for seamless restart
    private var transcriptState = AppTranscriptState()
    private var currentLocale: String = "en-US"

    private(set) var isActive: Bool = false

    // MARK: - Session Start

    func startSession(sessionId: String, locale: String) {
        guard !isActive else { return }

        currentLocale = locale
        transcriptState = AppTranscriptState(sessionId: sessionId)

        guard speechManager.setLocale(locale) else {
            writeError("Speech recognition not available for \(locale)")
            return
        }

        isActive = true
        sharedStore.clearAllIfStale()

        writeState(phase: .preparing, partialText: "")
        delegate?.dictationService(self, didChangePhase: .preparing)

        do {
            try speechManager.start()
            speechManager.delegate = self
            writeState(phase: .recording, partialText: "")
            delegate?.dictationService(self, didChangePhase: .recording)
            startHeartbeat()
        } catch {
            writeError(error.localizedDescription)
        }
    }

    // MARK: - Stop / Cancel

    func stopSession() {
        guard isActive else { return }
        writeState(phase: .finalizing, partialText: currentAbsoluteText)
        speechManager.stop()
        // Final will be delivered via delegate
    }

    func cancelSession() {
        guard isActive else { return }
        speechManager.cancel()
        writeState(phase: .idle, partialText: "")
        cleanup()
        delegate?.dictationService(self, didChangePhase: .idle)
    }

    // MARK: - Pause / Resume

    func pauseSession() {
        guard isActive else { return }
        speechManager.stop()
        writeState(phase: .paused, partialText: currentAbsoluteText)
        delegate?.dictationService(self, didChangePhase: .paused)
    }

    func resumeSession() {
        guard isActive else { return }
        // Commit current partial before resuming
        transcriptState.committedPrefix = currentAbsoluteText
        transcriptState.currentTaskPartial = ""

        do {
            try speechManager.start()
            speechManager.delegate = self
            writeState(phase: .recording, partialText: currentAbsoluteText)
            delegate?.dictationService(self, didChangePhase: .recording)
        } catch {
            writeError(error.localizedDescription)
        }
    }

    // MARK: - SpeechRecognitionManagerDelegate

    func speechRecognition(_ manager: SpeechRecognitionManager, didReceivePartial text: String) {
        transcriptState.currentTaskPartial = text
        debouncedWritePartial()
    }

    func speechRecognition(_ manager: SpeechRecognitionManager, didReceiveFinal text: String) {
        transcriptState.currentTaskPartial = text
        let finalText = currentAbsoluteText

        transcriptState.version += 1
        let payload = DictationStatePayload(
            sessionId: transcriptState.sessionId,
            phase: .completed,
            locale: currentLocale,
            partialText: finalText,
            finalText: finalText,
            errorMessage: nil,
            errorCode: nil,
            audioLevel: nil,
            version: transcriptState.version,
            updatedAt: Date()
        )
        try? sharedStore.writeState(payload)

        cleanup()
        delegate?.dictationService(self, didFinishWith: finalText)
        delegate?.dictationService(self, didChangePhase: .completed)
    }

    func speechRecognition(_ manager: SpeechRecognitionManager, didFailWith error: Error) {
        writeError(error.localizedDescription)
    }

    func speechRecognitionDidReachTimeLimit(_ manager: SpeechRecognitionManager) {
        performSeamlessRestart()
    }

    // MARK: - Seamless Restart

    private func performSeamlessRestart() {
        // Commit current partial
        transcriptState.committedPrefix = currentAbsoluteText
        transcriptState.currentTaskPartial = ""

        speechManager.stop()

        do {
            try speechManager.start()
            speechManager.delegate = self
            // Keep phase as recording — invisible to extension
        } catch {
            writeError(error.localizedDescription)
        }
    }

    // MARK: - Absolute Text

    private var currentAbsoluteText: String {
        let prefix = transcriptState.committedPrefix
        let partial = transcriptState.currentTaskPartial

        guard !partial.isEmpty else { return prefix }
        guard !prefix.isEmpty else { return partial }

        let langPrefix = String(currentLocale.prefix(2))
        if DictationConstants.noSpaceLocales.contains(langPrefix) {
            return prefix + partial
        }
        return prefix + " " + partial
    }

    // MARK: - Write Helpers

    private func writeState(phase: DictationPhase, partialText: String) {
        transcriptState.version += 1
        let payload = DictationStatePayload(
            sessionId: transcriptState.sessionId,
            phase: phase,
            locale: currentLocale,
            partialText: partialText,
            finalText: nil,
            errorMessage: nil,
            errorCode: nil,
            audioLevel: nil,
            version: transcriptState.version,
            updatedAt: Date()
        )
        try? sharedStore.writeState(payload)
    }

    private func writeError(_ message: String) {
        transcriptState.version += 1
        let payload = DictationStatePayload(
            sessionId: transcriptState.sessionId,
            phase: .error,
            locale: currentLocale,
            partialText: currentAbsoluteText,
            finalText: nil,
            errorMessage: message,
            errorCode: nil,
            audioLevel: nil,
            version: transcriptState.version,
            updatedAt: Date()
        )
        try? sharedStore.writeState(payload)
        cleanup()
        delegate?.dictationService(self, didFailWith: message)
        delegate?.dictationService(self, didChangePhase: .error)
    }

    private func debouncedWritePartial() {
        debounceTimer?.invalidate()
        let interval = Double(DictationConstants.Limits.partialDebounceMs) / 1000.0
        debounceTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            guard let self = self, self.isActive else { return }
            self.writeState(phase: .recording, partialText: self.currentAbsoluteText)

            // Check time limit for seamless restart
            if self.speechManager.isNearTimeLimit {
                self.performSeamlessRestart()
            }
        }
    }

    // MARK: - Heartbeat

    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isActive else { return }
            AppGroupManager.shared.set(Date(), forKey: DictationConstants.DefaultsKeys.dictationHeartbeatAt)
            DarwinNotificationBridge.shared.post(DictationConstants.Notifications.heartbeatChanged)
        }
    }

    // MARK: - Cleanup

    private func cleanup() {
        isActive = false
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        debounceTimer?.invalidate()
        debounceTimer = nil
        speechManager.delegate = nil
    }
}

// MARK: - Transcript State

struct AppTranscriptState {
    var sessionId: String = ""
    var committedPrefix: String = ""
    var currentTaskPartial: String = ""
    var version: UInt64 = 0
}
