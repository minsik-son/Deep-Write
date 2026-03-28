import UIKit

// MARK: - ChatReplyRequest

struct ChatReplyRequest {
    let context: String
    let tone: String
    let direction: String
    let language: String
}

// MARK: - ChatReplyGeneratorView

final class ChatReplyGeneratorView: UIView {

    // MARK: - Callbacks (모두 weak self로 설정될 것)
    var onClose: (() -> Void)?
    var onInsert: ((String) -> Void)?
    var onRequestGenerate: ((ChatReplyRequest) -> Void)?
    var onRequestRegenerate: (() -> Void)?
    var onToneChanged: (() -> Void)?
    var onCopy: ((String) -> Void)?

    // MARK: - AI Disclosure (Apple Guideline 4.7)
    private let aiDisclosureLabel = UILabel()

    // MARK: - Internal State
    enum SubState {
        case setup
        case loading
        case results
        case error
    }

    private(set) var currentSubState: SubState = .setup

    // MARK: - Session State
    private(set) var selectedToneIndex: Int = 0
    private var directionText: String = ""
    private(set) var contextMessage: String = ""
    private var currentReplies: [String] = []

    // MARK: - Tone Options
    static let toneOptionKeys: [String] = [
        "chatreply.tone.friendly",
        "chatreply.tone.polite",
        "chatreply.tone.cool",
        "chatreply.tone.witty",
        "chatreply.tone.professional",
        "chatreply.tone.romantic",
        "chatreply.tone.direct",
        "chatreply.tone.thoughtful"
    ]

    static let toneAPIValues: [String] = [
        "Friendly", "Polite", "Cool", "Witty",
        "Professional", "Romantic", "Direct", "Thoughtful"
    ]

    private var cachedToneDisplayNames: [String] = []

    // MARK: - UI Components — Context Banner
    private let contextBannerView = UIView()
    private let contextIconView = UIView()
    private let contextLabel = UILabel()
    private let closeButton = UIButton(type: .custom)

    // MARK: - UI Components — Tone Grid
    private let toneSectionLabel = UILabel()
    private let toneGridStack = UIStackView()
    private var toneButtons: [UIButton] = []

    // MARK: - UI Components — Direction Input
    private let directionSectionLabel = UILabel()
    private let directionInputContainer = UIView()
    private let directionDisplayLabel = UILabel()
    private let directionCursorView = UIView()
    private let directionPlaceholder = UILabel()
    private let directionSendButton = UIButton(type: .custom)
    private let skipLabel = UILabel()

    // MARK: - UI Components — Loading
    private let loadingContainer = UIView()
    private let loadingDots: [UIView] = [UIView(), UIView(), UIView()]
    private let loadingLabel = UILabel()
    private var loadingTimer: Timer?

    // MARK: - UI Components — Reply Cards
    private let replyContainer = UIView()
    private let replyCardsStack = UIStackView()
    private var replyCards: [ChatReplyCard] = []
    private let directionTagView = UIView()
    private let directionTagLabel = UILabel()
    private let toneBadge = UIButton(type: .custom)
    private let regenerateButton = UIButton(type: .custom)

    // MARK: - UI Components — Error
    private let errorContainer = UIView()
    private let errorLabel = UILabel()
    private let retryButton = UIButton(type: .custom)

    // MARK: - Theme
    private var customTheme: KeyboardTheme?
    private var isDark: Bool = false

    // MARK: - Haptic
    private let hapticFeedback = UIImpactFeedbackGenerator(style: .light)

    // MARK: - Cursor Animation
    private var cursorTimer: Timer?

    // MARK: - Init
    override init(frame: CGRect) {
        super.init(frame: frame)
        hapticFeedback.prepare()
        cachedToneDisplayNames = Self.toneOptionKeys.map { L($0) }
        setupUI()
        setupActions()
        showSubState(.setup)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        cursorTimer?.invalidate()
        cursorTimer = nil
        loadingTimer?.invalidate()
        loadingTimer = nil
    }

    // MARK: - Public Interface

    func setContext(_ message: String) {
        let trimmed = String(message.prefix(500))
        contextMessage = trimmed
        contextLabel.text = trimmed
        contextBannerView.accessibilityValue = contextMessage
    }

    func setDirectionText(_ text: String) {
        directionText = text
        directionDisplayLabel.text = text
        directionPlaceholder.isHidden = !text.isEmpty
        directionCursorView.isHidden = text.isEmpty && currentSubState != .setup
        directionSendButton.isEnabled = true
        updateDirectionSendButtonAppearance()
    }

    func displayReplies(_ replies: [String]) {
        guard !replies.isEmpty else {
            showError(L("chatreply.error.no_replies"))
            return
        }
        currentReplies = replies
        buildReplyCards(replies)
        showSubState(.results)
    }

    func showError(_ message: String) {
        errorLabel.text = message
        showSubState(.error)
    }

    func applyTheme(_ theme: KeyboardTheme?) {
        customTheme = theme
        applyColors()
    }

    func updateAppearance(isDark: Bool) {
        self.isDark = isDark
        applyColors()
    }

    func prepareForDismiss() {
        cursorTimer?.invalidate()
        cursorTimer = nil
        loadingTimer?.invalidate()
        loadingTimer = nil

        for card in replyCards {
            card.layer.sublayers?.removeAll(where: { $0 is CAGradientLayer })
        }
        replyCards.removeAll()
        replyCardsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        currentReplies.removeAll()
        aiDisclosureLabel.removeFromSuperview()
    }
}

// MARK: - Setup UI

extension ChatReplyGeneratorView {

    private func setupUI() {
        backgroundColor = UIColor.systemBackground

        // ---- Context Banner ----
        contextBannerView.translatesAutoresizingMaskIntoConstraints = false
        contextBannerView.layer.cornerRadius = 12
        contextBannerView.clipsToBounds = true
        contextBannerView.isAccessibilityElement = true
        contextBannerView.accessibilityLabel = L("chatreply.a11y.context")
        contextBannerView.accessibilityTraits = .staticText
        addSubview(contextBannerView)

        contextIconView.translatesAutoresizingMaskIntoConstraints = false
        contextIconView.backgroundColor = UIColor(red: 0.0, green: 0.75, blue: 0.65, alpha: 1)
        contextIconView.layer.cornerRadius = 4
        contextBannerView.addSubview(contextIconView)

        contextLabel.translatesAutoresizingMaskIntoConstraints = false
        contextLabel.font = .systemFont(ofSize: 13)
        contextLabel.numberOfLines = 2
        contextLabel.lineBreakMode = .byTruncatingTail
        contextBannerView.addSubview(contextLabel)

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setTitle("\u{2715}", for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        closeButton.accessibilityLabel = L("chatreply.a11y.close")
        closeButton.accessibilityHint = L("chatreply.a11y.close_hint")
        addSubview(closeButton)

        // ---- Tone Section ----
        toneSectionLabel.translatesAutoresizingMaskIntoConstraints = false
        toneSectionLabel.text = L("chatreply.tone.title")
        toneSectionLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        addSubview(toneSectionLabel)

        toneGridStack.translatesAutoresizingMaskIntoConstraints = false
        toneGridStack.axis = .vertical
        toneGridStack.spacing = 8
        toneGridStack.distribution = .fillEqually
        addSubview(toneGridStack)

        for row in 0..<4 {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.spacing = 8
            rowStack.distribution = .fillEqually

            for col in 0..<2 {
                let index = row * 2 + col
                let btn = UIButton(type: .custom)
                btn.tag = index
                btn.setTitle(cachedToneDisplayNames[safe: index] ?? Self.toneAPIValues[safe: index] ?? "", for: .normal)
                btn.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
                btn.layer.cornerRadius = 10
                btn.clipsToBounds = true
                btn.addTarget(self, action: #selector(toneTapped(_:)), for: .touchUpInside)
                btn.accessibilityLabel = cachedToneDisplayNames[safe: index] ?? ""
                btn.accessibilityHint = L("chatreply.a11y.tone_hint")
                btn.accessibilityTraits = (index == selectedToneIndex) ? [.button, .selected] : .button
                toneButtons.append(btn)
                rowStack.addArrangedSubview(btn)
            }
            toneGridStack.addArrangedSubview(rowStack)
        }
        updateToneSelection()

        // ---- Direction Input ----
        directionSectionLabel.translatesAutoresizingMaskIntoConstraints = false
        directionSectionLabel.text = L("chatreply.direction.title")
        directionSectionLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        directionSectionLabel.accessibilityTraits = .header
        addSubview(directionSectionLabel)

        directionInputContainer.translatesAutoresizingMaskIntoConstraints = false
        directionInputContainer.layer.cornerRadius = 12
        directionInputContainer.clipsToBounds = true
        addSubview(directionInputContainer)

        directionDisplayLabel.translatesAutoresizingMaskIntoConstraints = false
        directionDisplayLabel.font = .systemFont(ofSize: 14)
        directionDisplayLabel.numberOfLines = 1
        directionInputContainer.addSubview(directionDisplayLabel)

        directionCursorView.translatesAutoresizingMaskIntoConstraints = false
        directionCursorView.backgroundColor = UIColor(red: 0.19, green: 0.51, blue: 0.96, alpha: 1)
        directionInputContainer.addSubview(directionCursorView)

        directionPlaceholder.translatesAutoresizingMaskIntoConstraints = false
        directionPlaceholder.text = L("chatreply.direction.placeholder")
        directionPlaceholder.font = .systemFont(ofSize: 14)
        directionPlaceholder.alpha = 0.4
        directionInputContainer.addSubview(directionPlaceholder)

        directionSendButton.translatesAutoresizingMaskIntoConstraints = false
        directionSendButton.setTitle("\u{2192}", for: .normal)
        directionSendButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .bold)
        directionSendButton.layer.cornerRadius = 16
        directionSendButton.clipsToBounds = true
        directionInputContainer.addSubview(directionSendButton)

        skipLabel.translatesAutoresizingMaskIntoConstraints = false
        skipLabel.text = L("chatreply.skip")
        skipLabel.font = .systemFont(ofSize: 12)
        skipLabel.alpha = 0.5
        skipLabel.textAlignment = .center
        skipLabel.isUserInteractionEnabled = true
        skipLabel.isAccessibilityElement = true
        skipLabel.accessibilityLabel = L("chatreply.skip")
        skipLabel.accessibilityTraits = .button
        addSubview(skipLabel)

        // ---- Loading Container ----
        loadingContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(loadingContainer)

        loadingLabel.translatesAutoresizingMaskIntoConstraints = false
        loadingLabel.text = L("chatreply.loading")
        loadingLabel.font = .systemFont(ofSize: 14, weight: .medium)
        loadingLabel.textAlignment = .center
        loadingContainer.addSubview(loadingLabel)

        let dotsStack = UIStackView(arrangedSubviews: loadingDots)
        dotsStack.translatesAutoresizingMaskIntoConstraints = false
        dotsStack.axis = .horizontal
        dotsStack.spacing = 8
        dotsStack.alignment = .center
        loadingContainer.addSubview(dotsStack)

        for dot in loadingDots {
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.layer.cornerRadius = 5
            dot.backgroundColor = UIColor(red: 0.19, green: 0.51, blue: 0.96, alpha: 1)
            NSLayoutConstraint.activate([
                dot.widthAnchor.constraint(equalToConstant: 10),
                dot.heightAnchor.constraint(equalToConstant: 10)
            ])
        }

        NSLayoutConstraint.activate([
            dotsStack.centerXAnchor.constraint(equalTo: loadingContainer.centerXAnchor),
            dotsStack.centerYAnchor.constraint(equalTo: loadingContainer.centerYAnchor, constant: -12),
            loadingLabel.topAnchor.constraint(equalTo: dotsStack.bottomAnchor, constant: 12),
            loadingLabel.centerXAnchor.constraint(equalTo: loadingContainer.centerXAnchor)
        ])

        // ---- Reply Container ----
        replyContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(replyContainer)

        replyCardsStack.translatesAutoresizingMaskIntoConstraints = false
        replyCardsStack.axis = .vertical
        replyCardsStack.spacing = 10
        replyCardsStack.distribution = .fillEqually
        replyContainer.addSubview(replyCardsStack)

        regenerateButton.translatesAutoresizingMaskIntoConstraints = false
        regenerateButton.setTitle("\u{21BB} " + L("chatreply.regenerate"), for: .normal)
        regenerateButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        regenerateButton.layer.cornerRadius = 16
        regenerateButton.clipsToBounds = true
        regenerateButton.accessibilityLabel = L("chatreply.regenerate")
        regenerateButton.accessibilityHint = L("chatreply.a11y.regenerate_hint")
        replyContainer.addSubview(regenerateButton)

        // AI Disclosure 라벨 (Apple Guideline 4.7 준수)
        aiDisclosureLabel.text = L("chatreply.ai_disclosure")
        aiDisclosureLabel.font = .systemFont(ofSize: 10, weight: .regular)
        aiDisclosureLabel.textColor = UIColor.secondaryLabel
        aiDisclosureLabel.textAlignment = .center
        aiDisclosureLabel.translatesAutoresizingMaskIntoConstraints = false
        aiDisclosureLabel.isHidden = true
        addSubview(aiDisclosureLabel)

        // ---- Error Container ----
        errorContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(errorContainer)

        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        errorLabel.font = .systemFont(ofSize: 14)
        errorLabel.textAlignment = .center
        errorLabel.numberOfLines = 0
        errorContainer.addSubview(errorLabel)

        retryButton.translatesAutoresizingMaskIntoConstraints = false
        retryButton.setTitle(L("chatreply.retry"), for: .normal)
        retryButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        retryButton.layer.cornerRadius = 20
        retryButton.clipsToBounds = true
        retryButton.backgroundColor = UIColor(red: 0.19, green: 0.51, blue: 0.96, alpha: 1)
        retryButton.accessibilityLabel = L("chatreply.retry")
        retryButton.accessibilityHint = L("chatreply.a11y.retry_hint")
        errorContainer.addSubview(retryButton)

        NSLayoutConstraint.activate([
            errorLabel.centerXAnchor.constraint(equalTo: errorContainer.centerXAnchor),
            errorLabel.centerYAnchor.constraint(equalTo: errorContainer.centerYAnchor, constant: -20),
            errorLabel.leadingAnchor.constraint(equalTo: errorContainer.leadingAnchor, constant: 24),
            errorLabel.trailingAnchor.constraint(equalTo: errorContainer.trailingAnchor, constant: -24),
            retryButton.topAnchor.constraint(equalTo: errorLabel.bottomAnchor, constant: 16),
            retryButton.centerXAnchor.constraint(equalTo: errorContainer.centerXAnchor),
            retryButton.widthAnchor.constraint(equalToConstant: 120),
            retryButton.heightAnchor.constraint(equalToConstant: 40)
        ])

        // ---- iPad maxWidth ----
        let maxWidthConstraint = toneGridStack.widthAnchor.constraint(lessThanOrEqualToConstant: 500)
        maxWidthConstraint.priority = .required
        maxWidthConstraint.isActive = true

        // ---- Layout ----
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            closeButton.widthAnchor.constraint(equalToConstant: 32),
            closeButton.heightAnchor.constraint(equalToConstant: 32),

            contextBannerView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            contextBannerView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            contextBannerView.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -8),
            contextBannerView.heightAnchor.constraint(equalToConstant: 48),

            contextIconView.leadingAnchor.constraint(equalTo: contextBannerView.leadingAnchor, constant: 12),
            contextIconView.centerYAnchor.constraint(equalTo: contextBannerView.centerYAnchor),
            contextIconView.widthAnchor.constraint(equalToConstant: 4),
            contextIconView.heightAnchor.constraint(equalToConstant: 24),

            contextLabel.leadingAnchor.constraint(equalTo: contextIconView.trailingAnchor, constant: 10),
            contextLabel.trailingAnchor.constraint(equalTo: contextBannerView.trailingAnchor, constant: -12),
            contextLabel.centerYAnchor.constraint(equalTo: contextBannerView.centerYAnchor),
        ])

        NSLayoutConstraint.activate([
            toneSectionLabel.topAnchor.constraint(equalTo: contextBannerView.bottomAnchor, constant: 12),
            toneSectionLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),

            toneGridStack.topAnchor.constraint(equalTo: toneSectionLabel.bottomAnchor, constant: 8),
            toneGridStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            toneGridStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            toneGridStack.centerXAnchor.constraint(equalTo: centerXAnchor),
        ])

        NSLayoutConstraint.activate([
            directionSectionLabel.topAnchor.constraint(equalTo: toneGridStack.bottomAnchor, constant: 12),
            directionSectionLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),

            directionInputContainer.topAnchor.constraint(equalTo: directionSectionLabel.bottomAnchor, constant: 8),
            directionInputContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            directionInputContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            directionInputContainer.heightAnchor.constraint(equalToConstant: 44),

            directionDisplayLabel.leadingAnchor.constraint(equalTo: directionInputContainer.leadingAnchor, constant: 14),
            directionDisplayLabel.centerYAnchor.constraint(equalTo: directionInputContainer.centerYAnchor),
            directionDisplayLabel.trailingAnchor.constraint(equalTo: directionSendButton.leadingAnchor, constant: -8),

            directionCursorView.leadingAnchor.constraint(equalTo: directionDisplayLabel.trailingAnchor, constant: 1),
            directionCursorView.centerYAnchor.constraint(equalTo: directionInputContainer.centerYAnchor),
            directionCursorView.widthAnchor.constraint(equalToConstant: 2),
            directionCursorView.heightAnchor.constraint(equalToConstant: 18),

            directionPlaceholder.leadingAnchor.constraint(equalTo: directionInputContainer.leadingAnchor, constant: 14),
            directionPlaceholder.centerYAnchor.constraint(equalTo: directionInputContainer.centerYAnchor),

            directionSendButton.trailingAnchor.constraint(equalTo: directionInputContainer.trailingAnchor, constant: -6),
            directionSendButton.centerYAnchor.constraint(equalTo: directionInputContainer.centerYAnchor),
            directionSendButton.widthAnchor.constraint(equalToConstant: 32),
            directionSendButton.heightAnchor.constraint(equalToConstant: 32),

            skipLabel.topAnchor.constraint(equalTo: directionInputContainer.bottomAnchor, constant: 8),
            skipLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
        ])

        for container in [loadingContainer, replyContainer, errorContainer] {
            NSLayoutConstraint.activate([
                container.topAnchor.constraint(equalTo: topAnchor),
                container.leadingAnchor.constraint(equalTo: leadingAnchor),
                container.trailingAnchor.constraint(equalTo: trailingAnchor),
                container.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }

        NSLayoutConstraint.activate([
            replyCardsStack.topAnchor.constraint(equalTo: replyContainer.topAnchor, constant: 12),
            replyCardsStack.leadingAnchor.constraint(equalTo: replyContainer.leadingAnchor, constant: 16),
            replyCardsStack.trailingAnchor.constraint(equalTo: replyContainer.trailingAnchor, constant: -16),

            regenerateButton.topAnchor.constraint(equalTo: replyCardsStack.bottomAnchor, constant: 12),
            regenerateButton.centerXAnchor.constraint(equalTo: replyContainer.centerXAnchor),
            regenerateButton.widthAnchor.constraint(equalToConstant: 140),
            regenerateButton.heightAnchor.constraint(equalToConstant: 36),

            aiDisclosureLabel.topAnchor.constraint(equalTo: regenerateButton.bottomAnchor, constant: 4),
            aiDisclosureLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
        ])
    }
}

// MARK: - Actions

extension ChatReplyGeneratorView {

    private func setupActions() {
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        directionSendButton.addTarget(self, action: #selector(directionSendTapped), for: .touchUpInside)

        let skipTap = UITapGestureRecognizer(target: self, action: #selector(skipTapped))
        skipLabel.addGestureRecognizer(skipTap)

        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
        regenerateButton.addTarget(self, action: #selector(regenerateTapped), for: .touchUpInside)
    }

    @objc private func handleCardLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        guard currentSubState == .results else { return }
        guard let card = gesture.view as? ChatReplyCard else { return }
        guard replyCards.contains(where: { $0 === card }) else { return }

        let index = card.tag
        guard let reply = currentReplies[safe: index] else { return }

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        UIPasteboard.general.string = reply

        UIAccessibility.post(notification: .announcement, argument: L("chatreply.copied"))

        onCopy?(reply)
    }

    @objc private func closeTapped() {
        hapticFeedback.impactOccurred()
        onClose?()
    }

    @objc private func toneTapped(_ sender: UIButton) {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
        onToneChanged?()
        selectedToneIndex = sender.tag
        updateToneSelection()
    }

    @objc private func directionSendTapped() {
        hapticFeedback.impactOccurred()
        triggerGeneration()
    }

    @objc private func skipTapped() {
        hapticFeedback.impactOccurred()
        triggerGeneration()
    }

    @objc private func retryTapped() {
        hapticFeedback.impactOccurred()
        triggerGeneration()
    }

    @objc private func regenerateTapped() {
        hapticFeedback.impactOccurred()
        onRequestRegenerate?()
    }

    private func triggerGeneration() {
        let tone = Self.toneAPIValues[safe: selectedToneIndex] ?? "Friendly"
        let request = ChatReplyRequest(
            context: contextMessage,
            tone: tone,
            direction: directionText,
            language: ""
        )
        onRequestGenerate?(request)
    }

    private func updateToneSelection() {
        for (index, btn) in toneButtons.enumerated() {
            if index == selectedToneIndex {
                btn.backgroundColor = UIColor(red: 0.19, green: 0.51, blue: 0.96, alpha: 1)
                btn.setTitleColor(.white, for: .normal)
            } else {
                btn.backgroundColor = isDark ?
                    UIColor(white: 0.2, alpha: 1) :
                    UIColor(white: 0.93, alpha: 1)
                btn.setTitleColor(isDark ? .white : .darkGray, for: .normal)
            }
            btn.accessibilityTraits = (index == selectedToneIndex) ? [.button, .selected] : .button
        }
    }

    private func updateDirectionSendButtonAppearance() {
        let hasText = !directionText.isEmpty
        directionSendButton.backgroundColor = hasText ?
            UIColor(red: 0.19, green: 0.51, blue: 0.96, alpha: 1) :
            UIColor(white: 0.5, alpha: 0.3)
        directionSendButton.setTitleColor(.white, for: .normal)
    }
}

// MARK: - Colors

extension ChatReplyGeneratorView {

    private func applyColors() {
        let bgColor = isDark ?
            UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1) :
            UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1)
        let textColor = isDark ? UIColor.white : UIColor.black
        let secondaryText = isDark ?
            UIColor(white: 0.6, alpha: 1) :
            UIColor(white: 0.4, alpha: 1)
        let bannerBg = isDark ?
            UIColor(white: 0.15, alpha: 1) :
            UIColor(white: 0.9, alpha: 1)
        let inputBg = isDark ?
            UIColor(white: 0.15, alpha: 1) :
            UIColor.white

        backgroundColor = bgColor
        contextBannerView.backgroundColor = bannerBg
        contextLabel.textColor = textColor
        closeButton.setTitleColor(secondaryText, for: .normal)
        toneSectionLabel.textColor = textColor
        directionSectionLabel.textColor = textColor
        updateToneSelection()
        directionInputContainer.backgroundColor = inputBg
        directionDisplayLabel.textColor = textColor
        directionPlaceholder.textColor = secondaryText
        skipLabel.textColor = secondaryText
        loadingLabel.textColor = secondaryText
        errorLabel.textColor = secondaryText
        regenerateButton.backgroundColor = isDark ?
            UIColor(white: 0.2, alpha: 1) :
            UIColor(white: 0.9, alpha: 1)
        regenerateButton.setTitleColor(
            UIColor(red: 0.19, green: 0.51, blue: 0.96, alpha: 1),
            for: .normal
        )
    }
}

// MARK: - SubState Transitions

extension ChatReplyGeneratorView {

    func showSubState(_ state: SubState) {
        currentSubState = state

        directionInputContainer.isHidden = true
        directionSectionLabel.isHidden = true
        toneSectionLabel.isHidden = true
        toneGridStack.isHidden = true
        skipLabel.isHidden = true
        loadingContainer.isHidden = true
        replyContainer.isHidden = true
        errorContainer.isHidden = true

        switch state {
        case .setup:
            toneSectionLabel.isHidden = false
            toneGridStack.isHidden = false
            directionSectionLabel.isHidden = false
            directionInputContainer.isHidden = false
            skipLabel.isHidden = false
            startCursorBlink()
        case .loading:
            loadingContainer.isHidden = false
            startLoadingAnimation()
        case .results:
            replyContainer.isHidden = false
            stopLoadingAnimation()
        case .error:
            errorContainer.isHidden = false
            stopLoadingAnimation()
        }

        aiDisclosureLabel.isHidden = (state != .results)

        switch state {
        case .loading:
            UIAccessibility.post(notification: .announcement, argument: L("chatreply.loading"))
        case .results:
            UIAccessibility.post(notification: .layoutChanged, argument: replyCards.first)
        case .error:
            UIAccessibility.post(notification: .announcement, argument: L("chatreply.a11y.error_occurred"))
        case .setup:
            break
        }

        UIView.animate(withDuration: 0.2) { self.layoutIfNeeded() }
    }

    private func startCursorBlink() {
        cursorTimer?.invalidate()
        directionCursorView.isHidden = false
        cursorTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.directionCursorView.alpha = self.directionCursorView.alpha > 0.5 ? 0 : 1
        }
    }

    private func stopCursorBlink() {
        cursorTimer?.invalidate()
        cursorTimer = nil
        directionCursorView.isHidden = true
    }

    private func startLoadingAnimation() {
        var dotIndex = 0
        loadingTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            for (i, dot) in self.loadingDots.enumerated() {
                UIView.animate(withDuration: 0.2) {
                    dot.alpha = (i == dotIndex % 3) ? 1.0 : 0.3
                }
            }
            dotIndex += 1
        }
    }

    private func stopLoadingAnimation() {
        loadingTimer?.invalidate()
        loadingTimer = nil
    }

    private func buildReplyCards(_ replies: [String]) {
        replyCards.forEach { $0.removeFromSuperview() }
        replyCards.removeAll()
        replyCardsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let tone = cachedToneDisplayNames[safe: selectedToneIndex] ?? L("chatreply.tone.friendly")

        for (index, reply) in replies.enumerated() {
            let card = ChatReplyCard(index: index)
            card.configure(number: index + 1, tone: tone, text: reply)

            card.onTap = { [weak self] in
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                self?.onInsert?(reply)
            }

            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleCardLongPress(_:)))
            longPress.minimumPressDuration = 0.5
            card.addGestureRecognizer(longPress)
            card.tag = index

            card.isAccessibilityElement = true
            card.accessibilityLabel = String(format: L("chatreply.a11y.card"), index + 1)
            card.accessibilityValue = reply
            card.accessibilityHint = L("chatreply.a11y.card_hint")
            card.accessibilityTraits = .button

            replyCardsStack.addArrangedSubview(card)
            replyCards.append(card)
        }
    }
}

// MARK: - ChatReplyCard

final class ChatReplyCard: UIView {
    let numberLabel = UILabel()
    let toneLabel = UILabel()
    let replyTextLabel = UILabel()
    private let gradientLayer = CAGradientLayer()

    var onTap: (() -> Void)?

    init(index: Int) {
        super.init(frame: .zero)
        setupUI(index: index)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func tapped() { onTap?() }

    func configure(number: Int, tone: String, text: String) {
        numberLabel.text = "\(number)"
        toneLabel.text = tone.uppercased()
        replyTextLabel.text = text
    }

    private func setupUI(index: Int) {
        layer.cornerRadius = 14
        clipsToBounds = true

        let colors: [(UIColor, UIColor)] = [
            (UIColor(red: 0.12, green: 0.23, blue: 0.37, alpha: 1),
             UIColor(red: 0.05, green: 0.12, blue: 0.20, alpha: 1)),
            (UIColor(red: 0.18, green: 0.11, blue: 0.24, alpha: 1),
             UIColor(red: 0.10, green: 0.06, blue: 0.14, alpha: 1)),
            (UIColor(red: 0.11, green: 0.23, blue: 0.18, alpha: 1),
             UIColor(red: 0.06, green: 0.14, blue: 0.10, alpha: 1))
        ]

        let safeIndex = index % colors.count
        gradientLayer.colors = [colors[safeIndex].0.cgColor, colors[safeIndex].1.cgColor]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        layer.insertSublayer(gradientLayer, at: 0)

        numberLabel.translatesAutoresizingMaskIntoConstraints = false
        numberLabel.font = .systemFont(ofSize: 12, weight: .bold)
        numberLabel.textColor = .white
        numberLabel.textAlignment = .center
        numberLabel.backgroundColor = UIColor(white: 1, alpha: 0.15)
        numberLabel.layer.cornerRadius = 10
        numberLabel.clipsToBounds = true
        addSubview(numberLabel)

        toneLabel.translatesAutoresizingMaskIntoConstraints = false
        toneLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        toneLabel.textColor = UIColor(white: 1, alpha: 0.6)
        addSubview(toneLabel)

        replyTextLabel.translatesAutoresizingMaskIntoConstraints = false
        replyTextLabel.font = .systemFont(ofSize: 14)
        replyTextLabel.textColor = .white
        replyTextLabel.numberOfLines = 3
        replyTextLabel.lineBreakMode = .byTruncatingTail
        addSubview(replyTextLabel)

        NSLayoutConstraint.activate([
            numberLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            numberLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            numberLabel.widthAnchor.constraint(equalToConstant: 20),
            numberLabel.heightAnchor.constraint(equalToConstant: 20),

            toneLabel.centerYAnchor.constraint(equalTo: numberLabel.centerYAnchor),
            toneLabel.leadingAnchor.constraint(equalTo: numberLabel.trailingAnchor, constant: 8),

            replyTextLabel.topAnchor.constraint(equalTo: numberLabel.bottomAnchor, constant: 8),
            replyTextLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            replyTextLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            replyTextLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -12),
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
    }
}
