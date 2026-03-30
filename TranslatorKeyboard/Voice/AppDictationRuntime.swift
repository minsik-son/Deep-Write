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

struct StartContext {
    let sessionId: String
    let locale: String
    let source: LaunchSource
}

struct ActiveContext {
    let sessionId: String
    let locale: String
    let startedAt: Date
}

struct RuntimeErrorContext {
    let sessionId: String
    let message: String
    let occurredAt: Date
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

    private var activeSessionId: String?
    private var activeLocale: String?
    private var activeStartedAt: Date?

    var isActive: Bool {
        if case .idle = state { return false }
        if case .error = state { return false }
        return true
    }

    init() {
        dictationService.delegate = self
        startCommandObserver()
    }

    // MARK: - Start Session

    func startSession(sessionId: String, locale: String, source: LaunchSource) -> StartResult {
        // Reject if already active
        if isActive, let activeId = activeSessionId {
            return .rejectedAlreadyActive(activeSessionId: activeId)
        }

        // Reject duplicate sessionId
        if activeSessionId == sessionId {
            return .rejectedAlreadyActive(activeSessionId: sessionId)
        }

        // Permission check
        guard SpeechRecognitionManager.isSpeechAuthorized && SpeechRecognitionManager.isMicAuthorized else {
            return .rejectedPermissionRequired
        }

        // Locale validation
        let tempManager = SpeechRecognitionManager()
        guard tempManager.setLocale(locale) else {
            return .rejectedUnsupportedLocale
        }

        // Transition to starting
        activeSessionId = sessionId
        activeLocale = locale
        activeStartedAt = Date()
        state = .starting(sessionId: sessionId)

        // Start engine via DictationService
        dictationService.startSession(sessionId: sessionId, locale: locale)

        return .accepted(sessionId: sessionId)
    }

    // MARK: - Stop

    func stopSession(reason: StopReason) {
        guard isActive else { return }

        state = .finalizing(sessionId: activeSessionId ?? "")
        dictationService.stopSession()

        // Cleanup timers
        returnGraceTimer?.invalidate()
        returnGraceTimer = nil
    }

    // MARK: - Cancel

    func cancelSession(reason: CancelReason) {
        guard isActive else { return }

        dictationService.cancelSession()
        cleanupSession()
    }

    // MARK: - Pause / Resume

    func pauseSession() {
        guard isActive, let sid = activeSessionId else { return }
        dictationService.pauseSession()
        state = .paused(sessionId: sid)
    }

    func resumeSession() {
        guard isActive, let sid = activeSessionId else { return }
        dictationService.resumeSession()
        state = .recording(sessionId: sid)
    }

    // MARK: - App Lifecycle

    func handleAppDidEnterBackground() {
        // Audio engine continues with UIBackgroundModes=audio
        // Keep heartbeat running
    }

    func handleAppWillEnterForeground() {
        // Resume any paused work if needed
    }

    func handleSceneDidDisconnect() {
        // Scene disconnected but process still alive
        // Runtime keeps running
    }

    func handleMemoryWarning() {
        if isActive {
            stopSession(reason: .memoryWarning)
        }
    }

    // MARK: - Snapshot

    func currentSnapshot() -> RuntimeSnapshot {
        return RuntimeSnapshot(
            state: state,
            sessionId: activeSessionId,
            locale: activeLocale,
            isActive: isActive
        )
    }

    // MARK: - Stale Cleanup

    func cleanupIfStale(now: Date = Date()) {
        guard !isActive else { return }
        sharedStore.clearAllIfStale(now: now)
    }

    // MARK: - Manual Return Grace Period

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

        switch command.action {
        case .pause:
            pauseSession()
        case .resume:
            resumeSession()
        case .stop:
            stopSession(reason: .userStopped)
        case .cancel:
            cancelSession(reason: .userCancelledFromExtension)
        case .clear:
            // Clear current partial and restart
            break
        case .deleteLastWord:
            break
        case .start:
            // Already handled via SceneDelegate
            break
        }
    }

    // MARK: - DictationServiceDelegate

    func dictationService(_ service: DictationService, didChangePhase phase: DictationPhase) {
        guard let sid = activeSessionId else { return }

        switch phase {
        case .preparing:
            state = .starting(sessionId: sid)
        case .recording:
            state = .recording(sessionId: sid)
            // If we were waiting for user return, they might still be in bootstrap
            if case .starting = state {
                state = .waitingForUserReturn(sessionId: sid)
                startReturnGraceTimer()
            } else {
                state = .recording(sessionId: sid)
            }
        case .paused:
            state = .paused(sessionId: sid)
        case .completed:
            cleanupSession()
        case .error:
            state = .error(message: "Speech engine error")
        case .idle:
            cleanupSession()
        default:
            break
        }
    }

    func dictationService(_ service: DictationService, didUpdatePartial text: String) {
        // Service handles writing to shared store
        // Cancel grace timer since we're actively recording
        cancelReturnGraceTimer()
    }

    func dictationService(_ service: DictationService, didFinishWith finalText: String) {
        cleanupSession()
    }

    func dictationService(_ service: DictationService, didFailWith message: String) {
        state = .error(message: message)
        // Auto-cleanup after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + DictationConstants.Limits.errorAutoResetDelay) { [weak self] in
            self?.cleanupSession()
        }
    }

    // MARK: - Cleanup

    private func cleanupSession() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        returnGraceTimer?.invalidate()
        returnGraceTimer = nil

        activeSessionId = nil
        activeLocale = nil
        activeStartedAt = nil

        state = .idle
    }
}
