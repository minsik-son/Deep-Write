import UIKit

protocol DictationOverlayViewDelegate: AnyObject {
    func dictationOverlayDidTapBack()
    func dictationOverlayDidTapPause()
    func dictationOverlayDidTapResume()
    func dictationOverlayDidTapCancel()
    func dictationOverlayDidTapClear()
    /// X button: stop recognition but keep inserted text
    func dictationOverlayDidTapStop()
}

final class DictationOverlayView: UIView {

    weak var delegate: DictationOverlayViewDelegate?

    private(set) var isPaused: Bool = false

    // MARK: - UI Components

    private let micIndicator: UIView = {
        let v = UIView()
        v.backgroundColor = .systemRed
        v.layer.cornerRadius = 8
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let statusLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 14, weight: .semibold)
        l.textColor = .white
        l.text = "Listening..."
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let localeBadge: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 11, weight: .medium)
        l.textColor = UIColor(white: 0.7, alpha: 1)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let previewLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 13)
        l.textColor = UIColor(white: 0.6, alpha: 1)
        l.textAlignment = .center
        l.numberOfLines = 2
        l.lineBreakMode = .byTruncatingTail
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let pauseButton: UIButton = {
        let btn = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        btn.setImage(UIImage(systemName: "pause.fill", withConfiguration: config), for: .normal)
        btn.tintColor = .white
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let cancelButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("Cancel", for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        btn.setTitleColor(UIColor(white: 0.7, alpha: 1), for: .normal)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let clearButton: UIButton = {
        let btn = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        btn.setImage(UIImage(systemName: "trash", withConfiguration: config), for: .normal)
        btn.tintColor = UIColor(white: 0.5, alpha: 1)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.isHidden = true
        return btn
    }()

    /// X button — stop recognition, keep inserted text
    private let stopButton: UIButton = {
        let btn = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        btn.setImage(UIImage(systemName: "xmark.circle.fill", withConfiguration: config), for: .normal)
        btn.tintColor = .white
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let backButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("←", for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 18, weight: .medium)
        btn.setTitleColor(UIColor(white: 0.7, alpha: 1), for: .normal)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        setupActions()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupUI() {
        backgroundColor = UIColor(white: 0.1, alpha: 1)

        addSubview(backButton)
        addSubview(micIndicator)
        addSubview(statusLabel)
        addSubview(localeBadge)
        addSubview(previewLabel)
        addSubview(pauseButton)
        addSubview(cancelButton)
        addSubview(clearButton)
        addSubview(stopButton)

        NSLayoutConstraint.activate([
            backButton.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            backButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            backButton.widthAnchor.constraint(equalToConstant: 28),
            backButton.heightAnchor.constraint(equalToConstant: 28),

            micIndicator.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            micIndicator.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 8),
            micIndicator.widthAnchor.constraint(equalToConstant: 16),
            micIndicator.heightAnchor.constraint(equalToConstant: 16),

            statusLabel.centerYAnchor.constraint(equalTo: micIndicator.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: micIndicator.trailingAnchor, constant: 8),

            localeBadge.centerYAnchor.constraint(equalTo: micIndicator.centerYAnchor),
            localeBadge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),

            previewLabel.topAnchor.constraint(equalTo: backButton.bottomAnchor, constant: 12),
            previewLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            previewLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            pauseButton.topAnchor.constraint(equalTo: previewLabel.bottomAnchor, constant: 16),
            pauseButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            pauseButton.widthAnchor.constraint(equalToConstant: 44),
            pauseButton.heightAnchor.constraint(equalToConstant: 44),

            cancelButton.centerYAnchor.constraint(equalTo: pauseButton.centerYAnchor),
            cancelButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),

            clearButton.centerYAnchor.constraint(equalTo: pauseButton.centerYAnchor),
            clearButton.leadingAnchor.constraint(equalTo: pauseButton.trailingAnchor, constant: 24),

            stopButton.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stopButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stopButton.widthAnchor.constraint(equalToConstant: 32),
            stopButton.heightAnchor.constraint(equalToConstant: 32),
        ])
    }

    private func setupActions() {
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        pauseButton.addTarget(self, action: #selector(pauseTapped), for: .touchUpInside)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        clearButton.addTarget(self, action: #selector(clearTapped), for: .touchUpInside)
        stopButton.addTarget(self, action: #selector(stopTapped), for: .touchUpInside)
    }

    // MARK: - Public API

    func updateLocale(_ identifier: String) {
        localeBadge.text = Locale(identifier: identifier).localizedString(forIdentifier: identifier) ?? identifier
    }

    func updateStatus(_ text: String) {
        statusLabel.text = text
    }

    func updatePreviewOnly(_ text: String) {
        previewLabel.text = text.isEmpty ? "" : "..." + String(text.suffix(80))
        clearButton.isHidden = text.isEmpty
    }

    func setRecordingState() {
        isPaused = false
        micIndicator.backgroundColor = .systemRed
        statusLabel.text = "Listening..."
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        pauseButton.setImage(UIImage(systemName: "pause.fill", withConfiguration: config), for: .normal)
        startPulse()
    }

    func setPausedState() {
        isPaused = true
        micIndicator.backgroundColor = .systemOrange
        statusLabel.text = "Paused"
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        pauseButton.setImage(UIImage(systemName: "mic.fill", withConfiguration: config), for: .normal)
        stopPulse()
    }

    func setErrorState(_ message: String) {
        micIndicator.backgroundColor = .systemGray
        statusLabel.text = "Error"
        previewLabel.text = message
        stopPulse()
    }

    func reset() {
        isPaused = false
        previewLabel.text = ""
        clearButton.isHidden = true
        micIndicator.backgroundColor = .systemRed
        statusLabel.text = "Listening..."
        stopPulse()
    }

    // MARK: - Actions

    @objc private func backTapped() {
        delegate?.dictationOverlayDidTapBack()
    }

    @objc private func pauseTapped() {
        if isPaused {
            delegate?.dictationOverlayDidTapResume()
        } else {
            delegate?.dictationOverlayDidTapPause()
        }
    }

    @objc private func cancelTapped() {
        delegate?.dictationOverlayDidTapCancel()
    }

    @objc private func clearTapped() {
        delegate?.dictationOverlayDidTapClear()
    }

    /// X = stop voice, keep text
    @objc private func stopTapped() {
        delegate?.dictationOverlayDidTapStop()
    }

    // MARK: - Pulse Animation

    private func startPulse() {
        guard micIndicator.layer.animation(forKey: "pulse") == nil else { return }
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.3
        pulse.duration = 0.8
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        micIndicator.layer.add(pulse, forKey: "pulse")
    }

    private func stopPulse() {
        micIndicator.layer.removeAnimation(forKey: "pulse")
    }
}
