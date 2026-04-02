import UIKit
import OSLog

// DEBUG TRACE: VoiceRecognition investigation
private let bootstrapLog = Logger(
    subsystem: "com.translatorkeyboard.app.voice",
    category: "bootstrap"
)

/// Bootstrap-only VC for dictation.
/// Starts the runtime session, shows "Return to your app".
/// Does NOT own the speech session — AppDictationRuntime does.
/// Session 종료 시 runtime 상태를 관찰하여 자동 dismiss.
/// dismiss는 Cancel 탭, rejected branch, 또는 stale check에서 발생.
final class DictationBootstrapViewController: UIViewController {

    private var sessionId: String = ""
    private var locale: String = "en-US"
    private var runtime: AppDictationRuntime?

    private var foregroundObserver: Any?
    private var stateObserverToken: UUID?
    private var hasStartedSession: Bool = false

    // MARK: - UI

    private let micIcon: UIImageView = {
        let iv = UIImageView()
        let config = UIImage.SymbolConfiguration(pointSize: 36, weight: .medium)
        iv.image = UIImage(systemName: "mic.fill", withConfiguration: config)
        iv.tintColor = .systemRed
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let statusLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 16, weight: .medium)
        l.textColor = .secondaryLabel
        l.textAlignment = .center
        l.text = "Starting dictation..."
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let hintLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 13)
        l.textColor = .tertiaryLabel
        l.textAlignment = .center
        l.numberOfLines = 2
        l.text = "Return to your app to use dictation"
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let returnHintLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 14, weight: .medium)
        l.textColor = .systemBlue
        l.text = "↑ " + L("dictation.bootstrap.return_hint")
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let cancelButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("Cancel", for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        btn.setTitleColor(.systemRed, for: .normal)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    // MARK: - Configure

    func configure(sessionId: String, locale: String, runtime: AppDictationRuntime) {
        self.sessionId = sessionId
        self.locale = locale
        self.runtime = runtime
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupUI()
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        startObservers()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // DEBUG TRACE: VoiceRecognition investigation
        bootstrapLog.debug("event=viewDidAppear sid=\(self.sessionId.prefix(8), privacy: .public)")
        startSession()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        checkAndDismissIfStale()
    }

    deinit {
        stopObservers()
    }

    // MARK: - Stale Check Observers

    private func startObservers() {
        // Option 1: scene foreground 복귀 시 stale check
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIScene.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.checkAndDismissIfStale()
        }

        // Option 2: shared state 변경 시 즉시 stale check (session 종료 즉각 감지)
        stateObserverToken = DarwinNotificationBridge.shared.addObserver(
            name: DictationConstants.Notifications.stateChanged
        ) { [weak self] in
            DispatchQueue.main.async { self?.checkAndDismissIfStale() }
        }
    }

    private func stopObservers() {
        if let observer = foregroundObserver {
            NotificationCenter.default.removeObserver(observer)
            foregroundObserver = nil
        }
        if let token = stateObserverToken {
            DarwinNotificationBridge.shared.removeObserver(
                name: DictationConstants.Notifications.stateChanged,
                token: token
            )
            stateObserverToken = nil
        }
    }

    // MARK: - Stale Check

    private func checkAndDismissIfStale() {
        // 세션 시작 전에는 stale check 하지 않음 (viewWillAppear → viewDidAppear 순서 보호)
        guard hasStartedSession else { return }
        guard let runtime = runtime else { return }
        let snapshot = runtime.currentSnapshot()

        bootstrapLog.debug("event=bootstrap_stale_check sid=\(self.sessionId.prefix(8), privacy: .public) runtimeActive=\(snapshot.isActive, privacy: .public) runtimeSid=\(snapshot.sessionId?.prefix(8) ?? "nil", privacy: .public)")

        // Case A/B: runtime이 더 이상 active가 아니거나 sessionId가 nil
        if !snapshot.isActive {
            bootstrapLog.debug("event=bootstrap_auto_dismiss reason=runtimeInactive sid=\(self.sessionId.prefix(8), privacy: .public)")
            stopObservers()
            dismiss(animated: true)
            return
        }

        // Case C: 현재 bootstrap의 sessionId와 runtime의 activeSessionId가 다름
        if let runtimeSid = snapshot.sessionId, runtimeSid != sessionId {
            bootstrapLog.debug("event=bootstrap_auto_dismiss reason=sessionMismatch sid=\(self.sessionId.prefix(8), privacy: .public) runtimeSid=\(runtimeSid.prefix(8), privacy: .public)")
            stopObservers()
            dismiss(animated: true)
            return
        }
    }

    // MARK: - Setup

    private func setupUI() {
        view.addSubview(returnHintLabel)
        view.addSubview(micIcon)
        view.addSubview(statusLabel)
        view.addSubview(hintLabel)
        view.addSubview(cancelButton)

        NSLayoutConstraint.activate([
            returnHintLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            returnHintLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),

            micIcon.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            micIcon.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),

            statusLabel.topAnchor.constraint(equalTo: micIcon.bottomAnchor, constant: 16),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            hintLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            hintLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            hintLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            cancelButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            cancelButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])
    }

    // MARK: - Session

    private func startSession() {
        guard let runtime = runtime else {
            showError("Runtime unavailable")
            return
        }

        guard SpeechRecognitionManager.isSpeechAuthorized && SpeechRecognitionManager.isMicAuthorized else {
            SpeechRecognitionManager.requestPermissions { [weak self] speech, mic in
                guard let self = self else { return }
                if speech && mic {
                    self.startSession()
                } else {
                    self.showPermissionError(speech: speech, mic: mic)
                }
            }
            return
        }

        let result = runtime.startSession(sessionId: sessionId, locale: locale, source: .coldStart)
        hasStartedSession = true

        // DEBUG TRACE: VoiceRecognition investigation
        switch result {
        case .accepted(let sid):
            bootstrapLog.debug("event=startSession_result result=accepted sid=\(sid.prefix(8), privacy: .public)")
        case .rejectedAlreadyActive(let activeId):
            bootstrapLog.debug("event=startSession_result result=rejectedAlreadyActive activeId=\(activeId.prefix(8), privacy: .public)")
        case .failedToStart(let msg):
            bootstrapLog.error("event=startSession_result result=failedToStart reason=\(msg, privacy: .public)")
        case .rejectedUnsupportedLocale:
            bootstrapLog.error("event=startSession_result result=rejectedUnsupportedLocale")
        case .rejectedPermissionRequired:
            bootstrapLog.error("event=startSession_result result=rejectedPermissionRequired")
        }

        switch result {
        case .accepted:
            statusLabel.text = "Dictation active"
            hintLabel.text = "Return to your app — dictation will continue"
            micIcon.tintColor = .systemGreen
            // returnGraceTimer는 runtime의 didChangePhase(.recording)에서 시작됨
            // bootstrap에서 중복 호출하지 않음

        case .rejectedAlreadyActive(let activeId):
            statusLabel.text = "Already recording"
            hintLabel.text = "Session \(String(activeId.prefix(8)))... is active.\nReturn to your app."
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.dismiss(animated: true)
            }

        case .rejectedUnsupportedLocale:
            showError("Language not supported for dictation")

        case .rejectedPermissionRequired:
            showPermissionError(speech: false, mic: false)

        case .failedToStart(let message):
            showError(message)
        }
    }

    private func showError(_ message: String) {
        statusLabel.text = "Error"
        hintLabel.text = message
        micIcon.tintColor = .systemGray
    }

    private func showPermissionError(speech: Bool, mic: Bool) {
        var message = ""
        if !mic { message += "Microphone access is required.\n" }
        if !speech { message += "Speech recognition access is required." }
        statusLabel.text = "Permission Required"
        hintLabel.text = message
        micIcon.tintColor = .systemGray
    }

    // MARK: - Actions

    @objc private func cancelTapped() {
        // DEBUG TRACE: VoiceRecognition investigation
        bootstrapLog.debug("event=cancelTapped sid=\(self.sessionId.prefix(8), privacy: .public)")
        stopObservers()
        runtime?.cancelSession(reason: .userCancelledDuringBootstrap)
        dismiss(animated: true)
    }
}
