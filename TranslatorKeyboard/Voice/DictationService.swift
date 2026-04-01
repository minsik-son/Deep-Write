import Foundation

protocol DictationServiceDelegate: AnyObject {
    func dictationService(_ service: DictationService, didChangePhase phase: DictationPhase)
    func dictationService(_ service: DictationService, didUpdatePartial text: String)
    func dictationService(_ service: DictationService, didFinishWith finalText: String)
    func dictationService(_ service: DictationService, didFailWith message: String)
}

// Control intent guard — pause 중 callback이 fatal로 전파되지 않게 함
private enum ControlIntent {
    case none
    case pausing
    case stopping
    case canceling
    case restarting
}

final class DictationService: SpeechRecognitionManagerDelegate {

    weak var delegate: DictationServiceDelegate?

    private let speechManager = SpeechRecognitionManager()
    private let sharedStore = DictationSharedStore()
    private var heartbeatTimer: Timer?
    private var debounceTimer: Timer?

    private var transcriptState = AppTranscriptState()
    private var currentLocale: String = "en-US"
    private var controlIntent: ControlIntent = .none

    private(set) var isActive: Bool = false

    /// Runtime이 현재 transcript를 읽을 수 있도록 public accessor
    var currentText: String { currentAbsoluteText }

    // MARK: - Session Start

    func startSession(sessionId: String, locale: String) {
        guard !isActive else { return }

        currentLocale = locale
        transcriptState = AppTranscriptState(sessionId: sessionId)
        controlIntent = .none

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
            writeHeartbeatNow()  // 즉시 첫 heartbeat write
            startHeartbeat()
        } catch {
            writeError(error.localizedDescription)
        }
    }

    // MARK: - Force Stop (deterministic — runtime이 호출)

    func forceStop() {
        controlIntent = .stopping
        speechManager.stop()
        cleanup()
    }

    // MARK: - Pause / Resume

    func pauseSession() {
        guard isActive else { return }
        controlIntent = .pausing
        speechManager.pause()
        writeState(phase: .paused, partialText: currentAbsoluteText)
        delegate?.dictationService(self, didChangePhase: .paused)
        controlIntent = .none
    }

    func resumeSession() {
        guard isActive else { return }
        controlIntent = .none

        do {
            try speechManager.resumeAfterPause()
            writeState(phase: .recording, partialText: currentAbsoluteText)
            writeHeartbeatNow()  // resume 직후 heartbeat 즉시 갱신
            delegate?.dictationService(self, didChangePhase: .recording)
        } catch {
            // Fallback: full restart
            transcriptState.committedPrefix = currentAbsoluteText
            transcriptState.currentTaskPartial = ""
            speechManager.stop()
            do {
                try speechManager.start()
                speechManager.delegate = self
                writeState(phase: .recording, partialText: currentAbsoluteText)
                delegate?.dictationService(self, didChangePhase: .recording)
            } catch {
                writeError(error.localizedDescription)
            }
        }
    }

    // MARK: - Clear Transcript

    func clearTranscript() {
        guard isActive else { return }
        transcriptState.committedPrefix = ""
        transcriptState.currentTaskPartial = ""
        writeState(phase: .recording, partialText: "")
    }

    // MARK: - Stop (동기 cleanup + ControlIntent)

    func stopSession() {
        guard isActive else { return }
        controlIntent = .stopping
        writeState(phase: .finalizing, partialText: currentAbsoluteText)
        speechManager.stop()
        cleanup()
    }

    func cancelSession() {
        controlIntent = .canceling
        speechManager.cancel()
        writeState(phase: .idle, partialText: "")
        cleanup()
        delegate?.dictationService(self, didChangePhase: .idle)
    }

    // MARK: - SpeechRecognitionManagerDelegate

    func speechRecognition(_ manager: SpeechRecognitionManager, didReceivePartial text: String) {
        // Intent guard: stopping/canceling 중이면 무시
        guard controlIntent == .none else { return }
        transcriptState.currentTaskPartial = text
        debouncedWritePartial()
    }

    func speechRecognition(_ manager: SpeechRecognitionManager, didReceiveFinal text: String) {
        guard controlIntent == .none else { return }
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
        // 1차 방어선: pausing/stopping/canceling 중이면 전파 안 함
        guard controlIntent == .none else { return }
        writeError(error.localizedDescription)
    }

    func speechRecognitionDidReachTimeLimit(_ manager: SpeechRecognitionManager) {
        guard controlIntent == .none else { return }
        performSeamlessRestart()
    }

    // MARK: - Seamless Restart

    private func performSeamlessRestart() {
        controlIntent = .restarting
        transcriptState.committedPrefix = currentAbsoluteText
        transcriptState.currentTaskPartial = ""
        speechManager.stop()
        do {
            try speechManager.start()
            speechManager.delegate = self
            controlIntent = .none
        } catch {
            controlIntent = .none
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
            guard let self = self, self.isActive, self.controlIntent == .none else { return }
            self.writeState(phase: .recording, partialText: self.currentAbsoluteText)
            self.writeHeartbeatNow()  // partial write 시 heartbeat 갱신
            if self.speechManager.isNearTimeLimit {
                self.performSeamlessRestart()
            }
        }
    }

    // MARK: - Heartbeat

    private func writeHeartbeatNow() {
        AppGroupManager.shared.set(Date(), forKey: DictationConstants.DefaultsKeys.dictationHeartbeatAt)
        DarwinNotificationBridge.shared.post(DictationConstants.Notifications.heartbeatChanged)
    }

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
