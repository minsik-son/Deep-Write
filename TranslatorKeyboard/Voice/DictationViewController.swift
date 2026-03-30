import UIKit

final class DictationViewController: UIViewController, DictationServiceDelegate {

    private let dictationService = DictationService()
    private var sessionId: String = ""
    private var locale: String = "en-US"

    // MARK: - UI Components

    private let micCircleView: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.systemRed
        v.layer.cornerRadius = 50
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let micIcon: UIImageView = {
        let iv = UIImageView()
        let config = UIImage.SymbolConfiguration(pointSize: 40, weight: .medium)
        iv.image = UIImage(systemName: "mic.fill", withConfiguration: config)
        iv.tintColor = .white
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let statusLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 18, weight: .semibold)
        l.textColor = .label
        l.textAlignment = .center
        l.text = "Listening..."
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let localeBadge: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 13, weight: .medium)
        l.textColor = .secondaryLabel
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let transcriptPreview: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 15)
        l.textColor = .secondaryLabel
        l.textAlignment = .center
        l.numberOfLines = 3
        l.lineBreakMode = .byTruncatingTail
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let returnHintLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 13)
        l.textColor = .tertiaryLabel
        l.textAlignment = .center
        l.text = "Return to your app to see the result"
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

    private let stopButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("Done", for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        btn.setTitleColor(.systemBlue, for: .normal)
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
        setupActions()

        dictationService.delegate = self
        localeBadge.text = Locale(identifier: locale).localizedString(forIdentifier: locale) ?? locale
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startDictation()
    }

    // MARK: - Setup

    private func setupUI() {
        view.addSubview(micCircleView)
        micCircleView.addSubview(micIcon)
        view.addSubview(statusLabel)
        view.addSubview(localeBadge)
        view.addSubview(transcriptPreview)
        view.addSubview(returnHintLabel)
        view.addSubview(cancelButton)
        view.addSubview(stopButton)

        NSLayoutConstraint.activate([
            micCircleView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            micCircleView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -80),
            micCircleView.widthAnchor.constraint(equalToConstant: 100),
            micCircleView.heightAnchor.constraint(equalToConstant: 100),

            micIcon.centerXAnchor.constraint(equalTo: micCircleView.centerXAnchor),
            micIcon.centerYAnchor.constraint(equalTo: micCircleView.centerYAnchor),

            statusLabel.topAnchor.constraint(equalTo: micCircleView.bottomAnchor, constant: 24),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            localeBadge.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            localeBadge.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            transcriptPreview.topAnchor.constraint(equalTo: localeBadge.bottomAnchor, constant: 20),
            transcriptPreview.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            transcriptPreview.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            returnHintLabel.topAnchor.constraint(equalTo: transcriptPreview.bottomAnchor, constant: 24),
            returnHintLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            cancelButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            cancelButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),

            stopButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            stopButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
        ])
    }

    private func setupActions() {
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        stopButton.addTarget(self, action: #selector(stopTapped), for: .touchUpInside)
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

        dictationService.startSession(sessionId: sessionId, locale: locale)
    }

    private func showPermissionError(speech: Bool, mic: Bool) {
        var message = ""
        if !mic { message += "Microphone access is required.\n" }
        if !speech { message += "Speech recognition access is required." }

        statusLabel.text = "Permission Required"
        transcriptPreview.text = message
        micCircleView.backgroundColor = .systemGray
    }

    // MARK: - Actions

    @objc private func cancelTapped() {
        dictationService.cancelSession()
        dismiss(animated: true)
    }

    @objc private func stopTapped() {
        dictationService.stopSession()
    }

    // MARK: - DictationServiceDelegate

    func dictationService(_ service: DictationService, didChangePhase phase: DictationPhase) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            switch phase {
            case .recording:
                self.statusLabel.text = "Listening..."
                self.micCircleView.backgroundColor = .systemRed
                self.startPulseAnimation()
            case .paused:
                self.statusLabel.text = "Paused"
                self.micCircleView.backgroundColor = .systemOrange
                self.stopPulseAnimation()
            case .preparing:
                self.statusLabel.text = "Preparing..."
                self.micCircleView.backgroundColor = .systemYellow
            case .completed:
                self.statusLabel.text = "Done"
                self.micCircleView.backgroundColor = .systemGreen
                self.stopPulseAnimation()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.dismiss(animated: true)
                }
            case .error:
                self.statusLabel.text = "Error"
                self.micCircleView.backgroundColor = .systemGray
                self.stopPulseAnimation()
                DispatchQueue.main.asyncAfter(deadline: .now() + DictationConstants.Limits.errorAutoResetDelay) { [weak self] in
                    self?.dismiss(animated: true)
                }
            default:
                break
            }
        }
    }

    func dictationService(_ service: DictationService, didUpdatePartial text: String) {
        DispatchQueue.main.async { [weak self] in
            // Redacted for privacy — show length only
            self?.transcriptPreview.text = "Transcribing... (\(text.count) chars)"
        }
    }

    func dictationService(_ service: DictationService, didFinishWith finalText: String) {
        DispatchQueue.main.async { [weak self] in
            self?.transcriptPreview.text = "Dictation complete (\(finalText.count) chars)"
        }
    }

    func dictationService(_ service: DictationService, didFailWith message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.transcriptPreview.text = message
        }
    }

    // MARK: - Pulse Animation

    private func startPulseAnimation() {
        let pulse = CABasicAnimation(keyPath: "transform.scale")
        pulse.fromValue = 1.0
        pulse.toValue = 1.08
        pulse.duration = 0.8
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        micCircleView.layer.add(pulse, forKey: "pulse")
    }

    private func stopPulseAnimation() {
        micCircleView.layer.removeAnimation(forKey: "pulse")
    }
}
