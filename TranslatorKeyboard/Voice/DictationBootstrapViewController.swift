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
/// No state observer. No auto-dismiss. No background handler.
/// dismiss는 Cancel 탭 또는 rejectedAlreadyActive 분기에서만 발생.
final class DictationBootstrapViewController: UIViewController {

    private var sessionId: String = ""
    private var locale: String = "en-US"
    private var runtime: AppDictationRuntime?

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
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // DEBUG TRACE: VoiceRecognition investigation
        bootstrapLog.debug("event=viewDidAppear sid=\(self.sessionId.prefix(8), privacy: .public)")
        startSession()
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
        runtime?.cancelSession(reason: .userCancelledDuringBootstrap)
        dismiss(animated: true)
    }
}
