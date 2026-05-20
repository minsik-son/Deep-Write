import UIKit
import os.log

#if DEBUG
private let toolbarMemoryDebugLog = OSLog(
    subsystem: "com.translatorkeyboard.keyboard",
    category: "MemoryDebug"
)

@inline(__always)
private func toolbarDebugMemLog(_ message: String) {
    os_log("%{public}@", log: toolbarMemoryDebugLog, type: .debug, message)
}
#endif

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
    var onCalculatorTap: (() -> Void)?
    var onChatReplyGeneratorTap: (() -> Void)?
    var onDictationTap: (() -> Void)?

    // Productivity editing tools
    var onCursorLeftTap: (() -> Void)?
    var onCursorRightTap: (() -> Void)?
    var onDeleteWordTap: (() -> Void)?
    var onUndoTap: (() -> Void)?
    var onRedoTap: (() -> Void)?
    var onSelectAllTap: (() -> Void)?
    var onCopyTap: (() -> Void)?
    var onPasteTap: (() -> Void)?
    var onCutTap: (() -> Void)?
    var onCaseTransformTap: (() -> Void)?

    // New features
    var onDateTimeInsertTap: (() -> Void)?
    var onDateTimeInsertLongPress: (() -> Void)?
    var onDismissKeyboardTap: (() -> Void)?
    var onUnitConverterTap: (() -> Void)?
    var onSettingsTap: (() -> Void)?

    // MARK: - Toolbar Views

    private let toolbarStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.alignment = .center
        sv.distribution = .equalSpacing
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    /// Settings button container (UIKit — no SwiftUI dependency)
    let settingsLinkContainer: UIView = {
        let v = UIView()
        v.backgroundColor = .clear
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let settingsButton: UIButton = {
        let button = UIButton(type: .system)
        if let image = UIImage(named: "icon_toolbar_settings")?.withRenderingMode(.alwaysTemplate) {
            button.setImage(image, for: .normal)
        }
        button.tintColor = .label
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = "Settings"
        return button
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
        #if DEBUG
        toolbarDebugMemLog(String(
            format: "[MEM_ATTR] event=ToolbarView.init phase=end id=%@ arranged=%d chips=%d",
            String(describing: Unmanaged.passUnretained(self).toOpaque()),
            toolbarStack.arrangedSubviews.count,
            suggestionChipStack.arrangedSubviews.count
        ))
        #endif
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        #if DEBUG
        toolbarDebugMemLog(String(
            format: "[MEM_ATTR] event=ToolbarView.deinit phase=start id=%@ arranged=%d chips=%d",
            String(describing: Unmanaged.passUnretained(self).toOpaque()),
            toolbarStack.arrangedSubviews.count,
            suggestionChipStack.arrangedSubviews.count
        ))
        #endif
        // ToolbarView holds no timers / displayLinks / observers; closures use
        // [weak self] from the controller side. Suggestion chips + wood pattern
        // overlays are released once the view leaves the hierarchy.
    }

    /// Idempotent teardown called by the controller after `viewWillDisappear`.
    /// Nils retained callbacks and releases transient suggestion / overlay UI
    /// without touching input state. Safe to call multiple times.
    func prepareForControllerRelease() {
        onTranslateToggle = nil
        onCorrectionToggle = nil
        onEmojiKeyboardToggle = nil
        onSavedPhrasesTap = nil
        onClipboardTap = nil
        onQuickNoteTap = nil
        onSuggestionTap = nil
        onSuggestionDismiss = nil
        onCalculatorTap = nil
        onChatReplyGeneratorTap = nil
        onDictationTap = nil
        onCursorLeftTap = nil
        onCursorRightTap = nil
        onDeleteWordTap = nil
        onUndoTap = nil
        onRedoTap = nil
        onSelectAllTap = nil
        onCopyTap = nil
        onPasteTap = nil
        onCutTap = nil
        onCaseTransformTap = nil
        onDateTimeInsertTap = nil
        onDateTimeInsertLongPress = nil
        onDismissKeyboardTap = nil
        onUnitConverterTap = nil
        onSettingsTap = nil

        // Transient chips are not user input state — safe to drop.
        suggestionChipStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // Wood-pattern overlays on toolbar buttons will be reapplied by theme.
        cleanupWoodToolbarStyle()

        #if DEBUG
        toolbarDebugMemLog(String(
            format: "[MEM_ATTR] event=ToolbarView.prepareForControllerRelease phase=end id=%@ arranged=%d chips=%d",
            String(describing: Unmanaged.passUnretained(self).toOpaque()),
            toolbarStack.arrangedSubviews.count,
            suggestionChipStack.arrangedSubviews.count
        ))
        #endif
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

        // Settings button inside container
        settingsLinkContainer.addSubview(settingsButton)
        settingsButton.addTarget(self, action: #selector(settingsButtonTapped), for: .touchUpInside)
        NSLayoutConstraint.activate([
            settingsButton.topAnchor.constraint(equalTo: settingsLinkContainer.topAnchor),
            settingsButton.bottomAnchor.constraint(equalTo: settingsLinkContainer.bottomAnchor),
            settingsButton.leadingAnchor.constraint(equalTo: settingsLinkContainer.leadingAnchor),
            settingsButton.trailingAnchor.constraint(equalTo: settingsLinkContainer.trailingAnchor),
        ])

        NSLayoutConstraint.activate([
            toolbarStack.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            toolbarStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            toolbarStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            toolbarStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),

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

        // Toolbar buttons — defer until size is ready to avoid width-0 constraint conflicts
        if bounds.width > 0 {
            buildToolbarButtons()
        } else {
            pendingToolbarBuild = true
            #if DEBUG
            NSLog("[ToolbarRebuild] deferred width=%.2f height=%.2f", bounds.width, bounds.height)
            #endif
        }
    }

    private var pendingToolbarBuild = false

    override func layoutSubviews() {
        super.layoutSubviews()
        if pendingToolbarBuild, bounds.width > 0 {
            pendingToolbarBuild = false
            #if DEBUG
            NSLog("[ToolbarRebuild] consumeDeferred width=%.2f height=%.2f", bounds.width, bounds.height)
            #endif
            buildToolbarButtons()
        }
    }

    // MARK: - Build Toolbar Buttons

    private var currentToolbarConfig: [ToolbarItemType] = []
    private var settingsLinkSizeConfigured = false

    private func buildToolbarButtons() {
        let items = ToolbarConfiguration.load()
        currentToolbarConfig = items
        applyToolbarItems(items)
    }

    func rebuildToolbarIfNeeded() {
        let newConfig = ToolbarConfiguration.load()
        #if DEBUG
        let _trStart = CACurrentMediaTime()
        let changed = (newConfig != currentToolbarConfig)
        #endif
        guard newConfig != currentToolbarConfig else {
            #if DEBUG
            NSLog("[ToolbarRebuild] changed=false current=%d new=%d duration=%.2fms hasSettings=%d", currentToolbarConfig.count, newConfig.count, (CACurrentMediaTime() - _trStart) * 1000, newConfig.contains(.settings) ? 1 : 0)
            #endif
            return
        }

        for view in toolbarStack.arrangedSubviews {
            if view === settingsLinkContainer {
                toolbarStack.removeArrangedSubview(view)
                continue
            }
            toolbarStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        currentToolbarConfig = newConfig
        applyToolbarItems(newConfig)

        if let theme = customTheme {
            applyTheme(theme)
        }
        updateAppearance(isDark: isDark)
        #if DEBUG
        NSLog("[ToolbarRebuild] changed=true current=%d new=%d duration=%.2fms hasSettings=%d", currentToolbarConfig.count, newConfig.count, (CACurrentMediaTime() - _trStart) * 1000, newConfig.contains(.settings) ? 1 : 0)
        #endif
    }

    private func applyToolbarItems(_ items: [ToolbarItemType]) {
        let screenWidth = UIScreen.main.bounds.width
        toolbarStack.spacing = screenWidth <= 375 ? 0 : 2

        let iconRenderSize: CGFloat = 20

        // Defensive filter: skip unsupported host text items
        let filtered = items.filter { !ToolbarConfiguration.unsupportedHostTextItems.contains($0) }

        for item in filtered {
            switch item {
            case .settings:
                if !settingsLinkSizeConfigured {
                    settingsLinkContainer.translatesAutoresizingMaskIntoConstraints = false
                    NSLayoutConstraint.activate([
                        settingsLinkContainer.widthAnchor.constraint(equalToConstant: 36),
                        settingsLinkContainer.heightAnchor.constraint(equalToConstant: 34),
                    ])
                    settingsLinkSizeConfigured = true
                }
                toolbarStack.addArrangedSubview(settingsLinkContainer)

            case .emoji:
                toolbarStack.addArrangedSubview(
                    makeToolbarButton(iconName: "icon_toolbar_emoji", action: #selector(emojiButtonTapped), tag: 1, iconSize: iconRenderSize))

            case .clipboard:
                toolbarStack.addArrangedSubview(
                    makeToolbarButton(iconName: "icon_toolbar_clipboard", action: #selector(clipboardHistoryTapped), tag: 2, iconSize: iconRenderSize))

            case .savedPhrases:
                toolbarStack.addArrangedSubview(
                    makeToolbarButton(iconName: "icon_toolbar_savedphrases", action: #selector(savedPhrasesTapped), tag: 3, iconSize: iconRenderSize))

            case .quickNote:
                toolbarStack.addArrangedSubview(
                    makeToolbarButton(iconName: "icon_toolbar_quicknote", action: #selector(noteTapped), tag: 4, iconSize: iconRenderSize))

            case .correction:
                toolbarStack.addArrangedSubview(
                    makeToolbarButton(iconName: "icon_toolbar_correction", action: #selector(correctionButtonTapped), tag: 5, iconSize: iconRenderSize))

            case .translation:
                toolbarStack.addArrangedSubview(
                    makeToolbarButton(iconName: "icon_toolbar_translation", action: #selector(translationButtonTapped), tag: 6, iconSize: iconRenderSize))

            case .calculator:
                toolbarStack.addArrangedSubview(
                    makeToolbarButton(iconName: "icon_toolbar_calculator", action: #selector(calculatorTapped), tag: 7, iconSize: iconRenderSize))

            case .chatReplyGenerator:
                toolbarStack.addArrangedSubview(
                    makeToolbarButton(iconName: "icon_toolbar_chat_reply", action: #selector(chatReplyGeneratorTapped), tag: 8, iconSize: iconRenderSize))

            case .dictation:
                toolbarStack.addArrangedSubview(
                    makeToolbarButton(iconName: "icon_toolbar_dictation", action: #selector(dictationTapped), tag: 9, iconSize: iconRenderSize))

            // Productivity editing tools — lucide SVG assets
            case .cursorLeft:
                toolbarStack.addArrangedSubview(makeToolbarButton(iconName: "icon_toolbar_cursor_left", action: #selector(cursorLeftTapped), tag: 10, iconSize: iconRenderSize))
            case .cursorRight:
                toolbarStack.addArrangedSubview(makeToolbarButton(iconName: "icon_toolbar_cursor_right", action: #selector(cursorRightTapped), tag: 11, iconSize: iconRenderSize))
            case .deleteWord:
                toolbarStack.addArrangedSubview(makeToolbarButton(iconName: "icon_toolbar_delete_word", action: #selector(deleteWordTapped), tag: 12, iconSize: iconRenderSize))
            case .undo:
                toolbarStack.addArrangedSubview(makeToolbarButton(iconName: "icon_toolbar_undo", action: #selector(undoTapped), tag: 13, iconSize: iconRenderSize))
            case .redo:
                toolbarStack.addArrangedSubview(makeToolbarButton(iconName: "icon_toolbar_redo", action: #selector(redoTapped), tag: 14, iconSize: iconRenderSize))
            case .selectAll:
                toolbarStack.addArrangedSubview(makeToolbarButton(iconName: "icon_toolbar_select_all", action: #selector(selectAllTapped), tag: 15, iconSize: iconRenderSize))
            case .copy:
                toolbarStack.addArrangedSubview(makeToolbarButton(iconName: "icon_toolbar_copy", action: #selector(copyTapped), tag: 16, iconSize: iconRenderSize))
            case .paste:
                toolbarStack.addArrangedSubview(makeToolbarButton(iconName: "icon_toolbar_paste", action: #selector(pasteTapped), tag: 17, iconSize: iconRenderSize))
            case .cut:
                toolbarStack.addArrangedSubview(makeToolbarButton(iconName: "icon_toolbar_cut", action: #selector(cutTapped), tag: 18, iconSize: iconRenderSize))
            case .caseTransform:
                toolbarStack.addArrangedSubview(makeToolbarButton(iconName: "icon_toolbar_case", action: #selector(caseTransformTapped), tag: 19, iconSize: iconRenderSize))

            case .dateTimeInsert:
                let btn = makeToolbarButton(iconName: "icon_toolbar_datetime", action: #selector(dateTimeInsertTapped), tag: 20, iconSize: iconRenderSize)
                let longPress = UILongPressGestureRecognizer(target: self, action: #selector(dateTimeInsertLongPressed(_:)))
                longPress.minimumPressDuration = 0.4
                btn.addGestureRecognizer(longPress)
                toolbarStack.addArrangedSubview(btn)
            case .dismissKeyboard:
                toolbarStack.addArrangedSubview(makeToolbarButton(iconName: "icon_toolbar_dismiss", action: #selector(dismissKeyboardTapped), tag: 21, iconSize: iconRenderSize))
            case .unitConverter:
                toolbarStack.addArrangedSubview(makeToolbarButton(iconName: "icon_toolbar_unit_converter", action: #selector(unitConverterTapped), tag: 22, iconSize: iconRenderSize))
            }
        }
    }

    // makeSFToolbarButton removed — all toolbar items now use lucide SVG assets

    private func makeToolbarButton(iconName: String, action: Selector, tag: Int, iconSize: CGFloat) -> UIButton {
        let btn = UIButton(type: .system)

        if let original = UIImage(named: iconName)?.withRenderingMode(.alwaysTemplate) {
            let targetSize = CGSize(width: iconSize, height: iconSize)
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
        btn.tag = tag
        btn.addTarget(self, action: action, for: .touchUpInside)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.widthAnchor.constraint(equalToConstant: 36).isActive = true
        btn.heightAnchor.constraint(equalToConstant: 34).isActive = true
        return btn
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

        // 모든 아이콘 버튼 색상 업데이트
        for case let btn as UIButton in toolbarStack.arrangedSubviews {
            btn.tintColor = textColor
        }
        settingsButton.tintColor = textColor

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

        // 나머지 영역은 가장 가까운 버튼으로 라우팅
        let stackPoint = convert(point, to: toolbarStack)
        var nearestButton: UIButton?
        var nearestDistance: CGFloat = .greatestFiniteMagnitude
        for arranged in toolbarStack.arrangedSubviews {
            let btn: UIButton
            if arranged === settingsLinkContainer {
                btn = settingsButton
                // settingsButton center in stack coordinate
                let btnCenterInStack = settingsLinkContainer.convert(
                    CGPoint(x: settingsButton.bounds.midX, y: settingsButton.bounds.midY),
                    to: toolbarStack)
                let dist = abs(stackPoint.x - btnCenterInStack.x)
                if dist < nearestDistance {
                    nearestDistance = dist
                    nearestButton = btn
                }
            } else if let b = arranged as? UIButton {
                let btnCenter = CGPoint(x: b.frame.midX, y: b.frame.midY)
                let dist = abs(stackPoint.x - btnCenter.x)
                if dist < nearestDistance {
                    nearestDistance = dist
                    nearestButton = b
                }
            }
        }
        return nearestButton ?? super.hitTest(point, with: event)
    }

    // MARK: - Actions

    @objc private func calculatorTapped() {
        onCalculatorTap?()
    }

    @objc private func chatReplyGeneratorTapped() {
        onChatReplyGeneratorTap?()
    }

    @objc private func dictationTapped() {
        onDictationTap?()
    }

    @objc private func cursorLeftTapped() { onCursorLeftTap?() }
    @objc private func cursorRightTapped() { onCursorRightTap?() }
    @objc private func deleteWordTapped() { onDeleteWordTap?() }
    @objc private func undoTapped() { onUndoTap?() }
    @objc private func redoTapped() { onRedoTap?() }
    @objc private func selectAllTapped() { onSelectAllTap?() }
    @objc private func copyTapped() { onCopyTap?() }
    @objc private func pasteTapped() { onPasteTap?() }
    @objc private func cutTapped() { onCutTap?() }
    @objc private func caseTransformTapped() { onCaseTransformTap?() }
    @objc private func dateTimeInsertTapped() { onDateTimeInsertTap?() }
    @objc private func dateTimeInsertLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        onDateTimeInsertLongPress?()
    }
    @objc private func dismissKeyboardTapped() { onDismissKeyboardTap?() }
    @objc private func unitConverterTapped() { onUnitConverterTap?() }
    @objc private func settingsButtonTapped() { onSettingsTap?() }

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
