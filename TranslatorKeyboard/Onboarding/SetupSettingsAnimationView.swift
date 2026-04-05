import UIKit

/// iPhone 설정 화면을 닮은 미니 애니메이션 가이드.
/// Stage 1: 앱 설정 루트 → Stage 2: 키보드 상세 → Stage 3: 얼럿 → Stage 4: 토글 ON → 루프
final class SetupSettingsAnimationView: UIView {

    // MARK: - Stage

    private enum Stage: Int {
        case root = 0      // 앱 설정 루트
        case keyboard      // 키보드 상세
        case alert         // 허용 얼럿
        case done          // 토글 ON
    }

    // MARK: - Subviews

    private let containerView = UIView()       // 미니 설정 화면 프레임
    private let navBar = UIView()
    private let navTitleLabel = UILabel()
    private let backLabel = UILabel()
    private let backChevron = UIImageView()

    // Stage 1 — root
    private let rootCard = UIView()
    private let keyboardRow = UIView()
    private let keyboardRowLabel = UILabel()
    private let keyboardRowChevron = UIImageView()
    private let keyboardRowHighlight = UIView()

    // Stage 2 — keyboard detail
    private let detailCard = UIView()
    private let translatorRow = UIView()
    private let translatorLabel = UILabel()
    private let translatorToggle = MiniToggleView()
    private let fullAccessRow = UIView()
    private let fullAccessIcon = UIImageView()
    private let fullAccessLabel = UILabel()
    private let fullAccessToggle = MiniToggleView()
    private let detailSeparator = UIView()

    // Stage 3 — alert
    private let dimOverlay = UIView()
    private let alertContainer = UIView()
    private let alertTitleLabel = UILabel()
    private let alertBodyLabel = UILabel()
    private let alertButtonSeparator = UIView()
    private let alertDenyButton = UILabel()
    private let alertAllowButton = UILabel()
    private let alertVerticalSep = UIView()

    // MARK: - State

    private var currentStage: Stage = .root
    private var loopTimer: Timer?
    private var isAnimating = false

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
        applyLocalizedText()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
        applyLocalizedText()
    }

    // MARK: - Public API

    func startLoop() {
        guard !isAnimating else { return }
        isAnimating = true
        resetToStage(.root, animated: false)
        scheduleNextStage()
    }

    func stopLoop() {
        isAnimating = false
        loopTimer?.invalidate()
        loopTimer = nil
    }

    func applyLocalizedText() {
        navTitleLabel.text = L("onboarding.setup.anim.nav.root")
        keyboardRowLabel.text = L("onboarding.setup.anim.row.keyboard")
        translatorLabel.text = "Translator KB"
        fullAccessLabel.text = L("onboarding.setup.anim.row.full_access")
        alertTitleLabel.text = L("onboarding.setup.anim.alert.title")
        alertBodyLabel.text = L("onboarding.setup.anim.alert.body")
        alertDenyButton.text = L("onboarding.setup.anim.alert.deny")
        alertAllowButton.text = L("onboarding.setup.anim.alert.allow")
    }

    // MARK: - Setup Views

    private func setupViews() {
        // Container — 미니 설정 화면 프레임
        containerView.backgroundColor = UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1.0) // iOS Settings bg
        containerView.layer.cornerRadius = 12
        containerView.clipsToBounds = true
        containerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(containerView)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        setupNavBar()
        setupRootCard()
        setupDetailCard()
        setupAlertOverlay()
    }

    private func setupNavBar() {
        navBar.backgroundColor = UIColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 1.0)
        navBar.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(navBar)

        navTitleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        navTitleLabel.textAlignment = .center
        navTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        navBar.addSubview(navTitleLabel)

        backChevron.image = UIImage(systemName: "chevron.left")
        backChevron.tintColor = .systemBlue
        backChevron.contentMode = .scaleAspectFit
        backChevron.translatesAutoresizingMaskIntoConstraints = false
        navBar.addSubview(backChevron)

        backLabel.text = ""
        backLabel.font = .systemFont(ofSize: 12)
        backLabel.textColor = .systemBlue
        backLabel.translatesAutoresizingMaskIntoConstraints = false
        navBar.addSubview(backLabel)

        // Separator
        let navSep = UIView()
        navSep.backgroundColor = .separator
        navSep.translatesAutoresizingMaskIntoConstraints = false
        navBar.addSubview(navSep)

        NSLayoutConstraint.activate([
            navBar.topAnchor.constraint(equalTo: containerView.topAnchor),
            navBar.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            navBar.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            navBar.heightAnchor.constraint(equalToConstant: 32),

            navTitleLabel.centerXAnchor.constraint(equalTo: navBar.centerXAnchor),
            navTitleLabel.centerYAnchor.constraint(equalTo: navBar.centerYAnchor),

            backChevron.leadingAnchor.constraint(equalTo: navBar.leadingAnchor, constant: 8),
            backChevron.centerYAnchor.constraint(equalTo: navBar.centerYAnchor),
            backChevron.widthAnchor.constraint(equalToConstant: 10),
            backChevron.heightAnchor.constraint(equalToConstant: 14),

            backLabel.leadingAnchor.constraint(equalTo: backChevron.trailingAnchor, constant: 2),
            backLabel.centerYAnchor.constraint(equalTo: navBar.centerYAnchor),

            navSep.bottomAnchor.constraint(equalTo: navBar.bottomAnchor),
            navSep.leadingAnchor.constraint(equalTo: navBar.leadingAnchor),
            navSep.trailingAnchor.constraint(equalTo: navBar.trailingAnchor),
            navSep.heightAnchor.constraint(equalToConstant: 0.5),
        ])

        backChevron.alpha = 0
        backLabel.alpha = 0
    }

    private func setupRootCard() {
        rootCard.backgroundColor = .white
        rootCard.layer.cornerRadius = 8
        rootCard.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(rootCard)

        // Keyboard row
        keyboardRowLabel.font = .systemFont(ofSize: 13)
        keyboardRowLabel.translatesAutoresizingMaskIntoConstraints = false

        let kbIcon = UIImageView()
        kbIcon.image = UIImage(systemName: "keyboard")
        kbIcon.tintColor = .gray
        kbIcon.contentMode = .scaleAspectFit
        kbIcon.translatesAutoresizingMaskIntoConstraints = false

        keyboardRowChevron.image = UIImage(systemName: "chevron.right")
        keyboardRowChevron.tintColor = UIColor(white: 0.78, alpha: 1.0)
        keyboardRowChevron.contentMode = .scaleAspectFit
        keyboardRowChevron.translatesAutoresizingMaskIntoConstraints = false

        keyboardRowHighlight.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.08)
        keyboardRowHighlight.layer.cornerRadius = 6
        keyboardRowHighlight.alpha = 0
        keyboardRowHighlight.translatesAutoresizingMaskIntoConstraints = false

        keyboardRow.translatesAutoresizingMaskIntoConstraints = false
        rootCard.addSubview(keyboardRow)
        keyboardRow.addSubview(keyboardRowHighlight)
        keyboardRow.addSubview(kbIcon)
        keyboardRow.addSubview(keyboardRowLabel)
        keyboardRow.addSubview(keyboardRowChevron)

        NSLayoutConstraint.activate([
            rootCard.topAnchor.constraint(equalTo: navBar.bottomAnchor, constant: 12),
            rootCard.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 10),
            rootCard.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -10),

            keyboardRow.topAnchor.constraint(equalTo: rootCard.topAnchor),
            keyboardRow.leadingAnchor.constraint(equalTo: rootCard.leadingAnchor),
            keyboardRow.trailingAnchor.constraint(equalTo: rootCard.trailingAnchor),
            keyboardRow.heightAnchor.constraint(equalToConstant: 36),
            keyboardRow.bottomAnchor.constraint(equalTo: rootCard.bottomAnchor),

            keyboardRowHighlight.topAnchor.constraint(equalTo: keyboardRow.topAnchor, constant: 2),
            keyboardRowHighlight.bottomAnchor.constraint(equalTo: keyboardRow.bottomAnchor, constant: -2),
            keyboardRowHighlight.leadingAnchor.constraint(equalTo: keyboardRow.leadingAnchor, constant: 4),
            keyboardRowHighlight.trailingAnchor.constraint(equalTo: keyboardRow.trailingAnchor, constant: -4),

            kbIcon.leadingAnchor.constraint(equalTo: keyboardRow.leadingAnchor, constant: 10),
            kbIcon.centerYAnchor.constraint(equalTo: keyboardRow.centerYAnchor),
            kbIcon.widthAnchor.constraint(equalToConstant: 18),
            kbIcon.heightAnchor.constraint(equalToConstant: 18),

            keyboardRowLabel.leadingAnchor.constraint(equalTo: kbIcon.trailingAnchor, constant: 8),
            keyboardRowLabel.centerYAnchor.constraint(equalTo: keyboardRow.centerYAnchor),

            keyboardRowChevron.trailingAnchor.constraint(equalTo: keyboardRow.trailingAnchor, constant: -10),
            keyboardRowChevron.centerYAnchor.constraint(equalTo: keyboardRow.centerYAnchor),
            keyboardRowChevron.widthAnchor.constraint(equalToConstant: 8),
            keyboardRowChevron.heightAnchor.constraint(equalToConstant: 12),
        ])
    }

    private func setupDetailCard() {
        detailCard.backgroundColor = .white
        detailCard.layer.cornerRadius = 8
        detailCard.alpha = 0
        detailCard.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(detailCard)

        // Translator KB row
        translatorRow.translatesAutoresizingMaskIntoConstraints = false
        translatorLabel.font = .systemFont(ofSize: 13)
        translatorLabel.translatesAutoresizingMaskIntoConstraints = false
        translatorToggle.translatesAutoresizingMaskIntoConstraints = false
        translatorToggle.setOn(true, animated: false)

        detailCard.addSubview(translatorRow)
        translatorRow.addSubview(translatorLabel)
        translatorRow.addSubview(translatorToggle)

        // Separator
        detailSeparator.backgroundColor = UIColor(white: 0.92, alpha: 1.0)
        detailSeparator.translatesAutoresizingMaskIntoConstraints = false
        detailCard.addSubview(detailSeparator)

        // Full Access row
        fullAccessRow.translatesAutoresizingMaskIntoConstraints = false
        fullAccessIcon.image = UIImage(systemName: "keyboard")
        fullAccessIcon.tintColor = .gray
        fullAccessIcon.contentMode = .scaleAspectFit
        fullAccessIcon.translatesAutoresizingMaskIntoConstraints = false
        fullAccessLabel.font = .systemFont(ofSize: 13)
        fullAccessLabel.translatesAutoresizingMaskIntoConstraints = false
        fullAccessToggle.translatesAutoresizingMaskIntoConstraints = false
        fullAccessToggle.setOn(false, animated: false)

        detailCard.addSubview(fullAccessRow)
        fullAccessRow.addSubview(fullAccessIcon)
        fullAccessRow.addSubview(fullAccessLabel)
        fullAccessRow.addSubview(fullAccessToggle)

        NSLayoutConstraint.activate([
            detailCard.topAnchor.constraint(equalTo: navBar.bottomAnchor, constant: 12),
            detailCard.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 10),
            detailCard.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -10),

            translatorRow.topAnchor.constraint(equalTo: detailCard.topAnchor),
            translatorRow.leadingAnchor.constraint(equalTo: detailCard.leadingAnchor),
            translatorRow.trailingAnchor.constraint(equalTo: detailCard.trailingAnchor),
            translatorRow.heightAnchor.constraint(equalToConstant: 36),

            translatorLabel.leadingAnchor.constraint(equalTo: translatorRow.leadingAnchor, constant: 12),
            translatorLabel.centerYAnchor.constraint(equalTo: translatorRow.centerYAnchor),
            translatorToggle.trailingAnchor.constraint(equalTo: translatorRow.trailingAnchor, constant: -10),
            translatorToggle.centerYAnchor.constraint(equalTo: translatorRow.centerYAnchor),

            detailSeparator.topAnchor.constraint(equalTo: translatorRow.bottomAnchor),
            detailSeparator.leadingAnchor.constraint(equalTo: detailCard.leadingAnchor, constant: 12),
            detailSeparator.trailingAnchor.constraint(equalTo: detailCard.trailingAnchor),
            detailSeparator.heightAnchor.constraint(equalToConstant: 0.5),

            fullAccessRow.topAnchor.constraint(equalTo: detailSeparator.bottomAnchor),
            fullAccessRow.leadingAnchor.constraint(equalTo: detailCard.leadingAnchor),
            fullAccessRow.trailingAnchor.constraint(equalTo: detailCard.trailingAnchor),
            fullAccessRow.heightAnchor.constraint(equalToConstant: 36),
            fullAccessRow.bottomAnchor.constraint(equalTo: detailCard.bottomAnchor),

            fullAccessIcon.leadingAnchor.constraint(equalTo: fullAccessRow.leadingAnchor, constant: 10),
            fullAccessIcon.centerYAnchor.constraint(equalTo: fullAccessRow.centerYAnchor),
            fullAccessIcon.widthAnchor.constraint(equalToConstant: 18),
            fullAccessIcon.heightAnchor.constraint(equalToConstant: 18),

            fullAccessLabel.leadingAnchor.constraint(equalTo: fullAccessIcon.trailingAnchor, constant: 8),
            fullAccessLabel.centerYAnchor.constraint(equalTo: fullAccessRow.centerYAnchor),

            fullAccessToggle.trailingAnchor.constraint(equalTo: fullAccessRow.trailingAnchor, constant: -10),
            fullAccessToggle.centerYAnchor.constraint(equalTo: fullAccessRow.centerYAnchor),
        ])
    }

    private func setupAlertOverlay() {
        // Dim
        dimOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        dimOverlay.alpha = 0
        dimOverlay.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(dimOverlay)

        // Alert
        alertContainer.backgroundColor = UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1.0)
        alertContainer.layer.cornerRadius = 10
        alertContainer.alpha = 0
        alertContainer.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
        alertContainer.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(alertContainer)

        alertTitleLabel.font = .systemFont(ofSize: 11, weight: .bold)
        alertTitleLabel.textAlignment = .center
        alertTitleLabel.numberOfLines = 0
        alertTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        alertContainer.addSubview(alertTitleLabel)

        alertBodyLabel.font = .systemFont(ofSize: 9)
        alertBodyLabel.textColor = .secondaryLabel
        alertBodyLabel.textAlignment = .center
        alertBodyLabel.numberOfLines = 0
        alertBodyLabel.translatesAutoresizingMaskIntoConstraints = false
        alertContainer.addSubview(alertBodyLabel)

        alertButtonSeparator.backgroundColor = .separator
        alertButtonSeparator.translatesAutoresizingMaskIntoConstraints = false
        alertContainer.addSubview(alertButtonSeparator)

        alertDenyButton.font = .systemFont(ofSize: 11)
        alertDenyButton.textColor = .systemBlue
        alertDenyButton.textAlignment = .center
        alertDenyButton.translatesAutoresizingMaskIntoConstraints = false
        alertContainer.addSubview(alertDenyButton)

        alertAllowButton.font = .systemFont(ofSize: 11, weight: .semibold)
        alertAllowButton.textColor = .systemBlue
        alertAllowButton.textAlignment = .center
        alertAllowButton.translatesAutoresizingMaskIntoConstraints = false
        alertContainer.addSubview(alertAllowButton)

        alertVerticalSep.backgroundColor = .separator
        alertVerticalSep.translatesAutoresizingMaskIntoConstraints = false
        alertContainer.addSubview(alertVerticalSep)

        NSLayoutConstraint.activate([
            dimOverlay.topAnchor.constraint(equalTo: containerView.topAnchor),
            dimOverlay.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            dimOverlay.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            dimOverlay.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),

            alertContainer.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            alertContainer.centerYAnchor.constraint(equalTo: containerView.centerYAnchor, constant: 10),
            alertContainer.widthAnchor.constraint(equalTo: containerView.widthAnchor, multiplier: 0.75),

            alertTitleLabel.topAnchor.constraint(equalTo: alertContainer.topAnchor, constant: 12),
            alertTitleLabel.leadingAnchor.constraint(equalTo: alertContainer.leadingAnchor, constant: 12),
            alertTitleLabel.trailingAnchor.constraint(equalTo: alertContainer.trailingAnchor, constant: -12),

            alertBodyLabel.topAnchor.constraint(equalTo: alertTitleLabel.bottomAnchor, constant: 6),
            alertBodyLabel.leadingAnchor.constraint(equalTo: alertContainer.leadingAnchor, constant: 12),
            alertBodyLabel.trailingAnchor.constraint(equalTo: alertContainer.trailingAnchor, constant: -12),

            alertButtonSeparator.topAnchor.constraint(equalTo: alertBodyLabel.bottomAnchor, constant: 12),
            alertButtonSeparator.leadingAnchor.constraint(equalTo: alertContainer.leadingAnchor),
            alertButtonSeparator.trailingAnchor.constraint(equalTo: alertContainer.trailingAnchor),
            alertButtonSeparator.heightAnchor.constraint(equalToConstant: 0.5),

            alertDenyButton.topAnchor.constraint(equalTo: alertButtonSeparator.bottomAnchor),
            alertDenyButton.leadingAnchor.constraint(equalTo: alertContainer.leadingAnchor),
            alertDenyButton.widthAnchor.constraint(equalTo: alertContainer.widthAnchor, multiplier: 0.5),
            alertDenyButton.heightAnchor.constraint(equalToConstant: 32),
            alertDenyButton.bottomAnchor.constraint(equalTo: alertContainer.bottomAnchor),

            alertAllowButton.topAnchor.constraint(equalTo: alertButtonSeparator.bottomAnchor),
            alertAllowButton.trailingAnchor.constraint(equalTo: alertContainer.trailingAnchor),
            alertAllowButton.widthAnchor.constraint(equalTo: alertContainer.widthAnchor, multiplier: 0.5),
            alertAllowButton.heightAnchor.constraint(equalToConstant: 32),

            alertVerticalSep.topAnchor.constraint(equalTo: alertButtonSeparator.bottomAnchor),
            alertVerticalSep.bottomAnchor.constraint(equalTo: alertContainer.bottomAnchor),
            alertVerticalSep.centerXAnchor.constraint(equalTo: alertContainer.centerXAnchor),
            alertVerticalSep.widthAnchor.constraint(equalToConstant: 0.5),
        ])
    }

    // MARK: - Animation Loop

    private func scheduleNextStage() {
        guard isAnimating else { return }
        let delay: TimeInterval
        switch currentStage {
        case .root:     delay = 1.2
        case .keyboard: delay = 1.2
        case .alert:    delay = 1.5
        case .done:     delay = 1.0
        }
        loopTimer?.invalidate()
        loopTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.advanceStage()
        }
    }

    private func advanceStage() {
        guard isAnimating else { return }
        let next: Stage
        switch currentStage {
        case .root:     next = .keyboard
        case .keyboard: next = .alert
        case .alert:    next = .done
        case .done:     next = .root
        }
        resetToStage(next, animated: true)
        scheduleNextStage()
    }

    private func resetToStage(_ stage: Stage, animated: Bool) {
        currentStage = stage
        let dur: TimeInterval = animated ? 0.35 : 0.0

        UIView.animate(withDuration: dur, delay: 0, options: .curveEaseInOut) {
            switch stage {
            case .root:
                self.navTitleLabel.text = L("onboarding.setup.anim.nav.root")
                self.backChevron.alpha = 0
                self.backLabel.alpha = 0
                self.rootCard.alpha = 1
                self.detailCard.alpha = 0
                self.dimOverlay.alpha = 0
                self.alertContainer.alpha = 0
                self.alertContainer.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
                self.keyboardRowHighlight.alpha = 1
                self.fullAccessToggle.setOn(false, animated: false)

            case .keyboard:
                self.navTitleLabel.text = L("onboarding.setup.anim.nav.keyboard")
                self.backChevron.alpha = 1
                self.backLabel.alpha = 1
                self.rootCard.alpha = 0
                self.detailCard.alpha = 1
                self.dimOverlay.alpha = 0
                self.alertContainer.alpha = 0
                self.alertContainer.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
                self.keyboardRowHighlight.alpha = 0
                self.fullAccessToggle.setOn(false, animated: false)

            case .alert:
                self.dimOverlay.alpha = 1
                self.alertContainer.alpha = 1
                self.alertContainer.transform = .identity

            case .done:
                self.dimOverlay.alpha = 0
                self.alertContainer.alpha = 0
                self.alertContainer.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
                self.fullAccessToggle.setOn(true, animated: true)
            }
        }
    }
}

// MARK: - Mini Toggle View

private final class MiniToggleView: UIView {

    private let track = UIView()
    private let thumb = UIView()
    private var thumbLeading: NSLayoutConstraint!
    private var isOn = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        track.layer.cornerRadius = 8
        track.backgroundColor = UIColor(white: 0.88, alpha: 1.0)
        track.translatesAutoresizingMaskIntoConstraints = false
        addSubview(track)

        thumb.backgroundColor = .white
        thumb.layer.cornerRadius = 6.5
        thumb.layer.shadowColor = UIColor.black.cgColor
        thumb.layer.shadowOpacity = 0.15
        thumb.layer.shadowOffset = CGSize(width: 0, height: 1)
        thumb.layer.shadowRadius = 1
        thumb.translatesAutoresizingMaskIntoConstraints = false
        addSubview(thumb)

        thumbLeading = thumb.leadingAnchor.constraint(equalTo: track.leadingAnchor, constant: 1)

        NSLayoutConstraint.activate([
            track.centerYAnchor.constraint(equalTo: centerYAnchor),
            track.leadingAnchor.constraint(equalTo: leadingAnchor),
            track.widthAnchor.constraint(equalToConstant: 30),
            track.heightAnchor.constraint(equalToConstant: 16),

            widthAnchor.constraint(equalToConstant: 30),
            heightAnchor.constraint(equalToConstant: 16),

            thumb.centerYAnchor.constraint(equalTo: track.centerYAnchor),
            thumb.widthAnchor.constraint(equalToConstant: 13),
            thumb.heightAnchor.constraint(equalToConstant: 13),
            thumbLeading,
        ])
    }

    func setOn(_ on: Bool, animated: Bool) {
        isOn = on
        let action = {
            self.thumbLeading.constant = on ? 16 : 1
            self.track.backgroundColor = on ? .systemGreen : UIColor(white: 0.88, alpha: 1.0)
            self.layoutIfNeeded()
        }
        if animated {
            UIView.animate(withDuration: 0.25, animations: action)
        } else {
            action()
        }
    }
}
