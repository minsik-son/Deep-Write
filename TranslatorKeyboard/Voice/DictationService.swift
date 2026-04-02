import Foundation
import OSLog

// DEBUG TRACE: VoiceRecognition investigation
private let serviceLog = Logger(
    subsystem: "com.translatorkeyboard.app.voice",
    category: "service"
)

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
    private var hasReceivedSpeech: Bool = false

    private(set) var isActive: Bool = false

    /// Runtime이 현재 transcript를 읽을 수 있도록 public accessor
    var currentText: String { currentAbsoluteText }

    // MARK: - Session Start

    func startSession(sessionId: String, locale: String) {
        guard !isActive else { return }

        // DEBUG TRACE: VoiceRecognition investigation
        serviceLog.debug("event=startSession sid=\(sessionId.prefix(8), privacy: .public) locale=\(locale, privacy: .public)")

        currentLocale = locale
        transcriptState = AppTranscriptState(sessionId: sessionId)
        controlIntent = .none
        hasReceivedSpeech = false

        guard speechManager.setLocale(locale) else {
            writeError("Speech recognition not available for \(locale)")
            return
        }

        isActive = true
        sharedStore.clearAllIfStale()

        writeState(phase: .preparing, partialText: "")
        delegate?.dictationService(self, didChangePhase: .preparing)

        do {
            speechManager.delegate = self
            // DEBUG TRACE: VoiceRecognition investigation
            serviceLog.debug("event=delegate_bound sid=\(sessionId.prefix(8), privacy: .public)")
            try speechManager.start()
            writeState(phase: .recording, partialText: "")
            delegate?.dictationService(self, didChangePhase: .recording)
            writeHeartbeatNow(source: "initial")
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
        // DEBUG TRACE: VoiceRecognition investigation
        serviceLog.debug("event=pauseSession sid=\(self.transcriptState.sessionId.prefix(8), privacy: .public)")
        controlIntent = .pausing
        speechManager.pause()
        writeState(phase: .paused, partialText: currentAbsoluteText)
        delegate?.dictationService(self, didChangePhase: .paused)
        controlIntent = .none
    }

    func resumeSession() {
        guard isActive else { return }
        // DEBUG TRACE: VoiceRecognition investigation
        serviceLog.debug("event=resumeSession sid=\(self.transcriptState.sessionId.prefix(8), privacy: .public)")
        controlIntent = .none

        do {
            try speechManager.resumeAfterPause()
            writeState(phase: .recording, partialText: currentAbsoluteText)
            writeHeartbeatNow(source: "resume")
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
        hasReceivedSpeech = false
        writeState(phase: .recording, partialText: "")
    }

    // MARK: - Delete Last Character

    func deleteLastCharacter() {
        guard isActive else { return }

        let absoluteText = currentAbsoluteText
        guard !absoluteText.isEmpty else { return }

        // 1. 현재 absolute text에서 마지막 Character 제거
        let editedText = String(absoluteText.dropLast())

        // 2. 편집된 텍스트를 새 base로 승격 — partial 초기화
        transcriptState.committedPrefix = editedText
        transcriptState.currentTaskPartial = ""

        // DEBUG TRACE
        serviceLog.debug("event=deleteLastCharacter sid=\(self.transcriptState.sessionId.prefix(8), privacy: .public) remaining=\(editedText.count, privacy: .public)")

        // 3. recognizer restart — 다음 partial이 편집된 base 위에 쌓이도록
        controlIntent = .restarting
        speechManager.stop()
        do {
            try speechManager.start()
            speechManager.delegate = self
            controlIntent = .none
            serviceLog.debug("event=deleteLastCharacter_resync sid=\(self.transcriptState.sessionId.prefix(8), privacy: .public)")
        } catch {
            controlIntent = .none
            serviceLog.error("event=deleteLastCharacter_resync_fail sid=\(self.transcriptState.sessionId.prefix(8), privacy: .public) reason=\(error.localizedDescription, privacy: .public)")
        }

        // 4. 상태 전파 — extension에 업데이트된 텍스트 전달
        writeState(phase: .recording, partialText: currentAbsoluteText)
        writeHeartbeatNow(source: "deleteChar")
        delegate?.dictationService(self, didUpdatePartial: currentAbsoluteText)
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
        guard controlIntent == .none else { return }
        // DEBUG TRACE: VoiceRecognition investigation
        serviceLog.debug("event=service_partial sid=\(self.transcriptState.sessionId.prefix(8), privacy: .public) intent=\(String(describing: self.controlIntent), privacy: .public) delegateCall=true")
        hasReceivedSpeech = true
        transcriptState.currentTaskPartial = text
        debouncedWritePartial()
        delegate?.dictationService(self, didUpdatePartial: currentAbsoluteText)
    }

    func speechRecognition(_ manager: SpeechRecognitionManager, didReceiveFinal text: String) {
        guard controlIntent == .none else { return }
        // DEBUG TRACE: VoiceRecognition investigation
        serviceLog.debug("event=service_final sid=\(self.transcriptState.sessionId.prefix(8), privacy: .public)")
        hasReceivedSpeech = true
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

        // silence timeout은 정책적 종료 — 일반 error와 분리 처리
        if let speechError = error as? SpeechRecognitionManager.SpeechError,
           speechError == .silenceTimeout {
            handleSilenceTimeout()
            return
        }

        // DEBUG TRACE: VoiceRecognition investigation
        serviceLog.error("event=service_error sid=\(self.transcriptState.sessionId.prefix(8), privacy: .public) reason=\(error.localizedDescription, privacy: .public)")
        // 일반 error: speech engine teardown 먼저 보장
        speechManager.stop()
        writeError(error.localizedDescription)
    }

    func speechRecognitionDidReachTimeLimit(_ manager: SpeechRecognitionManager) {
        guard controlIntent == .none else { return }
        // DEBUG TRACE: VoiceRecognition investigation
        serviceLog.debug("event=timeLimit sid=\(self.transcriptState.sessionId.prefix(8), privacy: .public)")
        performSeamlessRestart()
    }

    // MARK: - Silence Timeout Handler

    private func handleSilenceTimeout() {
        let existingText = currentAbsoluteText

        // DEBUG TRACE: silence timeout 전용 로그
        serviceLog.debug("event=silence_timeout_handle sid=\(self.transcriptState.sessionId.prefix(8), privacy: .public) hasReceivedSpeech=\(self.hasReceivedSpeech, privacy: .public) hasText=\(!existingText.isEmpty, privacy: .public)")

        // 1. speech engine 완전 teardown 먼저
        controlIntent = .stopping
        speechManager.stop()

        if hasReceivedSpeech && !existingText.isEmpty {
            // Case 2: partial이 있었음 — 텍스트 보존, 정상 완료 취급
            transcriptState.version += 1
            let payload = DictationStatePayload(
                sessionId: transcriptState.sessionId,
                phase: .completed,
                locale: currentLocale,
                partialText: existingText,
                finalText: existingText,
                errorMessage: nil,
                errorCode: nil,
                audioLevel: nil,
                version: transcriptState.version,
                updatedAt: Date()
            )
            try? sharedStore.writeState(payload)
            cleanup()
            delegate?.dictationService(self, didFinishWith: existingText)
            delegate?.dictationService(self, didChangePhase: .completed)
        } else {
            // Case 1: partial 없음 — No speech detected
            controlIntent = .none
            writeError("No speech detected")
        }
    }

    // MARK: - Seamless Restart

    private func performSeamlessRestart() {
        // DEBUG TRACE: VoiceRecognition investigation
        serviceLog.debug("event=seamlessRestart_start sid=\(self.transcriptState.sessionId.prefix(8), privacy: .public)")
        controlIntent = .restarting
        transcriptState.committedPrefix = currentAbsoluteText
        transcriptState.currentTaskPartial = ""
        speechManager.stop()
        do {
            try speechManager.start()
            speechManager.delegate = self
            controlIntent = .none
            // DEBUG TRACE: VoiceRecognition investigation
            serviceLog.debug("event=seamlessRestart_success sid=\(self.transcriptState.sessionId.prefix(8), privacy: .public)")
            writeState(phase: .recording, partialText: currentAbsoluteText)
            writeHeartbeatNow(source: "restart")
        } catch {
            // 1회 재시도
            do {
                try speechManager.start()
                speechManager.delegate = self
                controlIntent = .none
                serviceLog.debug("event=seamlessRestart_retry_success sid=\(self.transcriptState.sessionId.prefix(8), privacy: .public)")
                writeState(phase: .recording, partialText: currentAbsoluteText)
                writeHeartbeatNow(source: "restart")
            } catch {
                controlIntent = .none
                // DEBUG TRACE: VoiceRecognition investigation
                serviceLog.error("event=seamlessRestart_fail sid=\(self.transcriptState.sessionId.prefix(8), privacy: .public) reason=\(error.localizedDescription, privacy: .public)")
                writeHeartbeatNow(source: "restart")
                writeError(error.localizedDescription)
            }
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
        // DEBUG TRACE: VoiceRecognition investigation
        serviceLog.debug("event=writeState phase=\(String(describing: phase), privacy: .public) ver=\(self.transcriptState.version, privacy: .public) sid=\(self.transcriptState.sessionId.prefix(8), privacy: .public)")
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
            self.writeHeartbeatNow(source: "partial")
            if self.speechManager.isNearTimeLimit {
                self.performSeamlessRestart()
            }
        }
    }

    // MARK: - Heartbeat

    private func writeHeartbeatNow(source: String) {
        // DEBUG TRACE: VoiceRecognition investigation
        serviceLog.debug("event=heartbeat source=\(source, privacy: .public) sid=\(self.transcriptState.sessionId.prefix(8), privacy: .public) active=\(self.isActive, privacy: .public)")
        AppGroupManager.shared.set(Date(), forKey: DictationConstants.DefaultsKeys.dictationHeartbeatAt)
        DarwinNotificationBridge.shared.post(DictationConstants.Notifications.heartbeatChanged)
    }

    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isActive else { return }
            // DEBUG TRACE: heartbeat source=timer
            serviceLog.debug("event=heartbeat source=timer sid=\(self.transcriptState.sessionId.prefix(8), privacy: .public) active=\(self.isActive, privacy: .public)")
            AppGroupManager.shared.set(Date(), forKey: DictationConstants.DefaultsKeys.dictationHeartbeatAt)
            DarwinNotificationBridge.shared.post(DictationConstants.Notifications.heartbeatChanged)
        }
    }

    // MARK: - Cleanup

    private func cleanup() {
        // DEBUG TRACE: VoiceRecognition investigation
        serviceLog.debug("event=cleanup sid=\(self.transcriptState.sessionId.prefix(8), privacy: .public) isActive=\(self.isActive, privacy: .public)")
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
