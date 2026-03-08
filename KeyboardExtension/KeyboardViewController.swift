import UIKit

enum KeyboardMode {
    case defaultMode
    case translationMode
    case correctionMode
    case phraseInputMode
}

class KeyboardViewController: UIInputViewController {

    private var currentMode: KeyboardMode = .defaultMode

    // MARK: - UI Components

    private lazy var toolbarView = ToolbarView()
    private lazy var translationLanguageBar = TranslationLanguageBar()
    private lazy var translationInputView = TranslationInputView()
    private lazy var correctionLanguageBar = CorrectionLanguageBar()
    private lazy var correctionInputView = TranslationInputView()
    private lazy var keyboardLayoutView = KeyboardLayoutView()
    private var emojiKeyboardView: EmojiKeyboardView?
    private var languagePickerView: LanguagePickerView?
    private var savedPhrasesView: SavedPhrasesView?
    private var clipboardHistoryView: ClipboardHistoryView?
    private lazy var phraseInputHeaderView = PhraseInputHeaderView()
    private lazy var phraseInputView = TranslationInputView()
    private var isEmojiMode = false

    // MARK: - Logic Managers

    private let defaultTextInputHandler = TextInputHandler()
    private let modeTextInputHandler = TextInputHandler()
    private var defaultModeComposingLength: Int = 0
    private lazy var textProxyManager = TextProxyManager(textDocumentProxy: textDocumentProxy)
    private let translationManager = TranslationManager()
    private let correctionManager = CorrectionManager()
    private let sessionManager = SessionManager.shared
    private let suggestionManager = SuggestionManager()

    // MARK: - Deferred View Setup Flags

    private var isTranslationViewsSetUp = false
    private var isCorrectionViewsSetUp = false
    private var isPhraseViewsSetUp = false

    // MARK: - Constraints

    private var heightConstraint: NSLayoutConstraint?
    private var keyboardTopToToolbarConstraint: NSLayoutConstraint?
    private var keyboardTopToTranslationConstraint: NSLayoutConstraint?
    private var keyboardTopToCorrectionConstraint: NSLayoutConstraint?
    private var translationInputHeightConstraint: NSLayoutConstraint?
    private var correctionInputHeightConstraint: NSLayoutConstraint?
    private var phraseInputHeightConstraint: NSLayoutConstraint?
    private var keyboardTopToPhraseInputConstraint: NSLayoutConstraint?
    private var keyboardLayoutHeightConstraint: NSLayoutConstraint?
    private var correctionInputTopConstraint: NSLayoutConstraint?
    private let hapticFeedback = UIImpactFeedbackGenerator(style: .medium)

    // Status message (floating toast)
    private var statusMessageTimer: DispatchWorkItem?
    private lazy var toastLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.textAlignment = .center
        label.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        label.layer.cornerRadius = 8
        label.clipsToBounds = true
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        label.isUserInteractionEnabled = false
        return label
    }()

    private var isAutocorrectEnabled: Bool {
        let defaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier)
        if let obj = defaults?.object(forKey: AppConstants.UserDefaultsKeys.autoComplete) {
            return (obj as? Bool) ?? false
        }
        return true
    }

    // Suggestion dismiss state
    private var isSuggestionDismissedForCurrentWord = false
    private var hasUserTypedSinceAppeared = false

    // Language state
    private var sourceLanguageCode: String = "ko"
    private var targetLanguageCode: String = "en"
    private var correctionLanguageCode: String = "ko"
    private var isLanguagePickerVisible = false

    // Tone state
    private var currentToneStyle: ToneStyle = .none
    private var tonePickerView: TonePickerView?
    private var isTonePickerVisible = false
    private var tonePickerHeightConstraint: NSLayoutConstraint?

    // MARK: - Layout Constants

    private struct Heights {
        static let toolbar: CGFloat = 40
        static let translationLanguageBar: CGFloat = 44
        static let translationInput: CGFloat = 44
        static let topPadding: CGFloat = 8
    }

    private var keyAreaHeight: CGFloat {
        let defaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier)
        let showNumberRow = defaults?.object(forKey: AppConstants.UserDefaultsKeys.showNumberRow) == nil ? true : (defaults?.bool(forKey: AppConstants.UserDefaultsKeys.showNumberRow) ?? true)
        return showNumberRow ? 270 : 222
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        setupUI()
        setupDelegates()
        setupCallbacks()
        switchMode(to: .defaultMode)
        restoreState()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        LocalizationManager.shared.reload()
        reloadLocalizedStrings()
        loadNumberRowSetting()
        loadKeyboardLanguageSetting()
        setupHeightConstraint()
        textProxyManager.updateProxy(textDocumentProxy)
        updateReturnKeyAppearance()
        checkAutoCapitalize()

        hasUserTypedSinceAppeared = false
        toolbarView.hideSuggestions()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.checkClipboardForNewContent()
            self?.updateToolbarBadge()
        }

        AppGroupManager.shared.set(self.hasFullAccess, forKey: AppConstants.UserDefaultsKeys.keyboardFullAccessEnabled)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        CompositionSessionManager.shared.endSession(reason: .keyboardHidden)
    }

    private func reloadLocalizedStrings() {
        if isTranslationViewsSetUp {
            translationInputView.setPlaceholder(L("translation.placeholder"))
        }
        if isCorrectionViewsSetUp {
            correctionInputView.setPlaceholder(L("correction.placeholder"))
        }
        if isPhraseViewsSetUp {
            phraseInputView.setPlaceholder(L("phrase.placeholder"))
            phraseInputHeaderView.reloadLocalizedStrings()
        }
        updateLanguageLabels()
        if currentMode == .correctionMode {
            correctionLanguageBar.updateToneName(currentToneStyle.displayName)
        }
    }

    private func loadNumberRowSetting() {
        let defaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier)
        let show = defaults?.object(forKey: AppConstants.UserDefaultsKeys.showNumberRow) == nil ? true : (defaults?.bool(forKey: AppConstants.UserDefaultsKeys.showNumberRow) ?? true)
        keyboardLayoutView.showNumberRow = show
        keyboardLayoutHeightConstraint?.constant = keyAreaHeight
    }

    private func loadKeyboardLanguageSetting() {
        let code = AppGroupManager.shared.string(forKey: AppConstants.UserDefaultsKeys.primaryKeyboardLanguage) ?? "ko"
        let lang = KeyboardLanguage(rawValue: code) ?? .korean
        keyboardLayoutView.pairedLanguage = lang
        let current = keyboardLayoutView.getCurrentLanguage()
        if current != .english && current != lang {
            keyboardLayoutView.setLanguage(lang)
        }
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        updateKeyboardAppearance()
        updateReturnKeyAppearance()

        // 교정/번역 모드: 호스트 앱 텍스트 필드가 비워지면 입력창 초기화
        if textProxyManager.hasPendingText {
            let contextEmpty = (textDocumentProxy.documentContextBeforeInput ?? "").isEmpty
                            && (textDocumentProxy.documentContextAfterInput ?? "").isEmpty
            if contextEmpty {
                if currentMode == .correctionMode {
                    modeTextInputHandler.clear()
                    correctionInputView.clear()
                    correctionManager.reset()
                    textProxyManager.reset()
                    correctionInputHeightConstraint?.constant = Heights.translationInput
                    updateHeight(for: .correctionMode, animated: true)
                } else if currentMode == .translationMode {
                    modeTextInputHandler.clear()
                    translationInputView.clear()
                    translationManager.cancelPending()
                    textProxyManager.reset()
                    translationInputHeightConstraint?.constant = Heights.translationInput
                    updateHeight(for: .translationMode, animated: true)
                }
            }
        }

        // CRITICAL: Reset Korean composition state when text context changes
        // (e.g., after sending a message, the text field is cleared by the app)
        // Without this, leftover composing characters contaminate the next input.
        if currentMode == .defaultMode || currentMode == .correctionMode || currentMode == .phraseInputMode {
            defaultTextInputHandler.clear()
            defaultModeComposingLength = 0
            isSuggestionDismissedForCurrentWord = false
        }

        checkAutoCapitalize()
        updateSuggestions()
    }

    // MARK: - Height

    private func setupHeightConstraint() {
        guard heightConstraint == nil, let inputView = self.inputView else { return }
        // DO NOT set translatesAutoresizingMaskIntoConstraints = false on inputView
        // iOS system manages the keyboard extension's inputView width via autoresizing masks
        let totalDefault = Heights.topPadding + Heights.toolbar + keyAreaHeight
        heightConstraint = inputView.heightAnchor.constraint(equalToConstant: totalDefault)
        heightConstraint?.priority = .defaultHigh
        heightConstraint?.isActive = true
    }

    private func updateHeight(for mode: KeyboardMode, animated: Bool = true) {
        let keyArea = keyAreaHeight
        keyboardLayoutHeightConstraint?.constant = keyArea
        let newHeight: CGFloat
        switch mode {
        case .defaultMode:
            newHeight = Heights.topPadding + Heights.toolbar + keyArea
        case .translationMode:
            let inputH = translationInputHeightConstraint?.constant ?? Heights.translationInput
            newHeight = Heights.topPadding + Heights.translationLanguageBar + inputH + keyArea
        case .correctionMode:
            let inputH = correctionInputHeightConstraint?.constant ?? Heights.translationInput
            let toneH = tonePickerHeightConstraint?.constant ?? 0
            newHeight = Heights.topPadding + Heights.translationLanguageBar + toneH + inputH + keyArea
        case .phraseInputMode:
            let inputH = phraseInputHeightConstraint?.constant ?? Heights.translationInput
            newHeight = Heights.topPadding + Heights.translationLanguageBar + inputH + keyArea
        }

        heightConstraint?.constant = newHeight

        if animated {
            UIView.animate(withDuration: 0.15) {
                self.inputView?.superview?.layoutIfNeeded()
            }
        }
    }

    private func updateInputHeight(_ newHeight: CGFloat, isTranslation: Bool) {
        if isTranslation {
            translationInputHeightConstraint?.constant = newHeight
        } else {
            correctionInputHeightConstraint?.constant = newHeight
        }
        updateHeight(for: currentMode, animated: true)
    }

    // MARK: - Book Animation

    private func animateBookOpen(_ views: [UIView]) {
        inputView?.layoutIfNeeded()
        for v in views {
            v.alpha = 0
            var t = CATransform3DIdentity
            t.m34 = -1.0 / 500
            t = CATransform3DRotate(t, -CGFloat.pi * 0.45, 1, 0, 0)
            v.layer.transform = t
        }
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.82, initialSpringVelocity: 0.3, options: []) {
            for v in views {
                v.alpha = 1
                v.layer.transform = CATransform3DIdentity
            }
        }
    }

    private func animateBookClose(_ views: [UIView], completion: @escaping () -> Void) {
        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseIn) {
            for v in views {
                v.alpha = 0
                var t = CATransform3DIdentity
                t.m34 = -1.0 / 500
                t = CATransform3DRotate(t, -CGFloat.pi * 0.45, 1, 0, 0)
                v.layer.transform = t
            }
        } completion: { _ in
            for v in views {
                v.layer.transform = CATransform3DIdentity
                v.alpha = 1
            }
            completion()
        }
    }

    // MARK: - Setup UI

    private func setupUI() {
        guard let inputView = self.inputView else {
            return
        }
        inputView.backgroundColor = .clear
        inputView.layer.cornerRadius = 20
        inputView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        inputView.clipsToBounds = true

        // Only add always-needed views: toolbar + keyboard layout
        // Translation, correction, phrase views are deferred to first mode entry
        [toolbarView, keyboardLayoutView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            inputView.addSubview($0)
        }

        NSLayoutConstraint.activate([
            // Toolbar — pinned to top with padding
            toolbarView.topAnchor.constraint(equalTo: inputView.topAnchor, constant: Heights.topPadding),
            toolbarView.leadingAnchor.constraint(equalTo: inputView.leadingAnchor),
            toolbarView.trailingAnchor.constraint(equalTo: inputView.trailingAnchor),
            toolbarView.heightAnchor.constraint(equalToConstant: Heights.toolbar),

            // Keyboard Layout
            keyboardLayoutView.leadingAnchor.constraint(equalTo: inputView.leadingAnchor),
            keyboardLayoutView.trailingAnchor.constraint(equalTo: inputView.trailingAnchor),
            keyboardLayoutView.bottomAnchor.constraint(equalTo: inputView.bottomAnchor),
        ])

        // Fixed height for keyboard layout — prevents stretching when system popup expands inputView
        keyboardLayoutHeightConstraint = keyboardLayoutView.heightAnchor.constraint(equalToConstant: keyAreaHeight)
        keyboardLayoutHeightConstraint?.isActive = true

        // Default: keyboard top = toolbar bottom
        keyboardTopToToolbarConstraint = keyboardLayoutView.topAnchor.constraint(equalTo: toolbarView.bottomAnchor)
        keyboardTopToToolbarConstraint?.priority = .defaultHigh
        keyboardTopToToolbarConstraint?.isActive = true

        // Toast — floating on top of everything
        inputView.addSubview(toastLabel)
        NSLayoutConstraint.activate([
            toastLabel.centerXAnchor.constraint(equalTo: inputView.centerXAnchor),
            toastLabel.topAnchor.constraint(equalTo: inputView.topAnchor, constant: 6),
            toastLabel.leadingAnchor.constraint(greaterThanOrEqualTo: inputView.leadingAnchor, constant: 24),
            toastLabel.trailingAnchor.constraint(lessThanOrEqualTo: inputView.trailingAnchor, constant: -24),
            toastLabel.heightAnchor.constraint(equalToConstant: 32),
        ])
    }

    // MARK: - Deferred View Setup

    private func setupTranslationViewsIfNeeded() {
        guard !isTranslationViewsSetUp, let inputView = self.inputView else { return }
        isTranslationViewsSetUp = true

        [translationLanguageBar, translationInputView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            inputView.addSubview($0)
        }
        translationLanguageBar.isHidden = true
        translationInputView.isHidden = true

        NSLayoutConstraint.activate([
            translationLanguageBar.topAnchor.constraint(equalTo: inputView.topAnchor, constant: Heights.topPadding),
            translationLanguageBar.leadingAnchor.constraint(equalTo: inputView.leadingAnchor),
            translationLanguageBar.trailingAnchor.constraint(equalTo: inputView.trailingAnchor),
            translationLanguageBar.heightAnchor.constraint(equalToConstant: Heights.translationLanguageBar),

            translationInputView.topAnchor.constraint(equalTo: translationLanguageBar.bottomAnchor),
            translationInputView.leadingAnchor.constraint(equalTo: inputView.leadingAnchor),
            translationInputView.trailingAnchor.constraint(equalTo: inputView.trailingAnchor),
        ])

        translationInputHeightConstraint = translationInputView.heightAnchor.constraint(equalToConstant: Heights.translationInput)
        translationInputHeightConstraint?.isActive = true

        keyboardTopToTranslationConstraint = keyboardLayoutView.topAnchor.constraint(equalTo: translationInputView.bottomAnchor)
        keyboardTopToTranslationConstraint?.priority = .defaultHigh

        setupTranslationCallbacks()
        updateLanguageLabels()
    }

    private func setupCorrectionViewsIfNeeded() {
        guard !isCorrectionViewsSetUp, let inputView = self.inputView else { return }
        isCorrectionViewsSetUp = true

        [correctionLanguageBar, correctionInputView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            inputView.addSubview($0)
        }
        correctionLanguageBar.isHidden = true
        correctionInputView.isHidden = true

        NSLayoutConstraint.activate([
            correctionLanguageBar.topAnchor.constraint(equalTo: inputView.topAnchor, constant: Heights.topPadding),
            correctionLanguageBar.leadingAnchor.constraint(equalTo: inputView.leadingAnchor),
            correctionLanguageBar.trailingAnchor.constraint(equalTo: inputView.trailingAnchor),
            correctionLanguageBar.heightAnchor.constraint(equalToConstant: Heights.translationLanguageBar),

            correctionInputView.leadingAnchor.constraint(equalTo: inputView.leadingAnchor),
            correctionInputView.trailingAnchor.constraint(equalTo: inputView.trailingAnchor),
        ])

        correctionInputTopConstraint = correctionInputView.topAnchor.constraint(equalTo: correctionLanguageBar.bottomAnchor)
        correctionInputTopConstraint?.isActive = true

        correctionInputHeightConstraint = correctionInputView.heightAnchor.constraint(equalToConstant: Heights.translationInput)
        correctionInputHeightConstraint?.isActive = true

        keyboardTopToCorrectionConstraint = keyboardLayoutView.topAnchor.constraint(equalTo: correctionInputView.bottomAnchor)
        keyboardTopToCorrectionConstraint?.priority = .defaultHigh

        setupCorrectionCallbacks()
    }

    private func setupPhraseViewsIfNeeded() {
        guard !isPhraseViewsSetUp, let inputView = self.inputView else { return }
        isPhraseViewsSetUp = true

        [phraseInputHeaderView, phraseInputView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            inputView.addSubview($0)
        }
        phraseInputHeaderView.isHidden = true
        phraseInputView.isHidden = true

        NSLayoutConstraint.activate([
            phraseInputHeaderView.topAnchor.constraint(equalTo: inputView.topAnchor, constant: Heights.topPadding),
            phraseInputHeaderView.leadingAnchor.constraint(equalTo: inputView.leadingAnchor),
            phraseInputHeaderView.trailingAnchor.constraint(equalTo: inputView.trailingAnchor),
            phraseInputHeaderView.heightAnchor.constraint(equalToConstant: Heights.translationLanguageBar),

            phraseInputView.topAnchor.constraint(equalTo: phraseInputHeaderView.bottomAnchor),
            phraseInputView.leadingAnchor.constraint(equalTo: inputView.leadingAnchor),
            phraseInputView.trailingAnchor.constraint(equalTo: inputView.trailingAnchor),
        ])

        phraseInputHeightConstraint = phraseInputView.heightAnchor.constraint(equalToConstant: Heights.translationInput)
        phraseInputHeightConstraint?.isActive = true

        keyboardTopToPhraseInputConstraint = keyboardLayoutView.topAnchor.constraint(equalTo: phraseInputView.bottomAnchor)
        keyboardTopToPhraseInputConstraint?.priority = .defaultHigh

        setupPhraseCallbacks()
    }

    // MARK: - Deferred Callbacks

    private func setupTranslationCallbacks() {
        translationInputView.onClearText = { [weak self] in
            self?.translationManager.cancelPending()
        }
        translationInputView.onHeightChanged = { [weak self] newHeight in
            self?.updateInputHeight(newHeight, isTranslation: true)
        }
        translationLanguageBar.onSourceTap = { [weak self] in
            self?.showLanguagePicker(initialTab: .source)
        }
        translationLanguageBar.onTargetTap = { [weak self] in
            self?.showLanguagePicker(initialTab: .target)
        }
        translationLanguageBar.onSwapTap = { [weak self] in
            self?.swapLanguages()
        }
        translationLanguageBar.onCloseTap = { [weak self] in
            self?.exitTranslationMode()
        }
    }

    private func setupCorrectionCallbacks() {
        correctionInputView.setPlaceholder(L("correction.placeholder"))
        correctionInputView.onClearText = { [weak self] in
            self?.exitCorrectionMode()
        }
        correctionInputView.onHeightChanged = { [weak self] newHeight in
            self?.updateInputHeight(newHeight, isTranslation: false)
        }
        correctionLanguageBar.onLanguageTap = { [weak self] in
            self?.showCorrectionLanguagePicker()
        }
        correctionLanguageBar.onToneTap = { [weak self] in
            self?.toggleTonePicker()
        }
        correctionLanguageBar.onCloseTap = { [weak self] in
            self?.exitCorrectionMode()
        }
    }

    private func setupPhraseCallbacks() {
        phraseInputHeaderView.onCancel = { [weak self] in
            self?.exitPhraseInputMode()
        }
        phraseInputHeaderView.onSave = { [weak self] in
            self?.saveNewPhrase()
        }
        phraseInputView.setPlaceholder(L("phrase.placeholder"))
        phraseInputView.onHeightChanged = { [weak self] newHeight in
            self?.phraseInputHeightConstraint?.constant = newHeight
            self?.updateHeight(for: .phraseInputMode, animated: true)
        }
    }

    // MARK: - Delegates

    private func setupDelegates() {
        modeTextInputHandler.delegate = self
        translationManager.delegate = self
        correctionManager.delegate = self
    }

    // MARK: - Callbacks

    private func setupCallbacks() {
        // Toolbar — default mode only
        toolbarView.onTranslateToggle = { [weak self] in
            self?.hideContextMenu()
            self?.hideStatusPopup()
            self?.toggleTranslationMode()
        }
        toolbarView.onEmojiKeyboardToggle = { [weak self] in
            self?.hideContextMenu()
            self?.hideStatusPopup()
            self?.toggleEmojiKeyboard()
        }
        toolbarView.onCorrectionToggle = { [weak self] in
            self?.hideContextMenu()
            self?.hideStatusPopup()
            self?.toggleCorrectionMode()
        }
        toolbarView.onSavedPhrasesTap = { [weak self] in
            self?.hideContextMenu()
            self?.hideStatusPopup()
            self?.showSavedPhrases()
        }
        toolbarView.onClipboardTap = { [weak self] in
            self?.hideContextMenu()
            self?.hideStatusPopup()
            self?.toggleClipboardHistory()
        }
        toolbarView.onLogoTap = { [weak self] in
            self?.hideContextMenu()
            self?.showStatusPopup()
        }
        toolbarView.onLogoLongPress = { [weak self] in
            self?.showContextMenu()
        }
        toolbarView.onSuggestionTap = { [weak self] suggestion in
            self?.applySuggestion(suggestion)
        }
        toolbarView.onSuggestionDismiss = { [weak self] in
            self?.dismissSuggestions()
        }

        // Keyboard layout — always present
        keyboardLayoutView.onKeyTap = { [weak self] key in
            self?.handleKeyTap(key)
        }
        keyboardLayoutView.onLanguageChanged = { [weak self] lang in
            self?.commitDefaultComposing()
            AppGroupManager.shared.set(lang.rawValue, forKey: AppConstants.UserDefaultsKeys.keyboardLayout)
        }
        keyboardLayoutView.onCursorMove = { [weak self] horizontal, vertical in
            self?.handleCursorMove(horizontal: horizontal, vertical: vertical)
        }
        keyboardLayoutView.onTrackpadModeChanged = { [weak self] active in
            if active {
                // Commit any in-progress Korean composition before moving cursor
                self?.commitDefaultComposing()
            }
        }

    }

    // MARK: - State Restoration

    private func restoreState() {
        if let sourceLang = AppGroupManager.shared.string(forKey: AppConstants.UserDefaultsKeys.sourceLanguage) {
            sourceLanguageCode = sourceLang
        }
        if let targetLang = AppGroupManager.shared.string(forKey: AppConstants.UserDefaultsKeys.targetLanguage) {
            targetLanguageCode = targetLang
        }
        correctionLanguageCode = sourceLanguageCode
        translationManager.setLanguages(source: sourceLanguageCode, target: targetLanguageCode)
        updateLanguageLabels()

        // Restore keyboard language from keyboardLayout key (supports both old "korean"/"english" and new rawValue format)
        if let savedLang = AppGroupManager.shared.string(forKey: AppConstants.UserDefaultsKeys.keyboardLayout) {
            let lang: KeyboardLanguage
            if let parsed = KeyboardLanguage(rawValue: savedLang) {
                lang = parsed
            } else if savedLang == "korean" {
                lang = .korean
            } else {
                lang = .english
            }
            keyboardLayoutView.setLanguage(lang)
        }
    }

    // MARK: - Mode Switching

    func switchMode(to mode: KeyboardMode) {
        currentMode = mode
        hideEmojiKeyboard()

        // Deactivate all keyboard top constraints first
        keyboardTopToToolbarConstraint?.isActive = false
        keyboardTopToTranslationConstraint?.isActive = false
        keyboardTopToCorrectionConstraint?.isActive = false
        keyboardTopToPhraseInputConstraint?.isActive = false

        switch mode {
        case .defaultMode:
            toolbarView.isHidden = false
            if isTranslationViewsSetUp {
                translationLanguageBar.isHidden = true
                translationInputView.isHidden = true
            }
            if isCorrectionViewsSetUp {
                correctionLanguageBar.isHidden = true
                correctionInputView.isHidden = true
            }
            if isPhraseViewsSetUp {
                phraseInputHeaderView.isHidden = true
                phraseInputView.isHidden = true
            }
            translationManager.cancelPending()
            textProxyManager.reset()
            keyboardTopToToolbarConstraint?.isActive = true

        case .translationMode:
            toolbarView.isHidden = true
            translationLanguageBar.isHidden = false
            translationInputView.isHidden = false
            if isCorrectionViewsSetUp {
                correctionLanguageBar.isHidden = true
                correctionInputView.isHidden = true
            }
            if isPhraseViewsSetUp {
                phraseInputHeaderView.isHidden = true
                phraseInputView.isHidden = true
            }
            modeTextInputHandler.clear()
            translationInputView.clear()
            toolbarView.hideSuggestions()
            keyboardTopToTranslationConstraint?.isActive = true

        case .correctionMode:
            toolbarView.isHidden = true
            if isTranslationViewsSetUp {
                translationLanguageBar.isHidden = true
                translationInputView.isHidden = true
            }
            correctionLanguageBar.isHidden = false
            correctionInputView.isHidden = false
            if isPhraseViewsSetUp {
                phraseInputHeaderView.isHidden = true
                phraseInputView.isHidden = true
            }
            modeTextInputHandler.clear()
            correctionInputView.clear()
            correctionManager.reset()
            textProxyManager.reset()
            toolbarView.hideSuggestions()
            keyboardTopToCorrectionConstraint?.isActive = true

        case .phraseInputMode:
            toolbarView.isHidden = true
            if isTranslationViewsSetUp {
                translationLanguageBar.isHidden = true
                translationInputView.isHidden = true
            }
            if isCorrectionViewsSetUp {
                correctionLanguageBar.isHidden = true
                correctionInputView.isHidden = true
            }
            phraseInputHeaderView.isHidden = false
            phraseInputView.isHidden = false
            modeTextInputHandler.clear()
            phraseInputView.clear()
            toolbarView.hideSuggestions()
            keyboardTopToPhraseInputConstraint?.isActive = true
        }

        updateHeight(for: mode)
        updateReturnKeyForCurrentMode()
        updateToolbarBadge()
    }

    private func toggleTranslationMode() {
        switch currentMode {
        case .defaultMode:
            enterTranslationMode()
        case .translationMode:
            exitTranslationMode()
        case .correctionMode, .phraseInputMode:
            break
        }
    }

    private func enterTranslationMode() {
        commitDefaultComposing()

        guard hasFullAccess() else {
            showStatusMessage(L("keyboard.error.full_access"))
            return
        }

        guard CompositionSessionManager.shared.canStartSession(mode: .translate) else {
            showDailyLimitReached(mode: .translate)
            return
        }
        CompositionSessionManager.shared.startSession(mode: .translate)
        setupTranslationViewsIfNeeded()
        switchMode(to: .translationMode)
        animateBookOpen([translationLanguageBar, translationInputView])
    }

    private func exitTranslationMode() {
        modeTextInputHandler.commitComposing()
        translationManager.cancelPending()
        CompositionSessionManager.shared.endSession(reason: .modeExit)
        textProxyManager.reset()
        defaultTextInputHandler.clear()
        defaultModeComposingLength = 0
        translationInputHeightConstraint?.constant = Heights.translationInput
        hideLanguagePicker()
        animateBookClose([translationLanguageBar, translationInputView]) { [weak self] in
            self?.switchMode(to: .defaultMode)
        }
    }

    // MARK: - Correction Mode

    private func toggleCorrectionMode() {
        switch currentMode {
        case .defaultMode:
            enterCorrectionMode()
        case .correctionMode:
            exitCorrectionMode()
        case .translationMode, .phraseInputMode:
            break
        }
    }

    private func enterCorrectionMode() {
        commitDefaultComposing()

        guard hasFullAccess() else {
            showStatusMessage(L("keyboard.error.full_access"))
            return
        }

        guard CompositionSessionManager.shared.canStartSession(mode: .correct) else {
            showDailyLimitReached(mode: .correct)
            return
        }
        CompositionSessionManager.shared.startSession(mode: .correct)
        setupCorrectionViewsIfNeeded()

        let langName = languageDisplayName(for: correctionLanguageCode)
        correctionLanguageBar.updateLanguageName(langName)
        correctionManager.setLanguage(correctionLanguageCode)
        if let savedTone = AppGroupManager.shared.string(forKey: AppConstants.UserDefaultsKeys.toneStyle),
           let tone = ToneStyle(rawValue: savedTone) {
            currentToneStyle = tone
        } else {
            currentToneStyle = .none
        }
        correctionLanguageBar.updateToneName(currentToneStyle.displayName)
        correctionManager.setTone(currentToneStyle)
        switchMode(to: .correctionMode)
        animateBookOpen([correctionLanguageBar, correctionInputView])
    }

    private func exitCorrectionMode() {
        modeTextInputHandler.commitComposing()
        modeTextInputHandler.clear()
        correctionManager.cancelPending()
        correctionManager.reset()
        CompositionSessionManager.shared.endSession(reason: .modeExit)
        textProxyManager.reset()
        defaultTextInputHandler.clear()
        defaultModeComposingLength = 0
        correctionInputHeightConstraint?.constant = Heights.translationInput
        hideTonePicker()
        hideLanguagePicker()
        animateBookClose([correctionLanguageBar, correctionInputView]) { [weak self] in
            self?.switchMode(to: .defaultMode)
        }
    }

    // MARK: - Saved Phrases

    private func showSavedPhrases() {
        if savedPhrasesView == nil {
            guard let inputView = self.inputView else { return }
            let sv = SavedPhrasesView()
            sv.translatesAutoresizingMaskIntoConstraints = false
            sv.isHidden = true
            sv.onPhraseSelected = { [weak self] phrase in
                self?.insertPhrase(phrase)
            }
            sv.onAddPhrase = { [weak self] in
                self?.enterPhraseInputMode()
            }
            sv.onDismiss = { [weak self] in
                self?.hideSavedPhrases()
            }
            inputView.addSubview(sv)
            NSLayoutConstraint.activate([
                sv.topAnchor.constraint(equalTo: inputView.topAnchor),
                sv.leadingAnchor.constraint(equalTo: inputView.leadingAnchor),
                sv.trailingAnchor.constraint(equalTo: inputView.trailingAnchor),
                sv.bottomAnchor.constraint(equalTo: inputView.bottomAnchor),
            ])
            savedPhrasesView = sv
        }
        savedPhrasesView?.reloadData()
        savedPhrasesView?.isHidden = false
        savedPhrasesView?.alpha = 0
        if let sv = savedPhrasesView {
            inputView?.bringSubviewToFront(sv)
        }
        UIView.animate(withDuration: 0.2) {
            self.savedPhrasesView?.alpha = 1
        }
    }

    private func hideSavedPhrases() {
        UIView.animate(withDuration: 0.15, animations: {
            self.savedPhrasesView?.alpha = 0
        }) { _ in
            self.savedPhrasesView?.isHidden = true
        }
    }

    // MARK: - Clipboard History

    private func toggleClipboardHistory() {
        if clipboardHistoryView?.isHidden ?? true {
            showClipboardHistory()
        } else {
            hideClipboardHistory()
        }
    }

    private func showClipboardHistory() {
        guard hasFullAccess() else {
            showStatusMessage(L("keyboard.error.full_access"))
            return
        }
        if clipboardHistoryView == nil {
            guard let inputView = self.inputView else { return }
            let cv = ClipboardHistoryView()
            cv.translatesAutoresizingMaskIntoConstraints = false
            cv.isHidden = true
            cv.onItemSelected = { [weak self] text in
                self?.textDocumentProxy.insertText(text)
                self?.hideClipboardHistory()
            }
            cv.onDismiss = { [weak self] in
                self?.hideClipboardHistory()
            }
            inputView.addSubview(cv)
            NSLayoutConstraint.activate([
                cv.topAnchor.constraint(equalTo: inputView.topAnchor),
                cv.leadingAnchor.constraint(equalTo: inputView.leadingAnchor),
                cv.trailingAnchor.constraint(equalTo: inputView.trailingAnchor),
                cv.bottomAnchor.constraint(equalTo: inputView.bottomAnchor),
            ])
            clipboardHistoryView = cv
        }
        clipboardHistoryView?.reloadData()
        clipboardHistoryView?.isHidden = false
        clipboardHistoryView?.alpha = 0
        if let cv = clipboardHistoryView {
            inputView?.bringSubviewToFront(cv)
        }
        inputView?.bringSubviewToFront(toastLabel)
        UIView.animate(withDuration: 0.2) {
            self.clipboardHistoryView?.alpha = 1
        }
    }

    private func hideClipboardHistory() {
        UIView.animate(withDuration: 0.15, animations: {
            self.clipboardHistoryView?.alpha = 0
        }) { _ in
            self.clipboardHistoryView?.isHidden = true
        }
    }

    private func checkClipboardForNewContent() {
        guard hasFullAccess() else { return }
        guard UIPasteboard.general.hasStrings else { return }
        guard let text = UIPasteboard.general.string else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let existing = ClipboardHistoryManager.shared.getItems()
        if existing.first?.text == trimmed { return }

        ClipboardHistoryManager.shared.addItem(trimmed)

        // 메인앱 히스토리 탭에도 저장
        HistoryManager.shared.addItem(
            type: .clipboard,
            original: trimmed,
            result: nil,
            metadata: nil
        )
    }

    private func insertPhrase(_ phrase: String) {
        textDocumentProxy.insertText(phrase)
        hideSavedPhrases()
    }

    private func enterPhraseInputMode() {
        hideSavedPhrases()
        setupPhraseViewsIfNeeded()
        phraseInputHeightConstraint?.constant = Heights.translationInput
        switchMode(to: .phraseInputMode)
    }

    private func exitPhraseInputMode() {
        modeTextInputHandler.commitComposing()
        modeTextInputHandler.clear()
        phraseInputHeightConstraint?.constant = Heights.translationInput
        switchMode(to: .defaultMode)
        showSavedPhrases()
    }

    private func saveNewPhrase() {
        let text = modeTextInputHandler.fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            exitPhraseInputMode()
            return
        }
        SavedPhrasesManager.shared.addPhrase(text)
        modeTextInputHandler.commitComposing()
        modeTextInputHandler.clear()
        phraseInputHeightConstraint?.constant = Heights.translationInput
        switchMode(to: .defaultMode)
        showSavedPhrases()
    }

    private func handlePhraseInputModeKey(_ key: String) {
        switch key {
        case KeyboardLayoutView.backKey:
            modeTextInputHandler.handleBackspace()

        case KeyboardLayoutView.returnKey:
            modeTextInputHandler.commitComposing()

        case " ":
            modeTextInputHandler.handleSpace()

        default:
            if modeTextInputHandler.totalLength >= AppConstants.Limits.maxCharacters {
                hapticFeedback.impactOccurred()
                return
            }

            let isKorean = isKoreanJamo(key)
            if let char = key.first {
                modeTextInputHandler.handleKey(char, isKorean: isKorean)
            }
        }
    }

    private func toggleTonePicker() {
        if isTonePickerVisible {
            hideTonePicker()
        } else {
            showTonePicker()
        }
    }

    private func ensureTonePickerView() {
        guard tonePickerView == nil, let inputView = self.inputView else { return }
        let tp = TonePickerView()
        tp.translatesAutoresizingMaskIntoConstraints = false
        tp.isHidden = true
        tp.onToneSelected = { [weak self] tone in
            self?.currentToneStyle = tone
            AppGroupManager.shared.set(tone.rawValue, forKey: AppConstants.UserDefaultsKeys.toneStyle)
            self?.correctionLanguageBar.updateToneName(tone.displayName)
            self?.correctionManager.setTone(tone)
            self?.hideTonePicker()
            if let text = self?.modeTextInputHandler.fullText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self?.correctionManager.reset()
                self?.correctionManager.requestCorrection(text: text)
            }
        }
        inputView.addSubview(tp)

        // Re-anchor correctionInputView: was pinned to correctionLanguageBar, now pin to tonePicker
        correctionInputTopConstraint?.isActive = false
        NSLayoutConstraint.activate([
            tp.topAnchor.constraint(equalTo: correctionLanguageBar.bottomAnchor),
            tp.leadingAnchor.constraint(equalTo: inputView.leadingAnchor),
            tp.trailingAnchor.constraint(equalTo: inputView.trailingAnchor),
        ])
        correctionInputTopConstraint = correctionInputView.topAnchor.constraint(equalTo: tp.bottomAnchor)
        correctionInputTopConstraint?.isActive = true

        tonePickerHeightConstraint = tp.heightAnchor.constraint(equalToConstant: 0)
        tonePickerHeightConstraint?.isActive = true

        tonePickerView = tp
    }

    private func showTonePicker() {
        ensureTonePickerView()
        isTonePickerVisible = true
        tonePickerView?.selectTone(currentToneStyle)
        tonePickerHeightConstraint?.constant = 38
        tonePickerView?.show()
        updateHeight(for: .correctionMode, animated: true)
    }

    private func hideTonePicker() {
        guard isTonePickerVisible else { return }
        isTonePickerVisible = false
        tonePickerView?.hide()
        tonePickerHeightConstraint?.constant = 0
        updateHeight(for: .correctionMode, animated: true)
    }

    private func showCorrectionLanguagePicker() {
        guard !isLanguagePickerVisible else {
            hideLanguagePicker()
            return
        }
        ensureLanguagePickerView()
        isLanguagePickerVisible = true
        languagePickerView?.configureSingleLanguage(code: correctionLanguageCode, title: "교정 언어")
        languagePickerView?.isHidden = false
        languagePickerView?.alpha = 0
        UIView.animate(withDuration: 0.2) {
            self.languagePickerView?.alpha = 1
        }
    }

    // MARK: - Emoji Keyboard

    private func toggleEmojiKeyboard() {
        if isEmojiMode { hideEmojiKeyboard() } else { showEmojiKeyboard() }
    }

    private func showEmojiKeyboard() {
        if emojiKeyboardView == nil {
            guard let inputView = self.inputView else { return }
            let emoji = EmojiKeyboardView()
            emoji.translatesAutoresizingMaskIntoConstraints = false
            emoji.onEmojiSelected = { [weak self] emojiStr in
                guard let self = self else { return }
                if emojiStr == KeyboardLayoutView.backKey {
                    self.textDocumentProxy.deleteBackward()
                } else {
                    self.textDocumentProxy.insertText(emojiStr)
                }
            }
            emoji.onBackToKeyboard = { [weak self] in
                self?.hideEmojiKeyboard()
            }
            inputView.addSubview(emoji)
            NSLayoutConstraint.activate([
                emoji.leadingAnchor.constraint(equalTo: inputView.leadingAnchor),
                emoji.trailingAnchor.constraint(equalTo: inputView.trailingAnchor),
                emoji.bottomAnchor.constraint(equalTo: inputView.bottomAnchor),
                emoji.topAnchor.constraint(equalTo: toolbarView.bottomAnchor),
            ])
            emojiKeyboardView = emoji
        }
        isEmojiMode = true
        keyboardLayoutView.isHidden = true
        emojiKeyboardView?.isHidden = false
    }

    private func hideEmojiKeyboard() {
        isEmojiMode = false
        emojiKeyboardView?.isHidden = true
        keyboardLayoutView.isHidden = false
    }

    private func hasFullAccess() -> Bool {
        if #available(iOSApplicationExtension 11.0, *) {
            return self.hasFullAccess
        }
        return false
    }

    // MARK: - Language Picker

    private func ensureLanguagePickerView() {
        guard languagePickerView == nil, let inputView = self.inputView else { return }
        let picker = LanguagePickerView()
        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.isHidden = true
        picker.onLanguageSelected = { [weak self] tab, language in
            self?.handleLanguageSelection(tab: tab, language: language)
        }
        picker.onDismiss = { [weak self] in
            self?.hideLanguagePicker()
        }
        inputView.addSubview(picker)
        NSLayoutConstraint.activate([
            picker.topAnchor.constraint(equalTo: inputView.topAnchor),
            picker.leadingAnchor.constraint(equalTo: inputView.leadingAnchor),
            picker.trailingAnchor.constraint(equalTo: inputView.trailingAnchor),
            picker.bottomAnchor.constraint(equalTo: inputView.bottomAnchor),
        ])
        languagePickerView = picker
    }

    private func showLanguagePicker(initialTab: LanguagePickerView.Tab = .source) {
        guard !isLanguagePickerVisible else {
            hideLanguagePicker()
            return
        }
        ensureLanguagePickerView()
        isLanguagePickerVisible = true
        languagePickerView?.configure(
            sourceCode: sourceLanguageCode,
            targetCode: targetLanguageCode,
            initialTab: initialTab
        )
        languagePickerView?.isHidden = false
        languagePickerView?.alpha = 0
        UIView.animate(withDuration: 0.2) {
            self.languagePickerView?.alpha = 1
        }
    }

    private func hideLanguagePicker() {
        guard isLanguagePickerVisible else { return }
        isLanguagePickerVisible = false
        UIView.animate(withDuration: 0.15, animations: {
            self.languagePickerView?.alpha = 0
        }) { _ in
            self.languagePickerView?.isHidden = true
        }
    }

    private func handleLanguageSelection(tab: LanguagePickerView.Tab, language: LanguageItem) {
        if currentMode == .correctionMode {
            correctionLanguageCode = language.code
            correctionLanguageBar.updateLanguageName(language.displayName)
            correctionManager.setLanguage(language.code)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.hideLanguagePicker()
            }
            return
        }

        switch tab {
        case .source:
            if language.code == targetLanguageCode {
                targetLanguageCode = sourceLanguageCode
                AppGroupManager.shared.set(targetLanguageCode, forKey: AppConstants.UserDefaultsKeys.targetLanguage)
            }
            sourceLanguageCode = language.code
            AppGroupManager.shared.set(language.code, forKey: AppConstants.UserDefaultsKeys.sourceLanguage)
        case .target:
            if language.code == sourceLanguageCode {
                sourceLanguageCode = targetLanguageCode
                AppGroupManager.shared.set(sourceLanguageCode, forKey: AppConstants.UserDefaultsKeys.sourceLanguage)
            }
            targetLanguageCode = language.code
            AppGroupManager.shared.set(language.code, forKey: AppConstants.UserDefaultsKeys.targetLanguage)
        }

        translationManager.setLanguages(source: sourceLanguageCode, target: targetLanguageCode)
        updateLanguageLabels()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.hideLanguagePicker()
        }
    }

    private func swapLanguages() {
        let temp = sourceLanguageCode
        sourceLanguageCode = targetLanguageCode
        targetLanguageCode = temp

        AppGroupManager.shared.set(sourceLanguageCode, forKey: AppConstants.UserDefaultsKeys.sourceLanguage)
        AppGroupManager.shared.set(targetLanguageCode, forKey: AppConstants.UserDefaultsKeys.targetLanguage)
        translationManager.setLanguages(source: sourceLanguageCode, target: targetLanguageCode)
        updateLanguageLabels()
    }

    private func updateLanguageLabels() {
        guard isTranslationViewsSetUp else { return }
        let sourceName = languageDisplayName(for: sourceLanguageCode)
        let targetName = languageDisplayName(for: targetLanguageCode)
        translationLanguageBar.updateLanguageNames(source: sourceName, target: targetName)
    }

    private func languageDisplayName(for code: String) -> String {
        return LanguagePickerView.supportedLanguages.first(where: { $0.code == code })?.displayName ?? code
    }

    // MARK: - Key Handling

    private func handleKeyTap(_ key: String) {
        hasUserTypedSinceAppeared = true
        switch currentMode {
        case .defaultMode:
            handleDefaultModeKey(key)
        case .translationMode:
            handleTranslationModeKey(key)
        case .correctionMode:
            handleCorrectionModeKey(key)
        case .phraseInputMode:
            handlePhraseInputModeKey(key)
        }
    }

    private func handleDefaultModeKey(_ key: String) {
        switch key {
        case KeyboardLayoutView.backKey:
            if !defaultTextInputHandler.composingText.isEmpty {
                textDocumentProxy.deleteBackward()
                defaultModeComposingLength = 0
                defaultTextInputHandler.handleBackspace()
                if !defaultTextInputHandler.composingText.isEmpty {
                    textDocumentProxy.insertText(defaultTextInputHandler.composingText)
                    defaultModeComposingLength = 1
                }
            } else {
                textDocumentProxy.deleteBackward()
            }

        case KeyboardLayoutView.returnKey:
            if currentTypingWord() != nil {
                StatsManager.shared.incrementWordsTyped()
            }
            commitDefaultComposing()
            textDocumentProxy.insertText("\n")
            isSuggestionDismissedForCurrentWord = false

        case " ":
            if currentTypingWord() != nil {
                StatsManager.shared.incrementWordsTyped()
            }
            commitDefaultComposing()
            textDocumentProxy.insertText(" ")

        default:
            isSuggestionDismissedForCurrentWord = false
            let isKorean = isKoreanJamo(key)
            if isKorean, let char = key.first {
                if defaultModeComposingLength > 0 {
                    textDocumentProxy.deleteBackward()
                    defaultModeComposingLength = 0
                }

                let oldBufferCount = defaultTextInputHandler.buffer.count
                defaultTextInputHandler.handleKey(char, isKorean: true)

                let newBufferCount = defaultTextInputHandler.buffer.count
                if newBufferCount > oldBufferCount {
                    let committedChars = String(defaultTextInputHandler.buffer.suffix(newBufferCount - oldBufferCount))
                    textDocumentProxy.insertText(committedChars)
                    defaultTextInputHandler.resetBuffer()
                }

                if !defaultTextInputHandler.composingText.isEmpty {
                    textDocumentProxy.insertText(defaultTextInputHandler.composingText)
                    defaultModeComposingLength = 1
                }
            } else {
                commitDefaultComposing()
                textDocumentProxy.insertText(key)
            }
        }

        checkAutoCapitalize()
        updateSuggestions()
    }

    private func commitDefaultComposing() {
        if defaultModeComposingLength > 0 {
            defaultTextInputHandler.commitComposing()
            defaultTextInputHandler.resetBuffer()
            defaultModeComposingLength = 0
        }
    }

    private func handleTranslationModeKey(_ key: String) {
        switch key {
        case KeyboardLayoutView.backKey:
            modeTextInputHandler.handleBackspace()

        case KeyboardLayoutView.returnKey:
            modeTextInputHandler.handleNewline()

        case " ":
            modeTextInputHandler.handleSpace()

        default:
            if modeTextInputHandler.totalLength >= AppConstants.Limits.maxCharacters {
                hapticFeedback.impactOccurred()
                showStatusMessage(String(format: L("keyboard.error.max_chars"), AppConstants.Limits.maxCharacters))
                return
            }

            let isKorean = isKoreanJamo(key)
            if let char = key.first {
                modeTextInputHandler.handleKey(char, isKorean: isKorean)
            }
        }
    }

    private func handleCorrectionModeKey(_ key: String) {
        switch key {
        case KeyboardLayoutView.backKey:
            modeTextInputHandler.handleBackspace()

        case KeyboardLayoutView.returnKey:
            modeTextInputHandler.handleNewline()

        case " ":
            modeTextInputHandler.handleSpace()

        default:
            if modeTextInputHandler.totalLength >= AppConstants.Limits.maxCharacters {
                hapticFeedback.impactOccurred()
                return
            }

            let isKorean = isKoreanJamo(key)
            if let char = key.first {
                modeTextInputHandler.handleKey(char, isKorean: isKorean)
            }
        }
    }

    private func isKoreanJamo(_ key: String) -> Bool {
        guard let scalar = key.unicodeScalars.first else { return false }
        return (0x3131...0x3163).contains(scalar.value)
    }

    // MARK: - Trackpad Cursor Movement

    private func handleCursorMove(horizontal: Int, vertical: Int) {
        if horizontal != 0 {
            textDocumentProxy.adjustTextPosition(byCharacterOffset: horizontal)
        }
        if vertical != 0 {
            if vertical < 0 {
                moveUp()
            } else {
                moveDown()
            }
        }
    }

    /// Estimate visual line width based on screen width and current language.
    private var estimatedCharsPerLine: Int {
        let screenWidth = UIScreen.main.bounds.width
        let textWidth = screenWidth * 0.85  // ~85% of screen for typical text view margins
        let lang = keyboardLayoutView.getCurrentLanguage()
        let avgCharWidth: CGFloat
        switch lang {
        case .korean: avgCharWidth = 17
        case .russian: avgCharWidth = 12
        default: avgCharWidth = 9
        }
        return max(10, Int(textWidth / avgCharWidth))
    }

    /// Move cursor up one line.
    /// Uses actual \n positions when available, falls back to estimated offset for soft-wrapped text.
    private func moveUp() {
        guard let before = textDocumentProxy.documentContextBeforeInput, !before.isEmpty else { return }

        // Find the last newline before cursor — that's the start of current line
        guard let currentLineStart = before.lastIndex(of: "\n") else {
            // No \n found — soft-wrapped text, use estimated offset
            textDocumentProxy.adjustTextPosition(byCharacterOffset: -estimatedCharsPerLine)
            return
        }

        let currentColumn = before.distance(from: before.index(after: currentLineStart), to: before.endIndex)

        // Find the previous line
        let textBeforeCurrentLine = before[before.startIndex..<currentLineStart]
        let prevLineStart: String.Index
        if let prevNewline = textBeforeCurrentLine.lastIndex(of: "\n") {
            prevLineStart = textBeforeCurrentLine.index(after: prevNewline)
        } else {
            prevLineStart = textBeforeCurrentLine.startIndex
        }

        let prevLineLength = before.distance(from: prevLineStart, to: currentLineStart)
        let targetColumn = min(currentColumn, prevLineLength)

        // Move back: current column chars + newline char + remaining chars in prev line
        let offset = -(currentColumn + 1 + (prevLineLength - targetColumn))
        textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
    }

    /// Move cursor down one line.
    /// Uses actual \n positions when available, falls back to estimated offset for soft-wrapped text.
    private func moveDown() {
        let after = textDocumentProxy.documentContextAfterInput ?? ""

        // Try \n-based accurate movement
        guard !after.isEmpty, let currentLineEnd = after.firstIndex(of: "\n") else {
            // No context, empty, or no \n — use estimated offset
            textDocumentProxy.adjustTextPosition(byCharacterOffset: estimatedCharsPerLine)
            return
        }

        // Calculate current column position
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        let currentColumn: Int
        if let lastNewline = before.lastIndex(of: "\n") {
            currentColumn = before.distance(from: before.index(after: lastNewline), to: before.endIndex)
        } else {
            currentColumn = before.count
        }

        // Find the next line's length
        let nextLineStart = after.index(after: currentLineEnd)
        let nextLineEnd: String.Index
        if let nextNewline = after[nextLineStart...].firstIndex(of: "\n") {
            nextLineEnd = nextNewline
        } else {
            nextLineEnd = after.endIndex
        }

        let nextLineLength = after.distance(from: nextLineStart, to: nextLineEnd)
        let targetColumn = min(currentColumn, nextLineLength)

        // Offset = chars remaining on current line + 1 (newline) + targetColumn
        let charsToCurrentLineEnd = after.distance(from: after.startIndex, to: currentLineEnd)
        let offset = charsToCurrentLineEnd + 1 + targetColumn
        textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
    }

    // MARK: - Status Messages

    private func showStatusMessage(_ message: String) {
        statusMessageTimer?.cancel()

        // Floating toast — visible in all modes
        toastLabel.text = "  \(message)  "
        toastLabel.isHidden = false
        toastLabel.alpha = 0
        inputView?.bringSubviewToFront(toastLabel)

        UIView.animate(withDuration: 0.2) {
            self.toastLabel.alpha = 1
        }

        let workItem = DispatchWorkItem { [weak self] in
            UIView.animate(withDuration: 0.3, animations: {
                self?.toastLabel.alpha = 0
            }) { _ in
                self?.toastLabel.isHidden = true
            }
        }
        statusMessageTimer = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: workItem)
    }

    // MARK: - Autocorrect Suggestions

    private func currentTypingWord() -> String? {
        guard let context = textDocumentProxy.documentContextBeforeInput else { return nil }
        let components = context.components(separatedBy: CharacterSet.whitespacesAndNewlines)
        return components.last?.isEmpty == false ? components.last : nil
    }

    private func dismissSuggestions() {
        isSuggestionDismissedForCurrentWord = true
        toolbarView.hideSuggestions()
    }

    private func updateSuggestions() {
        guard currentMode == .defaultMode, isAutocorrectEnabled, hasUserTypedSinceAppeared else {
            toolbarView.hideSuggestions(); return
        }
        guard !isSuggestionDismissedForCurrentWord else { return }

        // Only show suggestions when actively typing a word (not after space/enter/empty)
        let word = currentTypingWord()
        guard let word = word, !word.isEmpty else {
            toolbarView.hideSuggestions(); return
        }

        let currentLang = keyboardLayoutView.getCurrentLanguage()
        let isComposing = !defaultTextInputHandler.composingText.isEmpty

        let result = suggestionManager.getSuggestions(
            context: textDocumentProxy.documentContextBeforeInput,
            currentWord: word,
            isComposing: isComposing,
            language: currentLang
        )
        switch result.mode {
        case .none: toolbarView.hideSuggestions()
        case .autocorrect, .prediction: toolbarView.showSuggestions(result.suggestions)
        }
    }

    private func applySuggestion(_ suggestion: String) {
        let word = currentTypingWord()
        if let word = word, !word.isEmpty {
            commitDefaultComposing()
            for _ in 0..<word.count { textDocumentProxy.deleteBackward() }
        }
        textDocumentProxy.insertText(suggestion + " ")
        toolbarView.hideSuggestions()
        checkAutoCapitalize()
        DispatchQueue.main.async { [weak self] in
            self?.updateSuggestions()
        }
    }

    // MARK: - Return Key

    private func updateReturnKeyAppearance() {
        let returnType = textDocumentProxy.returnKeyType ?? .default

        switch returnType {
        case .go:
            keyboardLayoutView.returnKeyDisplayName = L("keyboard.return.go")
            keyboardLayoutView.returnKeyIsBlue = true
        case .search:
            keyboardLayoutView.returnKeyDisplayName = L("keyboard.return.search")
            keyboardLayoutView.returnKeyIsBlue = true
        case .send:
            keyboardLayoutView.returnKeyDisplayName = L("keyboard.return.send")
            keyboardLayoutView.returnKeyIsBlue = true
        case .done:
            keyboardLayoutView.returnKeyDisplayName = L("keyboard.return.done")
            keyboardLayoutView.returnKeyIsBlue = true
        case .next:
            keyboardLayoutView.returnKeyDisplayName = L("keyboard.return.next")
            keyboardLayoutView.returnKeyIsBlue = true
        case .join:
            keyboardLayoutView.returnKeyDisplayName = L("keyboard.return.join")
            keyboardLayoutView.returnKeyIsBlue = true
        case .route:
            keyboardLayoutView.returnKeyDisplayName = L("keyboard.return.route")
            keyboardLayoutView.returnKeyIsBlue = true
        case .emergencyCall:
            keyboardLayoutView.returnKeyDisplayName = L("keyboard.return.emergency")
            keyboardLayoutView.returnKeyIsBlue = true
        case .continue:
            keyboardLayoutView.returnKeyDisplayName = L("keyboard.return.continue")
            keyboardLayoutView.returnKeyIsBlue = true
        default:
            // .default — used in text editors, messaging body, notes → newline
            keyboardLayoutView.returnKeyDisplayName = L("keyboard.return.newline")
            keyboardLayoutView.returnKeyIsBlue = false
        }
    }

    // MARK: - Open Containing App

    @objc protocol URLOpener {
        @objc(openURL:options:completionHandler:)
        func open(_ url: URL, options: [String: Any], completionHandler: ((Bool) -> Void)?)
    }

    private func openContainingApp(path: String = "settings") {
        guard let url = URL(string: "translatorkeyboard://\(path)") else { return }
        var responder: UIResponder? = self
        while let r = responder {
            if let opener = r as? URLOpener {
                opener.open(url, options: [:], completionHandler: nil)
                return
            }
            responder = r.next
        }
    }

    private func showDailyLimitReached(mode: CompositionSession.SessionMode) {
        let modeText = mode == .correct ? L("home.stat.corrections") : L("home.stat.translations")
        let rewardMode: RewardMode = mode == .correct ? .correction : .translation
        let remaining = CompositionSessionManager.shared.remainingSessions(for: mode)

        if remaining <= 0 {
            // 토스트 메시지에 광고/업그레이드 안내 포함
            let message: String
            if DailyUsageManager.shared.canWatchRewardedAd(for: rewardMode) {
                message = String(format: L("session_limit.watch_ad"), modeText)
            } else {
                message = String(format: L("session_limit.upgrade"), modeText)
            }
            showStatusMessage(message)

            // 메인 앱의 페이월 또는 리워드 광고 화면으로 이동
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                if DailyUsageManager.shared.canWatchRewardedAd(for: rewardMode) {
                    self?.openContainingApp(path: "reward-ad?mode=\(rewardMode.rawValue)")
                } else {
                    self?.openContainingApp(path: "paywall")
                }
            }
        } else {
            showStatusMessage(L("session_limit.title"))
        }
    }

    // MARK: - Auto Capitalize

    private func checkAutoCapitalize() {
        guard AppGroupManager.shared.bool(forKey: AppConstants.UserDefaultsKeys.autoCapitalize) else { return }
        guard currentMode == .defaultMode else { return }
        guard keyboardLayoutView.getCurrentLanguage() == .english else { return }

        let shouldCapitalize: Bool
        let context = textDocumentProxy.documentContextBeforeInput

        if context == nil || context?.isEmpty == true {
            shouldCapitalize = true
        } else if let text = context,
                  text.hasSuffix(". ") || text.hasSuffix("? ") || text.hasSuffix("! ") || text.hasSuffix("\n") {
            shouldCapitalize = true
        } else {
            shouldCapitalize = false
        }

        if shouldCapitalize {
            keyboardLayoutView.setShifted(true)
        }
    }

    // MARK: - Appearance

    private func updateKeyboardAppearance() {
        let isDark = textDocumentProxy.keyboardAppearance == .dark
        let theme = KeyboardTheme.currentTheme()

        // 시스템 둥근 배경을 덮기 위해 inputView 배경색 설정
        if let theme = theme {
            inputView?.backgroundColor = theme.keyboardBackground
        } else if isDark {
            inputView?.backgroundColor = UIColor(white: 0.12, alpha: 1)
        } else {
            inputView?.backgroundColor = UIColor(red: 0.82, green: 0.84, blue: 0.86, alpha: 1)
        }

        keyboardLayoutView.applyTheme(theme)
        keyboardLayoutView.updateAppearance(isDark: isDark)
        toolbarView.applyTheme(theme)
        toolbarView.updateAppearance(isDark: isDark)
        emojiKeyboardView?.updateAppearance(isDark: isDark)
        if isTranslationViewsSetUp {
            translationLanguageBar.applyTheme(theme)
            translationLanguageBar.updateAppearance(isDark: isDark)
            translationInputView.applyTheme(theme)
            translationInputView.updateAppearance(isDark: isDark)
        }
        if isCorrectionViewsSetUp {
            correctionLanguageBar.applyTheme(theme)
            correctionLanguageBar.updateAppearance(isDark: isDark)
            correctionInputView.applyTheme(theme)
            correctionInputView.updateAppearance(isDark: isDark)
        }
        tonePickerView?.applyTheme(theme)
        tonePickerView?.updateAppearance(isDark: isDark)
        savedPhrasesView?.updateAppearance(isDark: isDark)
        clipboardHistoryView?.updateAppearance(isDark: isDark)
        if isPhraseViewsSetUp {
            phraseInputHeaderView.applyTheme(theme)
            phraseInputHeaderView.updateAppearance(isDark: isDark)
            phraseInputView.applyTheme(theme)
            phraseInputView.updateAppearance(isDark: isDark)
        }
    }

    // MARK: - Status Popup (Proposal 02)

    private var statusPopupView: StatusPopupView?

    private func showStatusPopup() {
        hideContextMenu()
        guard statusPopupView == nil else {
            hideStatusPopup()
            return
        }
        guard let inputView = self.inputView else { return }

        let popup = StatusPopupView()
        popup.translatesAutoresizingMaskIntoConstraints = false
        inputView.addSubview(popup)
        NSLayoutConstraint.activate([
            popup.topAnchor.constraint(equalTo: toolbarView.bottomAnchor),
            popup.leadingAnchor.constraint(equalTo: inputView.leadingAnchor),
            popup.trailingAnchor.constraint(equalTo: inputView.trailingAnchor),
            popup.bottomAnchor.constraint(equalTo: inputView.bottomAnchor),
        ])

        // Populate data
        let corrUsed = DailyUsageManager.shared.correctionCount
        let corrRemain = DailyUsageManager.shared.remainingCorrections
        let corrTotal = corrUsed + corrRemain
        let transUsed = DailyUsageManager.shared.translationCount
        let transRemain = DailyUsageManager.shared.remainingTranslations
        let transTotal = transUsed + transRemain
        let tier = SubscriptionStatus.shared.currentTier
        let planName: String
        switch tier {
        case .free: planName = "Free"
        case .pro: planName = "Pro"
        case .premium: planName = "Premium"
        }
        popup.update(corrUsed: corrUsed, corrTotal: corrTotal,
                     transUsed: transUsed, transTotal: transTotal,
                     planName: planName, isPro: tier != .free)

        popup.onUpgradeTap = { [weak self] in
            self?.hideStatusPopup()
            self?.openContainingApp(path: "paywall")
        }
        popup.onDismiss = { [weak self] in
            self?.hideStatusPopup()
        }

        popup.alpha = 0
        UIView.animate(withDuration: 0.2) {
            popup.alpha = 1
        }

        statusPopupView = popup
        inputView.bringSubviewToFront(toastLabel)
    }

    private func hideStatusPopup() {
        guard let popup = statusPopupView else { return }
        UIView.animate(withDuration: 0.15, animations: {
            popup.alpha = 0
        }) { _ in
            popup.removeFromSuperview()
        }
        statusPopupView = nil
    }

    // MARK: - Context Menu (Proposal 02)

    private var contextMenuView: ContextMenuView?

    private func showContextMenu() {
        hideStatusPopup()
        guard contextMenuView == nil else {
            hideContextMenu()
            return
        }
        guard let inputView = self.inputView else { return }

        let menu = ContextMenuView()
        menu.translatesAutoresizingMaskIntoConstraints = false
        inputView.addSubview(menu)
        NSLayoutConstraint.activate([
            menu.topAnchor.constraint(equalTo: toolbarView.bottomAnchor),
            menu.leadingAnchor.constraint(equalTo: inputView.leadingAnchor),
            menu.trailingAnchor.constraint(equalTo: inputView.trailingAnchor),
            menu.bottomAnchor.constraint(equalTo: inputView.bottomAnchor),
        ])

        menu.onSettingsTap = { [weak self] in
            self?.hideContextMenu()
            self?.openContainingApp(path: "settings")
        }
        menu.onHelpTap = { [weak self] in
            self?.hideContextMenu()
            self?.openContainingApp(path: "help")
        }
        menu.onDismiss = { [weak self] in
            self?.hideContextMenu()
        }

        menu.alpha = 0
        UIView.animate(withDuration: 0.2) {
            menu.alpha = 1
        }

        contextMenuView = menu
        inputView.bringSubviewToFront(toastLabel)
    }

    private func hideContextMenu() {
        guard let menu = contextMenuView else { return }
        UIView.animate(withDuration: 0.15, animations: {
            menu.alpha = 0
        }) { _ in
            menu.removeFromSuperview()
        }
        contextMenuView = nil
    }

    // MARK: - Badge Count Update

    private func updateToolbarBadge() {
        let corrRemaining = CompositionSessionManager.shared.remainingSessions(for: .correct)
        let transRemaining = CompositionSessionManager.shared.remainingSessions(for: .translate)
        let total = max(0, corrRemaining) + max(0, transRemaining)
        toolbarView.updateBadgeCount(total)
    }

    // MARK: - Return Key Mode Update (Proposal 03)

    private func updateReturnKeyForCurrentMode() {
        let hasText: Bool
        switch currentMode {
        case .translationMode:
            hasText = !modeTextInputHandler.fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            keyboardLayoutView.updateReturnKey(mode: .translationMode, hasText: hasText)
        case .correctionMode:
            hasText = !modeTextInputHandler.fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            keyboardLayoutView.updateReturnKey(mode: .correctionMode, hasText: hasText)
        case .defaultMode, .phraseInputMode:
            keyboardLayoutView.clearReturnKeyOverride()
        }
    }
}


// MARK: - TextInputHandlerDelegate

extension KeyboardViewController: TextInputHandlerDelegate {
    func textInputHandler(_ handler: TextInputHandler, didUpdateBuffer text: String) {
        let displayText = handler.fullText
        switch currentMode {
        case .correctionMode:
            correctionInputView.setDisplayText(displayText)
            correctionManager.requestCorrection(text: displayText)
        case .phraseInputMode:
            phraseInputView.setDisplayText(displayText)
        case .translationMode:
            translationInputView.setDisplayText(displayText)
            translationManager.requestTranslation(text: displayText)
        case .defaultMode:
            break
        }
        updateReturnKeyForCurrentMode()
    }

    func textInputHandler(_ handler: TextInputHandler, didUpdateComposing text: String) {
        let displayText = handler.fullText
        switch currentMode {
        case .correctionMode:
            correctionInputView.setDisplayText(displayText)
            correctionManager.requestCorrection(text: displayText)
        case .phraseInputMode:
            phraseInputView.setDisplayText(displayText)
        case .translationMode:
            translationInputView.setDisplayText(displayText)
            translationManager.requestTranslation(text: displayText)
        case .defaultMode:
            break
        }
        updateReturnKeyForCurrentMode()
    }
}

// MARK: - CorrectionManagerDelegate

extension KeyboardViewController: CorrectionManagerDelegate {
    func correctionManager(_ manager: CorrectionManager, didCorrect text: String, language: String) {
        textProxyManager.updateProxy(textDocumentProxy)
        textProxyManager.replaceText(with: text)
    }

    func correctionManager(_ manager: CorrectionManager, didFailWithError error: TranslationError) {
        switch error {
        case .timeout:
            showStatusMessage(L("keyboard.error.timeout"))
        case .offline:
            showStatusMessage(L("keyboard.error.offline"))
        case .rateLimited:
            showStatusMessage(L("keyboard.error.rate_limited"))
        case .networkError, .serverError, .invalidResponse:
            showStatusMessage(L("keyboard.error.correct_failed"))
        }
    }

    // 오타교정 진행 로그
    func correctionManagerDidStartCorrecting(_ manager: CorrectionManager) {
        // showStatusMessage(L("keyboard.status.correcting"))
    }
}

// MARK: - TranslationManagerDelegate

extension KeyboardViewController: TranslationManagerDelegate {
    func translationManager(_ manager: TranslationManager, didTranslate text: String, from source: String, to target: String) {
        textProxyManager.updateProxy(textDocumentProxy)
        textProxyManager.replaceText(with: text)
    }

    func translationManager(_ manager: TranslationManager, didFailWithError error: TranslationError) {
        switch error {
        case .timeout:
            showStatusMessage(L("keyboard.error.timeout"))
        case .offline:
            showStatusMessage(L("keyboard.error.offline"))
        case .rateLimited:
            showStatusMessage(L("keyboard.error.rate_limited"))
        case .networkError, .serverError, .invalidResponse:
            showStatusMessage(L("keyboard.error.translate_failed"))
        }
    }

    // 번역 진행 로그
    func translationManagerDidStartTranslating(_ manager: TranslationManager) {
        // showStatusMessage(L("keyboard.status.translating"))
    }
}
