import UIKit

class ToolbarView: UIView {

    // MARK: - Callbacks

    var onTranslateToggle: (() -> Void)?
    var onCorrectionToggle: (() -> Void)?
    var onEmojiKeyboardToggle: (() -> Void)?
    var onSavedPhrasesTap: (() -> Void)?
    var onClipboardTap: (() -> Void)?
    var onSuggestionTap: ((String) -> Void)?
    var onSuggestionDismiss: (() -> Void)?
    var onLogoTap: (() -> Void)?
    var onLogoLongPress: (() -> Void)?

    // MARK: - Toolbar Views

    private let toolbarStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.alignment = .center
        sv.distribution = .fill
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private let leftGroup: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.distribution = .fillEqually
        sv.alignment = .center
        sv.spacing = 0
        return sv
    }()

    private let rightGroup: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.distribution = .fill
        sv.alignment = .center
        sv.spacing = 4
        return sv
    }()

    private let flexSpace = UIView()

    // Logo badge
    private let logoBadge: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 10, weight: .bold)
        label.textColor = .white
        label.backgroundColor = UIColor(red: 0.941, green: 0.267, blue: 0.322, alpha: 1) // #F04452
        label.textAlignment = .center
        label.layer.cornerRadius = 8
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()

    // CTA pills
    private let correctionPill = UIButton(type: .system)
    private let translationPill = UIButton(type: .system)

    // Status label
    private let statusLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()

    // MARK: - Suggestion Views (Chip Style)

    private let suggestionScrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.showsHorizontalScrollIndicator = false
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.isHidden = true
        sv.contentInset = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        return sv
    }()

    private let suggestionChipStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 8
        sv.alignment = .center
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private let dismissButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("✕", for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        btn.setTitleColor(.label, for: .normal)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.isHidden = true
        return btn
    }()

    private let dismissSeparator: UIView = {
        let v = UIView()
        v.backgroundColor = .separator
        v.translatesAutoresizingMaskIntoConstraints = false
        v.isHidden = true
        return v
    }()

    // Track logo button for badge positioning
    private var logoButton: UIButton?

    // MARK: - Theme

    private var customTheme: KeyboardTheme?
    private var isDark = false

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupViews() {
        backgroundColor = .clear

        addSubview(toolbarStack)
        addSubview(statusLabel)
        addSubview(suggestionScrollView)
        addSubview(dismissSeparator)
        addSubview(dismissButton)

        dismissButton.addTarget(self, action: #selector(dismissTapped), for: .touchUpInside)

        NSLayoutConstraint.activate([
            toolbarStack.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            toolbarStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            toolbarStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            toolbarStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),

            statusLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            suggestionScrollView.topAnchor.constraint(equalTo: topAnchor),
            suggestionScrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            suggestionScrollView.trailingAnchor.constraint(equalTo: dismissSeparator.leadingAnchor),
            suggestionScrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            dismissSeparator.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            dismissSeparator.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            dismissSeparator.trailingAnchor.constraint(equalTo: dismissButton.leadingAnchor),
            dismissSeparator.widthAnchor.constraint(equalToConstant: 0.5),

            dismissButton.topAnchor.constraint(equalTo: topAnchor),
            dismissButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            dismissButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            dismissButton.widthAnchor.constraint(equalToConstant: 44),
        ])

        // Suggestion chip scroll view
        suggestionScrollView.addSubview(suggestionChipStack)
        NSLayoutConstraint.activate([
            suggestionChipStack.topAnchor.constraint(equalTo: suggestionScrollView.topAnchor),
            suggestionChipStack.leadingAnchor.constraint(equalTo: suggestionScrollView.leadingAnchor),
            suggestionChipStack.trailingAnchor.constraint(equalTo: suggestionScrollView.trailingAnchor),
            suggestionChipStack.bottomAnchor.constraint(equalTo: suggestionScrollView.bottomAnchor),
            suggestionChipStack.heightAnchor.constraint(equalTo: suggestionScrollView.heightAnchor),
        ])

        // Build left group buttons
        buildLeftGroup()

        // Build right group pills
        buildRightGroup()

        // Assemble toolbar
        toolbarStack.addArrangedSubview(leftGroup)
        toolbarStack.addArrangedSubview(flexSpace)
        toolbarStack.addArrangedSubview(rightGroup)

        // FlexSpace fills remaining space
        flexSpace.setContentHuggingPriority(.defaultLow, for: .horizontal)
        leftGroup.setContentHuggingPriority(.required, for: .horizontal)
        rightGroup.setContentHuggingPriority(.required, for: .horizontal)
    }

    // MARK: - Left Group (4 icon buttons)

    private func buildLeftGroup() {
        let items: [(icon: String, action: Selector, tag: Int)] = [
            ("t.circle", #selector(logoTapped), 0),
            ("face.smiling", #selector(emojiButtonTapped), 1),
            ("doc.on.clipboard", #selector(clipboardHistoryTapped), 2),
            ("bookmark", #selector(savedPhrasesTapped), 3),
        ]

        for item in items {
            let btn = UIButton(type: .system)
            let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .light)
            btn.setImage(UIImage(systemName: item.icon, withConfiguration: config), for: .normal)
            btn.tintColor = .label
            btn.tag = item.tag
            btn.addTarget(self, action: item.action, for: .touchUpInside)
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.widthAnchor.constraint(equalToConstant: 36).isActive = true
            btn.heightAnchor.constraint(equalToConstant: 34).isActive = true
            leftGroup.addArrangedSubview(btn)

            if item.tag == 0 {
                logoButton = btn
                // Long press gesture on logo
                let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLogoLongPress(_:)))
                longPress.minimumPressDuration = 0.5
                btn.addGestureRecognizer(longPress)
            }
        }

        // Add badge to logo button
        if let logo = logoButton {
            logo.addSubview(logoBadge)
            NSLayoutConstraint.activate([
                logoBadge.topAnchor.constraint(equalTo: logo.topAnchor, constant: 0),
                logoBadge.trailingAnchor.constraint(equalTo: logo.trailingAnchor, constant: -2),
                logoBadge.heightAnchor.constraint(equalToConstant: 16),
                logoBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 16),
            ])
        }
    }

    // MARK: - Right Group (CTA pills)

    private func buildRightGroup() {
        configurePill(correctionPill,
                      icon: "checkmark.circle",
                      title: L("reward.mode.correction"),
                      bgColor: UIColor(red: 1, green: 0.624, blue: 0.263, alpha: 0.12),
                      tintColor: UIColor(red: 1, green: 0.624, blue: 0.263, alpha: 1), // #FF9F43
                      action: #selector(correctionPillTapped))

        configurePill(translationPill,
                      icon: "globe",
                      title: L("reward.mode.translation"),
                      bgColor: UIColor(red: 0.192, green: 0.510, blue: 0.965, alpha: 0.12),
                      tintColor: UIColor(red: 0.192, green: 0.510, blue: 0.965, alpha: 1), // #3182F6
                      action: #selector(translationPillTapped))

        rightGroup.addArrangedSubview(correctionPill)
        rightGroup.addArrangedSubview(translationPill)
    }

    private func configurePill(_ pill: UIButton, icon: String, title: String, bgColor: UIColor, tintColor: UIColor, action: Selector) {
        pill.backgroundColor = bgColor
        pill.layer.cornerRadius = 18
        pill.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        pill.setTitleColor(tintColor, for: .normal)
        pill.contentEdgeInsets = UIEdgeInsets(top: 7, left: 14, bottom: 7, right: 14)

        let iconConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        pill.setImage(UIImage(systemName: icon, withConfiguration: iconConfig), for: .normal)
        pill.tintColor = tintColor
        pill.semanticContentAttribute = .forceLeftToRight
        pill.imageEdgeInsets = UIEdgeInsets(top: 0, left: -3, bottom: 0, right: 3)
        pill.setTitle(title, for: .normal)
        pill.addTarget(self, action: action, for: .touchUpInside)
        pill.translatesAutoresizingMaskIntoConstraints = false
    }

    // MARK: - Public Methods

    func updateBadgeCount(_ count: Int) {
        if count > 0 {
            logoBadge.text = "\(count)"
            logoBadge.isHidden = false
        } else {
            logoBadge.isHidden = true
        }
    }

    func showStatusMessage(_ message: String) {
        statusLabel.text = message
        statusLabel.isHidden = false
    }

    func hideStatusMessage() {
        statusLabel.isHidden = true
    }

    func applyTheme(_ theme: KeyboardTheme?) {
        customTheme = theme
    }

    func updateAppearance(isDark: Bool) {
        self.isDark = isDark
        let textColor: UIColor
        let suggestionBg: UIColor

        if let theme = customTheme {
            backgroundColor = theme.toolbarBackground
            textColor = theme.keyTextColor
            suggestionBg = theme.keyboardBackground
        } else {
            backgroundColor = isDark ? UIColor(white: 0.12, alpha: 1) : .clear
            textColor = isDark ? .white : .label
            suggestionBg = isDark
                ? UIColor(white: 0.08, alpha: 1)
                : UIColor(red: 0.82, green: 0.84, blue: 0.86, alpha: 1)
        }

        // Left group icons
        for case let btn as UIButton in leftGroup.arrangedSubviews {
            btn.tintColor = textColor
        }

        // Dismiss button
        dismissButton.setTitleColor(textColor, for: .normal)
        suggestionScrollView.backgroundColor = suggestionBg
        dismissButton.backgroundColor = suggestionBg

        // Update chip colors
        updateChipAppearance()
    }

    func updatePillLabels() {
        correctionPill.setTitle(L("reward.mode.correction"), for: .normal)
        translationPill.setTitle(L("reward.mode.translation"), for: .normal)
    }

    // MARK: - Suggestions (Chip Style)

    func showSuggestions(_ suggestions: [String]) {
        // Clear old chips
        suggestionChipStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        for (i, suggestion) in suggestions.enumerated() {
            let chip = createSuggestionChip(title: suggestion, tag: i, isPrimary: i == 0)
            suggestionChipStack.addArrangedSubview(chip)
        }

        toolbarStack.isHidden = true
        suggestionScrollView.isHidden = false
        dismissButton.isHidden = false
        dismissSeparator.isHidden = false
        suggestionScrollView.contentOffset = .zero
    }

    func hideSuggestions() {
        suggestionScrollView.isHidden = true
        toolbarStack.isHidden = false
        dismissButton.isHidden = true
        dismissSeparator.isHidden = true
    }

    private func createSuggestionChip(title: String, tag: Int, isPrimary: Bool) -> UIButton {
        let chip = UIButton(type: .system)
        chip.setTitle(title, for: .normal)
        chip.tag = tag

        if isPrimary {
            chip.backgroundColor = UIColor(red: 0.192, green: 0.510, blue: 0.965, alpha: 1) // accent
            chip.setTitleColor(.white, for: .normal)
            chip.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
            chip.layer.shadowColor = UIColor(red: 0.192, green: 0.510, blue: 0.965, alpha: 0.3).cgColor
            chip.layer.shadowOffset = CGSize(width: 0, height: 1)
            chip.layer.shadowOpacity = 1
            chip.layer.shadowRadius = 4
        } else {
            let chipBg = customTheme?.keyBackground ?? (isDark ? UIColor(white: 0.29, alpha: 1) : .white)
            chip.backgroundColor = chipBg
            chip.setTitleColor(customTheme?.keyTextColor ?? (isDark ? .white : .label), for: .normal)
            chip.titleLabel?.font = .systemFont(ofSize: 14, weight: .regular)
            chip.layer.shadowColor = UIColor.black.cgColor
            chip.layer.shadowOffset = CGSize(width: 0, height: 1)
            chip.layer.shadowOpacity = isDark ? 0.4 : 0.2
            chip.layer.shadowRadius = 0.5
        }

        chip.contentEdgeInsets = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        chip.layer.cornerRadius = 10
        chip.clipsToBounds = false
        chip.addTarget(self, action: #selector(chipTapped(_:)), for: .touchUpInside)
        return chip
    }

    private func updateChipAppearance() {
        for case let chip as UIButton in suggestionChipStack.arrangedSubviews {
            let isPrimary = chip.tag == 0
            if !isPrimary {
                let chipBg = customTheme?.keyBackground ?? (isDark ? UIColor(white: 0.29, alpha: 1) : .white)
                chip.backgroundColor = chipBg
                chip.setTitleColor(customTheme?.keyTextColor ?? (isDark ? .white : .label), for: .normal)
                chip.layer.shadowOpacity = isDark ? 0.4 : 0.2
            }
        }
    }

    // MARK: - Hit Test

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, bounds.contains(point) else { return nil }

        // Suggestion mode: default hit-testing
        if !suggestionScrollView.isHidden {
            return super.hitTest(point, with: event)
        }

        // Toolbar mode: check pills first, then icons
        guard !toolbarStack.isHidden else { return nil }

        // Check right group pills first (they have higher priority)
        let rightPoint = convert(point, to: rightGroup)
        if rightGroup.bounds.contains(rightPoint) {
            return rightGroup.hitTest(rightPoint, with: event)
        }

        // Then check left group — route to nearest button
        let leftPoint = convert(point, to: leftGroup)
        if leftGroup.bounds.contains(leftPoint) {
            var nearestButton: UIButton?
            var nearestDistance: CGFloat = .greatestFiniteMagnitude
            for case let btn as UIButton in leftGroup.arrangedSubviews {
                let dist = abs(leftPoint.x - btn.frame.midX)
                if dist < nearestDistance {
                    nearestDistance = dist
                    nearestButton = btn
                }
            }
            return nearestButton ?? super.hitTest(point, with: event)
        }

        // Flex space area — route to nearest left icon
        let stackPoint = convert(point, to: toolbarStack)
        var nearestButton: UIButton?
        var nearestDistance: CGFloat = .greatestFiniteMagnitude
        for case let btn as UIButton in leftGroup.arrangedSubviews {
            let btnCenter = leftGroup.convert(CGPoint(x: btn.frame.midX, y: btn.frame.midY), to: toolbarStack)
            let dist = abs(stackPoint.x - btnCenter.x)
            if dist < nearestDistance {
                nearestDistance = dist
                nearestButton = btn
            }
        }
        return nearestButton ?? super.hitTest(point, with: event)
    }

    // MARK: - Actions

    @objc private func logoTapped() {
        onLogoTap?()
    }

    @objc private func handleLogoLongPress(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onLogoLongPress?()
        }
    }

    @objc private func emojiButtonTapped() {
        onEmojiKeyboardToggle?()
    }

    @objc private func clipboardHistoryTapped() {
        onClipboardTap?()
    }

    @objc private func savedPhrasesTapped() {
        onSavedPhrasesTap?()
    }

    @objc private func correctionPillTapped() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onCorrectionToggle?()
    }

    @objc private func translationPillTapped() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onTranslateToggle?()
    }

    @objc private func chipTapped(_ sender: UIButton) {
        guard let title = sender.title(for: .normal), !title.isEmpty else { return }
        onSuggestionTap?(title)
    }

    @objc private func dismissTapped() {
        onSuggestionDismiss?()
    }
}
