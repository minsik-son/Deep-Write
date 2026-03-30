import UIKit

/// Bootstrap-only dictation screen.
/// Starts the speech engine then auto-dismisses so the user returns to the host app + keyboard overlay.
final class DictationViewController: UIViewController, DictationServiceDelegate {

    private let dictationService = DictationService()
    private var sessionId: String = ""
    private var locale: String = "en-US"
    private var didStartSession: Bool = false

    // MARK: - UI Components (minimal handoff screen)

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
        l.text = "Returning to your app..."
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

    // MARK: - Init

    func configure(sessionId: String, locale: String) {
        self.sessionId = sessionId
        self.locale = locale
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupUI()
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        dictationService.delegate = self
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didStartSession else { return }
        didStartSession = true
        startDictation()
    }

    // MARK: - Setup

    private func setupUI() {
        view.addSubview(micIcon)
        view.addSubview(statusLabel)
        view.addSubview(hintLabel)
        view.addSubview(cancelButton)

        NSLayoutConstraint.activate([
            micIcon.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            micIcon.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),

            statusLabel.topAnchor.constraint(equalTo: micIcon.bottomAnchor, constant: 16),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            hintLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            hintLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            cancelButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            cancelButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])
    }

    // MARK: - Dictation

    private func startDictation() {
        guard SpeechRecognitionManager.isSpeechAuthorized && SpeechRecognitionManager.isMicAuthorized else {
            SpeechRecognitionManager.requestPermissions { [weak self] speech, mic in
                guard let self = self else { return }
                if speech && mic {
                    self.startDictation()
                } else {
                    self.showPermissionError(speech: speech, mic: mic)
                }
            }
            return
        }

        // Start the engine
        dictationService.startSession(sessionId: sessionId, locale: locale)
    }

    private func showPermissionError(speech: Bool, mic: Bool) {
        var message = ""
        if !mic { message += "Microphone access is required.\n" }
        if !speech { message += "Speech recognition access is required." }

        statusLabel.text = "Permission Required"
        hintLabel.text = message
        micIcon.tintColor = .systemGray
    }

    /// Auto-dismiss after engine starts — user returns to host app + keyboard overlay
    private func autoDismiss() {
        hintLabel.text = "Return to your app to use dictation"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.dismiss(animated: true)
        }
    }

    // MARK: - Actions

    @objc private func cancelTapped() {
        dictationService.cancelSession()
        dismiss(animated: true)
    }

    // MARK: - DictationServiceDelegate

    func dictationService(_ service: DictationService, didChangePhase phase: DictationPhase) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            switch phase {
            case .recording:
                // Engine is running — auto-dismiss so user returns to keyboard
                self.statusLabel.text = "Dictation active"
                self.autoDismiss()
            case .preparing:
                self.statusLabel.text = "Starting..."
            case .error:
                self.statusLabel.text = "Error"
                self.micIcon.tintColor = .systemGray
                DispatchQueue.main.asyncAfter(deadline: .now() + DictationConstants.Limits.errorAutoResetDelay) { [weak self] in
                    self?.dismiss(animated: true)
                }
            case .completed:
                self.dismiss(animated: true)
            default:
                break
            }
        }
    }

    func dictationService(_ service: DictationService, didUpdatePartial text: String) {
        // Engine is running in background — no UI update needed here
        // Keyboard extension will receive partial via shared store + Darwin notification
    }

    func dictationService(_ service: DictationService, didFinishWith finalText: String) {
        // Final delivered via shared store to keyboard extension
    }

    func dictationService(_ service: DictationService, didFailWith message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.statusLabel.text = message
            self?.hintLabel.text = ""
        }
    }
}
