import Foundation

struct CompositionSession {
    let id: UUID
    let startedAt: Date
    var endedAt: Date?
    let mode: SessionMode
    var apiCallCount: Int
    var sourceText: String
    var resultText: String?

    enum SessionMode: String, Codable {
        case correct
        case translate
    }

    var isActive: Bool {
        return endedAt == nil
    }
}

class CompositionSessionManager {
    static let shared = CompositionSessionManager()

    private var currentSession: CompositionSession?
    private var idleTimer: Timer?
    private let idleTimeout: TimeInterval = AppConstants.Limits.sessionIdleTimeout

    private let userDefaults: UserDefaults?

    private init() {
        userDefaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier)
    }

    // MARK: - Session Start

    func startSession(mode: CompositionSession.SessionMode) {
        if currentSession?.isActive == true {
            endSession(reason: .modeChange)
        }

        currentSession = CompositionSession(
            id: UUID(),
            startedAt: Date(),
            mode: mode,
            apiCallCount: 0,
            sourceText: ""
        )

        incrementDailySessionCount()
        resetIdleTimer()
    }

    // MARK: - Record API Call

    func recordAPICall(sourceText: String, resultText: String?, mode: CompositionSession.SessionMode = .correct) {
        guard currentSession?.isActive == true else {
            startSession(mode: mode)
            recordAPICall(sourceText: sourceText, resultText: resultText, mode: mode)
            return
        }

        currentSession?.apiCallCount += 1
        currentSession?.sourceText = sourceText
        currentSession?.resultText = resultText
        resetIdleTimer()
    }

    // MARK: - Session End

    enum EndReason {
        case textInserted
        case modeExit
        case keyboardHidden
        case idleTimeout
        case modeChange
    }

    func endSession(reason: EndReason) {
        guard var session = currentSession, session.isActive else { return }

        session.endedAt = Date()
        currentSession = session

        idleTimer?.invalidate()
        idleTimer = nil

        // API 호출이 있었던 세션만 일일 사용량으로 카운트 (세션당 1회)
        if session.apiCallCount > 0 {
            switch session.mode {
            case .correct:
                DailyUsageManager.shared.recordCorrection()
            case .translate:
                DailyUsageManager.shared.recordTranslation()
            }
        }

        saveSessionToHistory(session)
        currentSession = nil
    }

    // MARK: - Idle Timer

    private func resetIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(
            withTimeInterval: idleTimeout,
            repeats: false
        ) { [weak self] _ in
            self?.endSession(reason: .idleTimeout)
        }
    }

    // MARK: - Daily Session Count

    private func incrementDailySessionCount() {
        guard !SubscriptionStatus.shared.isPro else { return }
        let today = formattedDate(Date())
        let lastDate = userDefaults?.string(forKey: AppConstants.UserDefaultsKeys.lastSessionDate)

        if lastDate != today {
            userDefaults?.set(1, forKey: AppConstants.UserDefaultsKeys.dailySessionCount)
            userDefaults?.set(today, forKey: AppConstants.UserDefaultsKeys.lastSessionDate)
        } else {
            let current = userDefaults?.integer(forKey: AppConstants.UserDefaultsKeys.dailySessionCount) ?? 0
            userDefaults?.set(current + 1, forKey: AppConstants.UserDefaultsKeys.dailySessionCount)
        }
    }

    func remainingSessions() -> Int {
        return min(DailyUsageManager.shared.remainingCorrections, DailyUsageManager.shared.remainingTranslations)
    }

    func remainingSessions(for mode: CompositionSession.SessionMode) -> Int {
        switch mode {
        case .correct: return DailyUsageManager.shared.remainingCorrections
        case .translate: return DailyUsageManager.shared.remainingTranslations
        }
    }

    func canStartSession() -> Bool {
        if SubscriptionStatus.shared.isPro { return true }
        return remainingSessions() > 0
    }

    func canStartSession(mode: CompositionSession.SessionMode) -> Bool {
        if SubscriptionStatus.shared.isPro { return true }
        if AdminMode.shared.isEnabled { return true }
        return remainingSessions(for: mode) > 0
    }

    var hasActiveSession: Bool {
        return currentSession?.isActive == true
    }

    // MARK: - History

    private func saveSessionToHistory(_ session: CompositionSession) {
        guard !session.sourceText.isEmpty else { return }

        let historyType: HistoryType = session.mode == .correct ? .correction : .translation
        let metadata: String
        if session.mode == .translate {
            let src = AppGroupManager.shared.string(forKey: AppConstants.UserDefaultsKeys.sourceLanguage) ?? "ko"
            let tgt = AppGroupManager.shared.string(forKey: AppConstants.UserDefaultsKeys.targetLanguage) ?? "en"
            metadata = "\(src.uppercased()) → \(tgt.uppercased())"
        } else {
            metadata = L("home.stat.corrections")
        }

        HistoryManager.shared.addItem(
            type: historyType,
            original: session.sourceText,
            result: session.resultText,
            metadata: metadata
        )
    }

    // MARK: - Utility

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
