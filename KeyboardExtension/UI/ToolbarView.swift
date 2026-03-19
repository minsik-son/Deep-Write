import UIKit
import SwiftUI

class ToolbarView: UIView {

    // MARK: - Callbacks

    var onTranslateToggle: (() -> Void)?
    var onCorrectionToggle: (() -> Void)?
    var onEmojiKeyboardToggle: (() -> Void)?
    var onSavedPhrasesTap: (() -> Void)?
    var onClipboardTap: (() -> Void)?
    var onQuickNoteTap: (() -> Void)?
    var onSuggestionTap: ((String) -> Void)?
    var onSuggestionDismiss: (() -> Void)?

    // MARK: - Toolbar Views

    private let toolbarStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.alignment = .center
        sv.distribution = .equalSpacing
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    /// SwiftUI Link를 담는 컨테이너 뷰 (UIHostingController.view가 들어감)
    let settingsLinkContainer: UIView = {
        let v = UIView()
        v.backgroundColor = .clear
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

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

        // Build all toolbar buttons
        buildToolbarButtons()
    }

    // MARK: - Build Toolbar Buttons

    private func buildToolbarButtons() {
        // 아이콘 7개 일렬 배치 (index 0은 SwiftUI Link 컨테이너)
        // index 0: plus.circle — settingsLinkContainer (SwiftUI Link)
        // index 1-6: UIButton (기존 기능)

        let buttonItems: [(icon: String, action: Selector, tag: Int)] = [
            ("icon_toolbar_emoji",        #selector(emojiButtonTapped),       1),
            ("icon_toolbar_clipboard",    #selector(clipboardHistoryTapped),  2),
            ("icon_toolbar_savedphrases", #selector(savedPhrasesTapped),      3),
            ("icon_toolbar_quicknote",    #selector(noteTapped),              4),
            ("icon_toolbar_correction",   #selector(correctionButtonTapped),  5),
            ("icon_toolbar_translation",  #selector(translationButtonTapped), 6),
        ]

        // CC-6: 반응형 spacing (iPhone SE 등 좁은 화면 대응)
        let screenWidth = UIScreen.main.bounds.width
        toolbarStack.spacing = screenWidth <= 375 ? 0 : 2

        // 0번: SwiftUI Link 컨테이너 (+ 버튼)
        settingsLinkContainer.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            settingsLinkContainer.widthAnchor.constraint(equalToConstant: 36),
            settingsLinkContainer.heightAnchor.constraint(equalToConstant: 34),
        ])
        toolbarStack.addArrangedSubview(settingsLinkContainer)

        // 1-6번: 일반 UIButton (커스텀 SVG 아이콘)
        let iconRenderSize: CGFloat = 20

        for item in buttonItems {
            let btn = UIButton(type: .system)

            // Asset Catalog에서 SVG 로드 → aspectFit으로 20×20pt 안에 렌더링
            // 비정사각형 SVG(clipboard 222×290, bookmark 211×317 등)도 비율 유지
            if let original = UIImage(named: item.icon)?.withRenderingMode(.alwaysTemplate) {
                let targetSize = CGSize(width: iconRenderSize, height: iconRenderSize)
                let renderer = UIGraphicsImageRenderer(size: targetSize)
                let resized = renderer.image { _ in
                    let widthRatio = targetSize.width / original.size.width
                    let heightRatio = targetSize.height / original.size.height
                    let scale = min(widthRatio, heightRatio)
                    let drawWidth = original.size.width * scale
                    let drawHeight = original.size.height * scale
                    let drawX = (targetSize.width - drawWidth) / 2
                    let drawY = (targetSize.height - drawHeight) / 2
                    original.draw(in: CGRect(x: drawX, y: drawY, width: drawWidth, height: drawHeight))
                }
                btn.setImage(resized.withRenderingMode(.alwaysTemplate), for: .normal)
            }

            btn.tintColor = .label
            btn.tag = item.tag
            btn.addTarget(self, action: item.action, for: .touchUpInside)
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.widthAnchor.constraint(equalToConstant: 36).isActive = true
            btn.heightAnchor.constraint(equalToConstant: 34).isActive = true
            toolbarStack.addArrangedSubview(btn)
        }
    }

    // MARK: - Public Methods

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

        // 모든 아이콘 버튼 색상 업데이트 (settingsLinkContainer 제외)
        for case let btn as UIButton in toolbarStack.arrangedSubviews {
            btn.tintColor = textColor
        }

        // Dismiss button
        dismissButton.setTitleColor(textColor, for: .normal)
        suggestionScrollView.backgroundColor = suggestionBg
        dismissButton.backgroundColor = suggestionBg

        // Update chip colors
        updateChipAppearance()

        // Wood toolbar styling
        if let theme = customTheme, theme.hasWoodTexture {
            applyWoodToolbarStyle(theme)
        } else {
            cleanupWoodToolbarStyle()
        }
    }

    private func applyWoodToolbarStyle(_ theme: KeyboardTheme) {
        guard let tileName = theme.woodTileImageName,
              let tileImg = UIImage(named: tileName) else { return }

        // toolbarStack의 모든 UIButton에 나무 텍스처 적용
        for case let btn as UIButton in toolbarStack.arrangedSubviews {
            btn.backgroundColor = theme.specialKeyBackground

            let patternTag = 9903
            btn.viewWithTag(patternTag)?.removeFromSuperview()

            let patternView = UIView()
            patternView.tag = patternTag
            patternView.backgroundColor = UIColor(patternImage: tileImg)
            patternView.alpha = 0.4
            patternView.isUserInteractionEnabled = false
            patternView.layer.cornerRadius = 5
            patternView.clipsToBounds = true
            patternView.translatesAutoresizingMaskIntoConstraints = false
            btn.insertSubview(patternView, at: 0)
            NSLayoutConstraint.activate([
                patternView.topAnchor.constraint(equalTo: btn.topAnchor),
                patternView.bottomAnchor.constraint(equalTo: btn.bottomAnchor),
                patternView.leadingAnchor.constraint(equalTo: btn.leadingAnchor),
                patternView.trailingAnchor.constraint(equalTo: btn.trailingAnchor),
            ])

            btn.layer.cornerRadius = 5
            btn.layer.borderWidth = 1
            btn.layer.borderColor = UIColor(white: 0, alpha: 0.2).cgColor
            btn.layer.shadowColor = UIColor(white: 0, alpha: 0.3).cgColor
            btn.layer.shadowOffset = CGSize(width: 0, height: 2)
            btn.layer.shadowRadius = 1
            btn.layer.shadowOpacity = 1.0
            btn.clipsToBounds = false

            btn.tintColor = theme.keyTextColor
        }
    }

    private func cleanupWoodToolbarStyle() {
        let patternTag = 9903

        for case let btn as UIButton in toolbarStack.arrangedSubviews {
            btn.viewWithTag(patternTag)?.removeFromSuperview()
            btn.layer.shadowOpacity = 0
            btn.layer.borderWidth = 0
            btn.clipsToBounds = true
            btn.backgroundColor = .clear
            btn.layer.cornerRadius = 0
        }
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

        // Toolbar mode
        guard !toolbarStack.isHidden else { return nil }

        // settingsLinkContainer 영역은 SwiftUI Link가 처리하도록 우선 통과
        let containerPoint = convert(point, to: settingsLinkContainer)
        if settingsLinkContainer.bounds.contains(containerPoint) {
            return settingsLinkContainer.hitTest(containerPoint, with: event)
        }

        // 나머지 영역은 가장 가까운 버튼으로 라우팅
        let stackPoint = convert(point, to: toolbarStack)
        var nearestButton: UIButton?
        var nearestDistance: CGFloat = .greatestFiniteMagnitude
        for case let btn as UIButton in toolbarStack.arrangedSubviews {
            let btnCenter = CGPoint(x: btn.frame.midX, y: btn.frame.midY)
            let dist = abs(stackPoint.x - btnCenter.x)
            if dist < nearestDistance {
                nearestDistance = dist
                nearestButton = btn
            }
        }
        return nearestButton ?? super.hitTest(point, with: event)
    }

    // MARK: - Actions

    @objc private func emojiButtonTapped() {
        onEmojiKeyboardToggle?()
    }

    @objc private func clipboardHistoryTapped() {
        onClipboardTap?()
    }

    @objc private func savedPhrasesTapped() {
        onSavedPhrasesTap?()
    }

    @objc private func noteTapped() {
        onQuickNoteTap?()
    }

    @objc private func correctionButtonTapped() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onCorrectionToggle?()
    }

    @objc private func translationButtonTapped() {
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
