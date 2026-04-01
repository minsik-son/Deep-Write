import Foundation

// MARK: - Types

enum LaunchSource {
    case coldStart
    case warmStart
}

enum StopReason {
    case userStopped
    case userDidNotReturnInTime
    case backgroundInterrupted
    case memoryWarning
    case sceneDisconnect
}

enum CancelReason {
    case userCancelledDuringBootstrap
    case userCancelledFromExtension
    case systemCancelled
}

enum StartResult {
    case accepted(sessionId: String)
    case rejectedAlreadyActive(activeSessionId: String)
    case rejectedUnsupportedLocale
    case rejectedPermissionRequired
    case failedToStart(message: String)
}

struct RuntimeSnapshot {
    let state: RuntimeState
    let sessionId: String?
    let locale: String?
    let isActive: Bool
}

enum RuntimeState: Equatable {
    case idle
    case starting(sessionId: String)
    case waitingForUserReturn(sessionId: String)
    case recording(sessionId: String)
    case paused(sessionId: String)
    case finalizing(sessionId: String)
    case error(message: String)

    static func == (lhs: RuntimeState, rhs: RuntimeState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.starting(let a), .starting(let b)): return a == b
        case (.waitingForUserReturn(let a), .waitingForUserReturn(let b)): return a == b
        case (.recording(let a), .recording(let b)): return a == b
        case (.paused(let a), .paused(let b)): return a == b
        case (.finalizing(let a), .finalizing(let b)): return a == b
        case (.error(let a), .error(let b)): return a == b
        default: return false
        }
    }
}

// MARK: - Runtime

final class AppDictationRuntime: DictationServiceDelegate {

    private(set) var state: RuntimeState = .idle
    private let dictationService = DictationService()
    private let sharedStore = DictationSharedStore()

    private var heartbeatTimer: Timer?
    private var returnGraceTimer: Timer?
    private var commandObserverToken: UUID?

    private var killObserverToken: UUID?
    private var activeSessionId: String?
    private var activeLocale: String?

    var isActive: Bool {
        if case .idle = state { return false }
        if case .error = state { return false }
        return true
    }

    init() {
        dictationService.delegate = self
        startCommandObserver()
        startKillObserver()
    }

    // MARK: - Start Session

    func startSession(sessionId: String, locale: String, source: LaunchSource) -> StartResult {
        if isActive, let activeId = activeSessionId {
            return .rejectedAlreadyActive(activeSessionId: activeId)
        }
        if activeSessionId == sessionId {
            return .rejectedAlreadyActive(activeSessionId: sessionId)
        }

        guard SpeechRecognitionManager.isSpeechAuthorized && SpeechRecognitionManager.isMicAuthorized else {
            return .rejectedPermissionRequired
        }

        let tempManager = SpeechRecognitionManager()
        guard tempManager.setLocale(locale) else {
            return .rejectedUnsupportedLocale
        }

        activeSessionId = sessionId
        activeLocale = locale
        state = .starting(sessionId: sessionId)

        #if DEBUG
        print("[DictationRuntime] START sessionId=\(sessionId.prefix(8)) locale=\(locale)")
        #endif

        dictationService.startSession(sessionId: sessionId, locale: locale)
        return .accepted(sessionId: sessionId)
    }

    // MARK: - Stop (동기 cleanup — asyncAfter 금지)

    func stopSession(reason: StopReason) {
        guard isActive else { return }

        #if DEBUG
        print("[DictationRuntime] STOP reason=\(reason) sessionId=\(activeSessionId?.prefix(8) ?? "nil")")
        #endif

        state = .finalizing(sessionId: activeSessionId ?? "")
        returnGraceTimer?.invalidate()
        returnGraceTimer = nil

        dictationService.forceStop()
        cleanupSession()  // 반드시 동기
    }

    // MARK: - Cancel (동기 cleanup)

    func cancelSession(reason: CancelReason) {
        guard isActive else { return }

        #if DEBUG
        print("[DictationRuntime] CANCEL reason=\(reason) sessionId=\(activeSessionId?.prefix(8) ?? "nil")")
        #endif

        dictationService.cancelSession()
        cleanupSession()  // 동기
    }

    // MARK: - Pause / Resume

    func pauseSession() {
        guard isActive, let sid = activeSessionId else { return }
        #if DEBUG
        print("[DictationRuntime] PAUSE sessionId=\(sid.prefix(8))")
        #endif
        dictationService.pauseSession()
        state = .paused(sessionId: sid)
    }

    func resumeSession() {
        guard isActive, let sid = activeSessionId else { return }
        #if DEBUG
        print("[DictationRuntime] RESUME sessionId=\(sid.prefix(8))")
        #endif
        dictationService.resumeSession()
        state = .recording(sessionId: sid)
    }

    // MARK: - Clear

    func clearTranscript() {
        guard isActive else { return }
        dictationService.clearTranscript()
    }

    // MARK: - App Lifecycle

    func handleAppDidEnterBackground() {
        // Audio continues with UIBackgroundModes=audio — 아무것도 하지 않음
    }

    func handleAppWillEnterForeground() {
        // Check for pending kill signals from extension
        checkKillSignal()
    }

    func handleSceneDidDisconnect() {
        // Process still alive — runtime keeps running
    }

    func handleMemoryWarning() {
        if isActive {
            stopSession(reason: .memoryWarning)
        }
    }

    // MARK: - Snapshot

    func currentSnapshot() -> RuntimeSnapshot {
        RuntimeSnapshot(state: state, sessionId: activeSessionId, locale: activeLocale, isActive: isActive)
    }

    // MARK: - Stale Cleanup

    func cleanupIfStale(now: Date = Date()) {
        guard !isActive else { return }
        sharedStore.clearAllIfStale(now: now)
    }

    // MARK: - Return Grace Timer

    func startReturnGraceTimer() {
        returnGraceTimer?.invalidate()
        returnGraceTimer = Timer.scheduledTimer(withTimeInterval: 20.0, repeats: false) { [weak self] _ in
            guard let self = self, self.isActive else { return }
            self.stopSession(reason: .userDidNotReturnInTime)
        }
    }

    func cancelReturnGraceTimer() {
        returnGraceTimer?.invalidate()
        returnGraceTimer = nil
    }

    // MARK: - Command Observer

    private func startKillObserver() {
        // 1) 초기 1회 체크 (cold start 대비)
        DispatchQueue.main.async { [weak self] in
            self?.checkKillSignal()
        }

        // 2) Darwin Notification 리스너 — Extension이 writeKill() 시 즉시 감지
        killObserverToken = DarwinNotificationBridge.shared.addObserver(
            name: DictationConstants.Notifications.killChanged
        ) { [weak self] in
            DispatchQueue.main.async { self?.checkKillSignal() }
        }
    }

    private func checkKillSignal() {
        guard let killSignal = sharedStore.readKill() else { return }

        let killAge = Date().timeIntervalSince(killSignal.timestampAt)
        if killAge >= DictationConstants.Limits.killSignalTTL {
            sharedStore.clearKill()
            return
        }

        #if DEBUG
        print("[DictationRuntime] KILL SIGNAL detected reason=\(killSignal.reason) sessionId=\(killSignal.sessionId.prefix(8))")
        #endif

        guard isActive else {
            // Not active — preserve kill signal for later
            #if DEBUG
            print("[DictationRuntime] kill signal preserved — isActive=false")
            #endif
            return
        }

        guard let activeId = activeSessionId, killSignal.sessionId == activeId else {
            #if DEBUG
            print("[DictationRuntime] kill signal sessionId MISMATCH — clearing")
            #endif
            sharedStore.clearKill()
            return
        }

        // Kill signal matches active session + fresh TTL → force terminate
        #if DEBUG
        print("[DictationRuntime] EXECUTING KILL for sessionId=\(activeId.prefix(8))")
        #endif
        dictationService.forceStop()
        cleanupSession()
        sharedStore.clearKill()
    }

    private func startCommandObserver() {
        commandObserverToken = DarwinNotificationBridge.shared.addObserver(
            name: DictationConstants.Notifications.commandChanged
        ) { [weak self] in
            DispatchQueue.main.async { self?.handleCommandUpdate() }
        }
    }

    private func handleCommandUpdate() {
        guard let command = sharedStore.readCommand() else { return }
        guard isActive, command.sessionId == activeSessionId else { return }

        #if DEBUG
        print("[DictationRuntime] CMD action=\(command.action) sessionId=\(command.sessionId.prefix(8))")
        #endif

        switch command.action {
        case .pause:  pauseSession()
        case .resume: resumeSession()
        case .stop:   stopSession(reason: .userStopped)
        case .cancel: cancelSession(reason: .userCancelledFromExtension)
        case .clear:  clearTranscript()
        case .deleteLastWord: break
        case .start:  break
        }
    }

    // MARK: - DictationServiceDelegate

    func dictationService(_ service: DictationService, didChangePhase phase: DictationPhase) {
        guard let sid = activeSessionId else { return }

        let previousState = state

        switch phase {
        case .preparing:
            state = .starting(sessionId: sid)

        case .recording:
            if case .starting = previousState {
                state = .waitingForUserReturn(sessionId: sid)
                startReturnGraceTimer()
            } else {
                state = .recording(sessionId: sid)
            }

        case .paused:
            state = .paused(sessionId: sid)

        case .completed:
            cleanupSession()  // 동기

        case .error:
            state = .error(message: "Speech engine error")

        case .idle:
            cleanupSession()  // 동기

        default:
            break
        }
    }

    func dictationService(_ service: DictationService, didUpdatePartial text: String) {
        cancelReturnGraceTimer()
        if let sid = activeSessionId, case .waitingForUserReturn = state {
            state = .recording(sessionId: sid)
        }
    }

    func dictationService(_ service: DictationService, didFinishWith finalText: String) {
        #if DEBUG
        print("[DictationRuntime] didFinishWith: len=\(finalText.count)")
        #endif
        cleanupSession()  // 동기
    }

    func dictationService(_ service: DictationService, didFailWith message: String) {
        state = .error(message: message)
        cleanupSession()  // 동기. asyncAfter 금지.
    }

    // MARK: - Session Cleanup (동기 — asyncAfter 절대 금지)

    /// 세션 정리 — 로컬 state만 정리. shared 파일은 삭제하지 않음.
    private func cleanupSession() {
        guard isActive || activeSessionId != nil else { return }

        #if DEBUG
        let sid = activeSessionId ?? "none"
        print("[DictationRuntime] CLEANUP sessionId=\(sid.prefix(8))")
        #endif

        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        returnGraceTimer?.invalidate()
        returnGraceTimer = nil

        activeSessionId = nil
        activeLocale = nil
        state = .idle

        // 주의: shared 파일(state, command, heartbeat)은 여기서 삭제하지 않음!
        // extension이 recovery에 사용할 수 있어야 하므로.
        // stale 파일은 cleanupIfStale()의 TTL 기반 정리로 처리.
    }
}
