import UIKit
import OSLog

// DEBUG TRACE: VoiceRecognition investigation
private let extensionLog = Logger(
    subsystem: "com.translatorkeyboard.keyboard.voice",
    category: "extension"
)

protocol DictationSessionCoordinatorDelegate: AnyObject {
    func dictationCoordinator(_ coordinator: DictationSessionCoordinator, didChangeState state: KeyboardDictationState)
    func dictationCoordinator(_ coordinator: DictationSessionCoordinator, didReceivePartial text: String)
    func dictationCoordinator(_ coordinator: DictationSessionCoordinator, didReceiveFinal text: String)
    func dictationCoordinatorDidCancel(_ coordinator: DictationSessionCoordinator)
}

enum KeyboardDictationState: Equatable {
    case idle
    case requestingLaunch
    case waitingForAck
    case active
    case paused
    case finalizing
    case error(String)

    static func == (lhs: KeyboardDictationState, rhs: KeyboardDictationState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.requestingLaunch, .requestingLaunch),
             (.waitingForAck, .waitingForAck), (.active, .active),
             (.paused, .paused), (.finalizing, .finalizing):
            return true
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }
}

final class DictationSessionCoordinator {

    weak var delegate: DictationSessionCoordinatorDelegate?

    private let sharedStore = DictationSharedStore()
    private(set) var state: KeyboardDictationState = .idle
    private(set) var sessionId: String = ""
    private(set) var locale: String = "en-US"

    private var stateObserverToken: UUID?
    private var heartbeatObserverToken: UUID?
    private var pollingTimer: Timer?
    private var ackWatchdogTimer: Timer?
    private var heartbeatWatchdogTimer: Timer?
    private var errorResetTimer: Timer?

    private var lastAppliedVersion: UInt64 = 0
    private var isWarmStart: Bool = false

    var isActive: Bool {
        switch state {
        case .idle, .error:
            return false
        default:
            return true
        }
    }

    // MARK: - Session Recovery

    /// 키보드가 다시 나타날 때 active session을 복구한다.
    /// shared state file에서 유효한 active session이 있으면 overlay를 재구성한다.
    func tryRecoverSession() -> Bool {
        guard state == .idle else { return isActive }

        // Step 1: Read kill signal ONCE
        let killSignal = sharedStore.readKill()

        // Step 2: If kill signal exists, check TTL first
        if let killSignal = killSignal {
            let killAge = Date().timeIntervalSince(killSignal.timestampAt)
            if killAge >= DictationConstants.Limits.killSignalTTL {
                // DEBUG TRACE: VoiceRecognition investigation
                extensionLog.debug("event=tryRecoverSession killSignal=stale age=\(killAge, privacy: .public)")
                sharedStore.clearKill()
            }
        }

        // Step 3: Load state payload
        guard let payload = sharedStore.readState() else { return false }

        // Step 4: If fresh kill signal exists, compare sessionId
        if let killSignal = killSignal {
            let killAge = Date().timeIntervalSince(killSignal.timestampAt)
            if killAge < DictationConstants.Limits.killSignalTTL {
                if killSignal.sessionId == payload.sessionId {
                    // DEBUG TRACE: VoiceRecognition investigation
                    extensionLog.debug("event=tryRecoverSession_reject reason=killSignalMatch sid=\(payload.sessionId.prefix(8), privacy: .public)")
                    sharedStore.clearAllIfStale()
                    sharedStore.clearKill()
                    return false
                } else {
                    // DEBUG TRACE: VoiceRecognition investigation
                    extensionLog.debug("event=tryRecoverSession killSignal=mismatch")
                }
            }
        }

        // Step 5: Stale payload check
        let age = Date().timeIntervalSince(payload.updatedAt)
        guard age < DictationConstants.Limits.stalePayloadTTL else {
            sharedStore.clearAllIfStale()
            return false
        }

        // Step 6: Active phase check
        switch payload.phase {
        case .preparing, .recording, .paused, .finalizing:
            break
        default:
            return false
        }

        // Step 6.5: Heartbeat freshness gate — app/runtime이 실제로 살아있는지 확인
        if let heartbeatDate = AppGroupManager.shared.date(forKey: DictationConstants.DefaultsKeys.dictationHeartbeatAt) {
            let heartbeatAge = Date().timeIntervalSince(heartbeatDate)
            guard heartbeatAge < DictationConstants.Limits.warmHeartbeatTTL else {
                extensionLog.debug("event=tryRecoverSession_reject reason=staleHeartbeat age=\(heartbeatAge, privacy: .public) sid=\(payload.sessionId.prefix(8), privacy: .public)")
                return false
            }
        } else {
            // heartbeat가 아예 없으면 앱이 한 번도 heartbeat를 쓴 적 없음
            extensionLog.debug("event=tryRecoverSession_reject reason=noHeartbeat sid=\(payload.sessionId.prefix(8), privacy: .public)")
            return false
        }

        // DEBUG TRACE: VoiceRecognition investigation
        extensionLog.debug("event=tryRecoverSession_accept phase=\(String(describing: payload.phase), privacy: .public) age=\(age, privacy: .public) sid=\(payload.sessionId.prefix(8), privacy: .public)")

        // Step 7: Recover session — delegate/overlay 연결 전이므로 handleStateUpdate 호출하지 않음
        // caller(KeyboardViewController)가 delegate/overlay 연결 후 replayRecoveredState()로 첫 payload 처리
        sessionId = payload.sessionId
        locale = payload.locale
        lastAppliedVersion = 0

        startObservers()

        switch payload.phase {
        case .recording, .preparing:
            transitionTo(.active)
        case .paused:
            transitionTo(.paused)
        case .finalizing:
            transitionTo(.finalizing)
        default:
            break
        }

        return true
    }

    /// Recovery 후 delegate/overlay 연결이 완료된 시점에 첫 payload를 replay
    func replayRecoveredState() {
        handleStateUpdate()
    }

    // MARK: - Start

    func startDictation(locale: String, proxy: UITextDocumentProxy) -> Bool {
        // Secure field / phone pad guard
        if proxy.isSecureTextEntry == true { return false }
        if let keyboardType = proxy.keyboardType {
            switch keyboardType {
            case .phonePad, .namePhonePad:
                return false
            default:
                break
            }
        }

        self.locale = locale
        sessionId = UUID().uuidString
        lastAppliedVersion = 0

        // DEBUG TRACE: VoiceRecognition investigation
        extensionLog.debug("event=startDictation sid=\(self.sessionId.prefix(8), privacy: .public) locale=\(locale, privacy: .public) warmStart=\(self.isWarmStart, privacy: .public)")

        // Check warm start
        if let heartbeat = AppGroupManager.shared.date(forKey: DictationConstants.DefaultsKeys.dictationHeartbeatAt) {
            let age = Date().timeIntervalSince(heartbeat)
            isWarmStart = age < DictationConstants.Limits.warmHeartbeatTTL
        } else {
            isWarmStart = false
        }

        // Write command
        let command = DictationCommandPayload(
            sessionId: sessionId,
            action: .start,
            locale: locale,
            sourceAppBundleId: nil,
            requestedAt: Date()
        )
        do {
            try sharedStore.writeCommand(command)
        } catch {
            transitionTo(.error("Failed to write command"))
            return false
        }

        transitionTo(.requestingLaunch)

        // Open main app
        openMainApp()

        transitionTo(.waitingForAck)
        startObservers()
        startAckWatchdog()

        return true
    }

    // MARK: - Send Commands

    func sendPause() {
        // DEBUG TRACE: VoiceRecognition investigation
        extensionLog.debug("event=cmd_write action=pause sid=\(self.sessionId.prefix(8), privacy: .public)")
        let command = DictationCommandPayload(
            sessionId: sessionId, action: .pause,
            locale: locale, sourceAppBundleId: nil, requestedAt: Date()
        )
        do {
            try sharedStore.writeCommand(command)
        } catch {
            extensionLog.error("event=cmd_write_fail action=pause reason=\(error.localizedDescription, privacy: .public)")
        }
    }

    func sendResume() {
        // DEBUG TRACE: VoiceRecognition investigation
        extensionLog.debug("event=cmd_write action=resume sid=\(self.sessionId.prefix(8), privacy: .public)")
        let command = DictationCommandPayload(
            sessionId: sessionId, action: .resume,
            locale: locale, sourceAppBundleId: nil, requestedAt: Date()
        )
        do {
            try sharedStore.writeCommand(command)
        } catch {
            extensionLog.error("event=cmd_write_fail action=resume reason=\(error.localizedDescription, privacy: .public)")
        }
    }

    func sendStop() {
        // DEBUG TRACE: VoiceRecognition investigation
        extensionLog.debug("event=cmd_write action=stop sid=\(self.sessionId.prefix(8), privacy: .public)")
        let command = DictationCommandPayload(
            sessionId: sessionId, action: .stop,
            locale: locale, sourceAppBundleId: nil, requestedAt: Date()
        )
        do {
            try sharedStore.writeCommand(command)
        } catch {
            extensionLog.error("event=cmd_write_fail action=stop reason=\(error.localizedDescription, privacy: .public)")
        }
        transitionTo(.finalizing)
    }

    func sendCancel() {
        let command = DictationCommandPayload(
            sessionId: sessionId, action: .cancel,
            locale: locale, sourceAppBundleId: nil, requestedAt: Date()
        )
        do {
            try sharedStore.writeCommand(command)
        } catch {
            extensionLog.error("event=cmd_write_fail action=cancel reason=\(error.localizedDescription, privacy: .public)")
        }
        cleanup()
        delegate?.dictationCoordinatorDidCancel(self)
    }

    func sendClear() {
        let command = DictationCommandPayload(
            sessionId: sessionId, action: .clear,
            locale: locale, sourceAppBundleId: nil, requestedAt: Date()
        )
        do {
            try sharedStore.writeCommand(command)
        } catch {
            extensionLog.error("event=cmd_write_fail action=clear reason=\(error.localizedDescription, privacy: .public)")
        }
    }

    func sendDeleteLastCharacter() {
        // DEBUG TRACE: VoiceRecognition investigation
        extensionLog.debug("event=cmd_write action=deleteLastCharacter sid=\(self.sessionId.prefix(8), privacy: .public)")
        let command = DictationCommandPayload(
            sessionId: sessionId, action: .deleteLastCharacter,
            locale: locale, sourceAppBundleId: nil, requestedAt: Date()
        )
        do {
            try sharedStore.writeCommand(command)
        } catch {
            extensionLog.error("event=cmd_write_fail action=deleteLastCharacter reason=\(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Force Finalize (memory warning / dismiss)

    func forceFinalizePreservingCurrentState() {
        sendStop()
        cleanup()  // 즉시 cleanup — memory warning 경로에서 0.5s delay 제거
    }

    // MARK: - State Handling

    private func handleStateUpdate() {
        guard let payload = sharedStore.readState() else { return }
        guard payload.sessionId == sessionId else { return }
        guard payload.version > lastAppliedVersion else { return }

        lastAppliedVersion = payload.version

        // DEBUG TRACE: VoiceRecognition investigation
        extensionLog.debug("event=handleStateUpdate phase=\(String(describing: payload.phase), privacy: .public) ver=\(payload.version, privacy: .public) sid=\(payload.sessionId.prefix(8), privacy: .public) extState=\(String(describing: self.state), privacy: .public)")

        switch payload.phase {
        case .preparing:
            ackWatchdogTimer?.invalidate()
            transitionTo(.active)

        case .recording:
            ackWatchdogTimer?.invalidate()
            transitionTo(.active)
            delegate?.dictationCoordinator(self, didReceivePartial: payload.partialText)
            resetHeartbeatWatchdog()

        case .paused:
            transitionTo(.paused)
            resetHeartbeatWatchdog()  // pause 진입 시 watchdog seed

        case .completed:
            let finalText = payload.finalText ?? payload.partialText
            delegate?.dictationCoordinator(self, didReceiveFinal: finalText)
            cleanup()

        case .error:
            let message = payload.errorMessage ?? "Unknown error"
            transitionTo(.error(message))

        case .idle:
            // Runtime went idle (e.g., after stop) — cleanup
            cleanup()

        case .launchingApp, .finalizing:
            break
        }
    }

    // MARK: - Observers

    private func startObservers() {
        stateObserverToken = DarwinNotificationBridge.shared.addObserver(
            name: DictationConstants.Notifications.stateChanged
        ) { [weak self] in
            DispatchQueue.main.async { self?.handleStateUpdate() }
        }

        heartbeatObserverToken = DarwinNotificationBridge.shared.addObserver(
            name: DictationConstants.Notifications.heartbeatChanged
        ) { [weak self] in
            DispatchQueue.main.async { self?.resetHeartbeatWatchdog() }
        }

        // Polling backup — state update + heartbeat freshness keepalive
        pollingTimer = Timer.scheduledTimer(withTimeInterval: DictationConstants.Limits.pollingInterval, repeats: true) { [weak self] _ in
            self?.handleStateUpdate()
            self?.refreshWatchdogFromHeartbeatIfNeeded()
        }
    }

    private func stopObservers() {
        if let token = stateObserverToken {
            DarwinNotificationBridge.shared.removeObserver(name: DictationConstants.Notifications.stateChanged, token: token)
            stateObserverToken = nil
        }
        if let token = heartbeatObserverToken {
            DarwinNotificationBridge.shared.removeObserver(name: DictationConstants.Notifications.heartbeatChanged, token: token)
            heartbeatObserverToken = nil
        }
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    // MARK: - Watchdogs

    private func startAckWatchdog() {
        let timeout = isWarmStart
            ? DictationConstants.Limits.warmStartAckTimeout
            : DictationConstants.Limits.coldStartAckTimeout

        ackWatchdogTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if self.state == .waitingForAck {
                if self.isWarmStart {
                    // Warm start failed, try cold start
                    self.isWarmStart = false
                    self.openMainApp()
                    self.startAckWatchdog()
                } else {
                    self.transitionTo(.error("App did not respond"))
                }
            }
        }
    }

    private func resetHeartbeatWatchdog() {
        heartbeatWatchdogTimer?.invalidate()
        // DEBUG TRACE: VoiceRecognition investigation
        extensionLog.debug("event=watchdog_reset sid=\(self.sessionId.prefix(8), privacy: .public) state=\(String(describing: self.state), privacy: .public)")
        heartbeatWatchdogTimer = Timer.scheduledTimer(withTimeInterval: DictationConstants.Limits.watchdogTimeout, repeats: false) { [weak self] _ in
            guard let self = self, self.isActive else { return }
            // DEBUG TRACE: VoiceRecognition investigation
            extensionLog.error("event=watchdog_fire sid=\(self.sessionId.prefix(8), privacy: .public) state=\(String(describing: self.state), privacy: .public) reason=appConnectionLost")
            self.transitionTo(.error("App connection lost"))
        }
    }

    /// Polling backup: heartbeat freshness로 watchdog 연장 — state version 변화 없어도 동작
    private func refreshWatchdogFromHeartbeatIfNeeded() {
        guard state == .active || state == .paused else { return }
        guard let heartbeatDate = AppGroupManager.shared.date(forKey: DictationConstants.DefaultsKeys.dictationHeartbeatAt) else { return }
        let heartbeatAge = Date().timeIntervalSince(heartbeatDate)
        guard heartbeatAge < DictationConstants.Limits.watchdogTimeout else { return }
        // heartbeat가 아직 fresh — watchdog 갱신
        resetHeartbeatWatchdog()
    }

    // MARK: - State Transition

    private func transitionTo(_ newState: KeyboardDictationState) {
        guard state != newState else { return }
        state = newState
        delegate?.dictationCoordinator(self, didChangeState: newState)

        if case .error = newState {
            startErrorAutoReset()
        }
    }

    private func startErrorAutoReset() {
        errorResetTimer?.invalidate()
        errorResetTimer = Timer.scheduledTimer(withTimeInterval: DictationConstants.Limits.errorAutoResetDelay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.cleanup()
        }
    }

    // MARK: - Open Main App

    /// Keyboard extension에서 URL을 여는 헬퍼.
    /// UIApplication.shared는 extension에서 사용 불가하므로 responder chain을 사용한다.
    var openURLHandler: ((URL) -> Void)?

    private func openMainApp() {
        guard let url = URL(string: "translatorkeyboard://dictation?locale=\(locale)&session=\(sessionId)") else { return }
        openURLHandler?(url)
    }

    // MARK: - Cleanup

    func cleanup() {
        // DEBUG TRACE: VoiceRecognition investigation
        extensionLog.debug("event=cleanup state=\(String(describing: self.state), privacy: .public) sid=\(self.sessionId.prefix(8), privacy: .public)")

        stopObservers()
        ackWatchdogTimer?.invalidate()
        ackWatchdogTimer = nil
        heartbeatWatchdogTimer?.invalidate()
        heartbeatWatchdogTimer = nil
        errorResetTimer?.invalidate()
        errorResetTimer = nil

        sharedStore.clearCommand()  // extension이 자기 command 정리

        let previousState = state
        state = .idle
        if previousState != .idle {
            delegate?.dictationCoordinator(self, didChangeState: .idle)
        }
    }

    /// Force-shutdown: stop immediately, clear all shared state, write kill signal with TTL
    func forceShutdown(reason: String) {
        // DEBUG TRACE: VoiceRecognition investigation
        extensionLog.error("event=forceShutdown reason=\(reason, privacy: .public) sid=\(self.sessionId.prefix(8), privacy: .public)")

        stopObservers()
        ackWatchdogTimer?.invalidate()
        ackWatchdogTimer = nil
        heartbeatWatchdogTimer?.invalidate()
        heartbeatWatchdogTimer = nil
        errorResetTimer?.invalidate()
        errorResetTimer = nil

        // Clear all shared files
        sharedStore.clearCommand()
        sharedStore.clearState()  // Only forceShutdown() deletes state

        // Write kill signal to force main app cleanup
        let killSignal = DictationKillSignal(
            sessionId: sessionId,
            reason: reason,
            timestampAt: Date()
        )
        do {
            try sharedStore.writeKill(killSignal)
        } catch {
            extensionLog.error("event=writeKill_fail reason=\(error.localizedDescription, privacy: .public)")
        }

        let previousState = state
        state = .idle
        if previousState != .idle {
            delegate?.dictationCoordinator(self, didChangeState: .idle)
        }
    }
}
