import UIKit

// MARK: - Safe Collection Subscript

private extension Collection {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// MARK: - ToneItem

private struct ToneItem {
    let id: String
    let emoji: String
    let nameKey: String
}

private let toneItems: [ToneItem] = [
    ToneItem(id: "casual", emoji: "\u{1F4AC}", nameKey: "tone.casual"),
    ToneItem(id: "formal", emoji: "\u{1F3A9}", nameKey: "tone.formal"),
    ToneItem(id: "polished", emoji: "\u{2728}", nameKey: "tone.polished"),
    ToneItem(id: "friendly", emoji: "\u{1F60A}", nameKey: "tone.friendly"),
    ToneItem(id: "empathetic", emoji: "\u{1F917}", nameKey: "tone.empathetic"),
    ToneItem(id: "confident", emoji: "\u{1F4AA}", nameKey: "tone.confident"),
    ToneItem(id: "witty", emoji: "\u{1F60F}", nameKey: "tone.witty"),
    ToneItem(id: "persuasive", emoji: "\u{1F3AF}", nameKey: "tone.persuasive"),
    ToneItem(id: "enthusiastic", emoji: "\u{1F389}", nameKey: "tone.enthusiastic"),
    ToneItem(id: "apologetic", emoji: "\u{1F64F}", nameKey: "tone.apologetic"),
    ToneItem(id: "social", emoji: "\u{270C}\u{FE0F}", nameKey: "tone.social"),
    ToneItem(id: "professional", emoji: "\u{1F4BC}", nameKey: "tone.professional"),
]

// MARK: - AIWriterViewController

class AIWriterViewController: UIViewController {

    // MARK: - Properties

    private var selectedTone = "casual"
    private var selectedLength = "medium"
    private var outputLanguage = "auto"
    private var isContextExpanded = false
    private var lastPrompt = ""

    // Bottom Sheet state
    private var toneSheet: UIView?
    private var lengthSheet: UIView?
    private var langSheet: UIView?
    private var sheetOverlay: UIView?

    // Constraint toggle for context expand/collapse (Fix 3)
    private var toggleBottomConstraint: NSLayoutConstraint!
    private var containerBottomConstraint: NSLayoutConstraint!

    // Dynamic Height Properties (v6)
    private var inputTextViewHeightConstraint: NSLayoutConstraint!
    private var contextTextViewHeightConstraint: NSLayoutConstraint!

    // Option card value labels
    private let langValueLabel = UILabel()
    private let toneValueLabel = UILabel()
    private let lengthValueLabel = UILabel()

    // MARK: - UI Elements

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let inputTextView = UITextView()
    private let generateButton = UIButton(type: .system)
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private var inputContainer: UIView!

    // Clear buttons for text views
    private weak var inputClearButton: UIButton?
    private weak var contextClearButton: UIButton?

    // Template Form Properties
    private var activeTemplate: AIWriterTemplate?
    private var templateFormContainer: UIView?
    private var templateFieldTextFields: [UITextField] = []

    // ★ v7: 폼 카드 활성 시 contextToggle 연결용 제약
    private var contextToggleToInputBottomConstraint: NSLayoutConstraint?
    private var contextToggleToFormCardBottomConstraint: NSLayoutConstraint?

    // Output language data (Feature 5)
    private struct OutputLanguageItem {
        let code: String
        let flag: String
        let nativeName: String
    }

    private let outputLanguages: [OutputLanguageItem] = [
        OutputLanguageItem(code: "auto", flag: "\u{1F310}", nativeName: ""),
        OutputLanguageItem(code: "ko", flag: "\u{1F1F0}\u{1F1F7}", nativeName: "\u{D55C}\u{AD6D}\u{C5B4}"),
        OutputLanguageItem(code: "en", flag: "\u{1F1FA}\u{1F1F8}", nativeName: "English"),
        OutputLanguageItem(code: "ja", flag: "\u{1F1EF}\u{1F1F5}", nativeName: "\u{65E5}\u{672C}\u{8A9E}"),
        OutputLanguageItem(code: "zh-CN", flag: "\u{1F1E8}\u{1F1F3}", nativeName: "\u{4E2D}\u{6587}(\u{7B80}\u{4F53})"),
        OutputLanguageItem(code: "zh-TW", flag: "\u{1F1F9}\u{1F1FC}", nativeName: "\u{4E2D}\u{6587}(\u{7E41}\u{9AD4})"),
        OutputLanguageItem(code: "vi", flag: "\u{1F1FB}\u{1F1F3}", nativeName: "Ti\u{1EBF}ng Vi\u{1EC7}t"),
        OutputLanguageItem(code: "th", flag: "\u{1F1F9}\u{1F1ED}", nativeName: "\u{0E44}\u{0E17}\u{0E22}"),
        OutputLanguageItem(code: "id", flag: "\u{1F1EE}\u{1F1E9}", nativeName: "Bahasa Indonesia"),
        OutputLanguageItem(code: "es", flag: "\u{1F1EA}\u{1F1F8}", nativeName: "Espa\u{00F1}ol"),
        OutputLanguageItem(code: "fr", flag: "\u{1F1EB}\u{1F1F7}", nativeName: "Fran\u{00E7}ais"),
        OutputLanguageItem(code: "de", flag: "\u{1F1E9}\u{1F1EA}", nativeName: "Deutsch"),
        OutputLanguageItem(code: "ru", flag: "\u{1F1F7}\u{1F1FA}", nativeName: "\u{0420}\u{0443}\u{0441}\u{0441}\u{043A}\u{0438}\u{0439}"),
        OutputLanguageItem(code: "it", flag: "\u{1F1EE}\u{1F1F9}", nativeName: "Italiano"),
    ]

    // Character counter
    private lazy var charCountLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = AppColors.textMuted
        label.textAlignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // Remaining badge
    private lazy var remainingBadge: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 11, weight: .bold)
        label.textColor = .white
        label.backgroundColor = UIColor.white.withAlphaComponent(0.3)
        label.textAlignment = .center
        label.layer.cornerRadius = 11
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // Input placeholder (Fix 1)
    private lazy var inputPlaceholderLabel: UILabel = {
        let label = UILabel()
        label.text = L("ai_writer.input_placeholder")
        label.font = .systemFont(ofSize: 15)
        label.textColor = AppColors.textMuted
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // Reply context
    private let contextTextView = UITextView()
    private let contextContainer = UIView()
    private let contextToggleButton = UIButton(type: .system)

    // Context placeholder (Fix 4)
    private lazy var contextPlaceholderLabel: UILabel = {
        let label = UILabel()
        label.text = L("ai_writer.reply_context_placeholder")
        label.font = .systemFont(ofSize: 13)
        label.textColor = AppColors.textMuted
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // Result carousel
    private let resultScrollView = UIScrollView()
    private var resultScrollViewHeightConstraint: NSLayoutConstraint?
    private var resultCards: [UIView] = []
    private var resultLabels: [UILabel] = []
    private var lastSavedItemId: String?
    private let pageControl = UIPageControl()

    // Bottom bar
    private let bottomBar = UIView()

    // Clipboard banner localized controls
    private let clipboardBannerTextLabel = UILabel()
    private let clipboardBannerUseButton = UIButton(type: .system)
    private let clipboardBannerDismissButton = UIButton(type: .system)

    // Clipboard banner
    private lazy var clipboardBanner: UIView = {
        let banner = UIView()
        banner.backgroundColor = AppColors.tierAccent.withAlphaComponent(0.1)
        banner.layer.cornerRadius = 10
        banner.isHidden = true
        banner.translatesAutoresizingMaskIntoConstraints = false

        let icon = UILabel()
        icon.text = "\u{1F4CB}"
        icon.font = .systemFont(ofSize: 16)
        icon.translatesAutoresizingMaskIntoConstraints = false

        clipboardBannerTextLabel.text = L("ai_writer.clipboard_suggest")
        clipboardBannerTextLabel.font = .systemFont(ofSize: 13, weight: .medium)
        clipboardBannerTextLabel.textColor = AppColors.text
        clipboardBannerTextLabel.translatesAutoresizingMaskIntoConstraints = false

        clipboardBannerUseButton.setTitle(L("ai_writer.clipboard_use"), for: .normal)
        clipboardBannerUseButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        clipboardBannerUseButton.setTitleColor(AppColors.tierAccent, for: .normal)
        clipboardBannerUseButton.addTarget(self, action: #selector(acceptClipboard), for: .touchUpInside)
        clipboardBannerUseButton.translatesAutoresizingMaskIntoConstraints = false

        clipboardBannerDismissButton.setTitle(L("ai_writer.clipboard_dismiss"), for: .normal)
        clipboardBannerDismissButton.titleLabel?.font = .systemFont(ofSize: 13)
        clipboardBannerDismissButton.setTitleColor(AppColors.textMuted, for: .normal)
        clipboardBannerDismissButton.addTarget(self, action: #selector(dismissClipboard), for: .touchUpInside)
        clipboardBannerDismissButton.translatesAutoresizingMaskIntoConstraints = false

        banner.addSubview(icon)
        banner.addSubview(clipboardBannerTextLabel)
        banner.addSubview(clipboardBannerUseButton)
        banner.addSubview(clipboardBannerDismissButton)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 12),
            icon.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
            clipboardBannerTextLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            clipboardBannerTextLabel.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
            clipboardBannerDismissButton.trailingAnchor.constraint(equalTo: banner.trailingAnchor, constant: -12),
            clipboardBannerDismissButton.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
            clipboardBannerUseButton.trailingAnchor.constraint(equalTo: clipboardBannerDismissButton.leadingAnchor, constant: -12),
            clipboardBannerUseButton.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
            banner.heightAnchor.constraint(equalToConstant: 44),
        ])

        return banner
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColors.bg
        navigationItem.title = L("ai_writer.title")
        setupNavigation()
        setupUI()
        updateGenerateButton()
        NotificationCenter.default.addObserver(self, selector: #selector(handleLanguageChange), name: .languageDidChange, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleSubscriptionChange),
            name: .subscriptionStatusDidChange, object: nil
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        LocalizationManager.shared.reload()
        updateGenerateButton()
        checkClipboardForReply()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow(_:)),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: .languageDidChange, object: nil)
        NotificationCenter.default.removeObserver(self, name: .subscriptionStatusDidChange, object: nil)
    }

    // MARK: - Setup

    private func setupNavigation() {
        navigationController?.navigationBar.prefersLargeTitles = true
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.largeTitleTextAttributes = [.foregroundColor: AppColors.text]
        appearance.titleTextAttributes = [.foregroundColor: AppColors.text]
        navigationController?.navigationBar.standardAppearance = appearance
        navigationController?.navigationBar.scrollEdgeAppearance = appearance

        let historyBtn = UIBarButtonItem(
            image: UIImage(systemName: "clock.arrow.circlepath"),
            style: .plain,
            target: self,
            action: #selector(showHistory)
        )
        navigationItem.rightBarButtonItem = historyBtn
    }

    private func setupUI() {
        // 1. ScrollView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .interactive
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // 2. ContentStack
        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 4),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -120),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -40),
        ])

        // 1 Input section (top)
        setupInputSection()

        // 2 Quick templates (horizontal scroll)
        setupTemplateSection()

        // 3 Options card (language/tone/length grouped)
        setupOptionsCard()

        // 4 Result area
        setupResultArea()

        // 5 Bottom fixed CTA
        setupBottomBar()

        // Tap outside to dismiss keyboard
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tapGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(tapGesture)
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    @objc private func handleSubscriptionChange() {
        clipboardBanner.backgroundColor = AppColors.tierAccent.withAlphaComponent(0.1)
        clipboardBannerUseButton.setTitleColor(AppColors.tierAccent, for: .normal)
        inputTextView.tintColor = AppColors.tierAccent
        contextToggleButton.tintColor = AppColors.tierAccent
        contextToggleButton.setTitleColor(AppColors.tierAccent, for: .normal)
        contextTextView.tintColor = AppColors.tierAccent
        generateButton.backgroundColor = AppColors.tierAccent
        loadingIndicator.color = AppColors.tierAccent
        pageControl.currentPageIndicatorTintColor = AppColors.tierAccent
    }

    @objc private func handleLanguageChange() {
        LocalizationManager.shared.reload()
        rebuildLocalizedUI()
    }

    private func localizedToneDisplayName(for toneId: String) -> String {
        if let item = toneItems.first(where: { $0.id == toneId }) {
            return "\(item.emoji) \(L(item.nameKey))"
        }
        return toneId
    }

    private func localizedLengthDisplayName(for lengthId: String) -> String {
        let lengths = [
            "short": L("ai_writer.length.short"),
            "medium": L("ai_writer.length.medium"),
            "long": L("ai_writer.length.long")
        ]
        return lengths[lengthId] ?? lengthId
    }

    private func localizedOutputLanguageDisplayName(for code: String) -> String {
        guard let lang = outputLanguages.first(where: { $0.code == code }) else { return code }
        return lang.code == "auto" ? L("ai_writer.lang.auto") : lang.nativeName
    }

    private func applySelectedOutputLanguage(_ code: String) {
        outputLanguage = code
        langValueLabel.text = localizedOutputLanguageDisplayName(for: code)
    }

    private func updateLocalizedDynamicValues() {
        navigationItem.title = L("ai_writer.title")
        inputPlaceholderLabel.text = L("ai_writer.input_placeholder")
        contextPlaceholderLabel.text = L("ai_writer.reply_context_placeholder")
        clipboardBannerTextLabel.text = L("ai_writer.clipboard_suggest")
        clipboardBannerUseButton.setTitle(L("ai_writer.clipboard_use"), for: .normal)
        clipboardBannerDismissButton.setTitle(L("ai_writer.clipboard_dismiss"), for: .normal)

        toneValueLabel.text = localizedToneDisplayName(for: selectedTone)
        lengthValueLabel.text = localizedLengthDisplayName(for: selectedLength)
        langValueLabel.text = localizedOutputLanguageDisplayName(for: outputLanguage)

        if isContextExpanded {
            let closeIcon = UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .medium))
            contextToggleButton.setImage(closeIcon, for: .normal)
            contextToggleButton.setTitle(" " + L("ai_writer.reply_close"), for: .normal)
        } else {
            let chatIcon = UIImage(systemName: "bubble.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .medium))
            contextToggleButton.setImage(chatIcon, for: .normal)
            contextToggleButton.setTitle(" " + L("ai_writer.reply_paste"), for: .normal)
        }

        updateGenerateButton()
    }

    private func rebuildLocalizedUI() {
        let currentInputText = inputTextView.text
        let currentContextText = contextTextView.text
        let currentResults = resultLabels.compactMap { $0.text }
        let currentPage = pageControl.currentPage

        contentStack.arrangedSubviews.forEach {
            contentStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        resultCards.removeAll()
        resultLabels.removeAll()
        resultScrollView.subviews.forEach { $0.removeFromSuperview() }
        resultScrollView.isHidden = true
        pageControl.isHidden = true

        setupInputSection()
        setupTemplateSection()
        setupOptionsCard()
        setupResultArea()

        inputTextView.text = currentInputText
        contextTextView.text = currentContextText
        inputPlaceholderLabel.isHidden = !(currentInputText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        contextPlaceholderLabel.isHidden = !(currentContextText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

        if isContextExpanded {
            toggleBottomConstraint.isActive = false
            containerBottomConstraint.isActive = true
            contextContainer.isHidden = false
        } else {
            containerBottomConstraint.isActive = false
            toggleBottomConstraint.isActive = true
            contextContainer.isHidden = true
        }

        updateLocalizedDynamicValues()
        updateCharacterCounter()
        updateGenerateButtonState()
        view.layoutIfNeeded()

        if !currentResults.isEmpty {
            displayResults(currentResults)
            let page = min(currentPage, max(0, currentResults.count - 1))
            let cardWidth = view.bounds.width - 56
            pageControl.currentPage = page
            resultScrollView.contentOffset = CGPoint(x: CGFloat(page) * (cardWidth + 8), y: 0)
        }

        checkClipboardForReply()
        updateClearButtonVisibility()
    }

    // MARK: - Keyboard Avoidance

    // MARK: - Smart Scroll (v6)
    private func scrollToCaretInTextView(_ textView: UITextView) {
        guard scrollView.contentInset.bottom > 0 else { return }

        guard let selectedRange = textView.selectedTextRange,
              let end = Optional(selectedRange.end) else { return }
        let caretRect = textView.caretRect(for: end)
        guard !caretRect.isNull && !caretRect.isInfinite else { return }

        let caretInScroll = textView.convert(caretRect, to: scrollView)

        if let card = inputContainer {
            let cardTopInScroll = card.convert(CGPoint.zero, to: scrollView).y
            let visibleTop = scrollView.contentOffset.y
            let visibleBottom = visibleTop + scrollView.bounds.height - scrollView.contentInset.bottom

            if caretInScroll.maxY > visibleBottom - 20 || caretInScroll.minY < visibleTop + 10 {
                let targetRect = caretInScroll.insetBy(dx: 0, dy: -30)
                let maxAllowedOffset = cardTopInScroll - 10
                let idealOffset = targetRect.minY - 60

                if idealOffset > maxAllowedOffset {
                    scrollView.setContentOffset(CGPoint(x: 0, y: maxAllowedOffset), animated: true)
                } else {
                    scrollView.scrollRectToVisible(targetRect, animated: true)
                }
            }
        } else {
            let targetRect = caretInScroll.insetBy(dx: 0, dy: -30)
            scrollView.scrollRectToVisible(targetRect, animated: true)
        }
    }

    @objc private func keyboardWillShow(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let keyboardFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval,
              let curveValue = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt
        else { return }

        let keyboardHeight = keyboardFrame.height
        let bottomInset = keyboardHeight - view.safeAreaInsets.bottom

        let options = UIView.AnimationOptions(rawValue: curveValue << 16)
        UIView.animate(withDuration: duration, delay: 0, options: options) {
            self.scrollView.contentInset.bottom = bottomInset
            self.scrollView.verticalScrollIndicatorInsets.bottom = bottomInset
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let activeTextView: UITextView?
            if self.inputTextView.isFirstResponder {
                activeTextView = self.inputTextView
            } else if self.contextTextView.isFirstResponder {
                activeTextView = self.contextTextView
            } else {
                activeTextView = nil
            }

            if let textView = activeTextView {
                self.scrollToCaretInTextView(textView)
            }
        }
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval,
              let curveValue = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt
        else { return }

        let options = UIView.AnimationOptions(rawValue: curveValue << 16)
        UIView.animate(withDuration: duration, delay: 0, options: options) {
            self.scrollView.contentInset.bottom = 0
            self.scrollView.verticalScrollIndicatorInsets.bottom = 0
        }
    }

    // MARK: - Input Section (top card)

    private func setupInputSection() {
        let card = UIView()
        card.backgroundColor = AppColors.card
        card.layer.cornerRadius = 20
        card.layer.borderWidth = 1
        card.layer.borderColor = AppColors.border.cgColor
        card.translatesAutoresizingMaskIntoConstraints = false

        // Header: label + char count
        let headerStack = UIStackView()
        headerStack.axis = .horizontal
        headerStack.alignment = .center
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        let inputLabel = UILabel()
        inputLabel.text = L("ai_writer.input_label")
        inputLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        inputLabel.textColor = AppColors.text

        charCountLabel.font = .systemFont(ofSize: 12, weight: .medium)
        charCountLabel.textColor = AppColors.textMuted

        headerStack.addArrangedSubview(inputLabel)
        headerStack.addArrangedSubview(UIView()) // spacer
        headerStack.addArrangedSubview(charCountLabel)

        // Text input
        inputTextView.backgroundColor = .clear
        inputTextView.font = .systemFont(ofSize: 15)
        inputTextView.textColor = AppColors.text
        inputTextView.tintColor = AppColors.tierAccent
        inputTextView.delegate = self
        inputTextView.isScrollEnabled = false
        inputTextView.textContainer.lineFragmentPadding = 0
        inputTextView.translatesAutoresizingMaskIntoConstraints = false

        // Reply toggle button (Fix 2: SF Symbol + new text)
        let chatIcon = UIImage(systemName: "bubble.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .medium))
        contextToggleButton.setImage(chatIcon, for: .normal)
        contextToggleButton.tintColor = AppColors.tierAccent
        contextToggleButton.setTitle(" " + L("ai_writer.reply_paste"), for: .normal)
        contextToggleButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        contextToggleButton.setTitleColor(AppColors.tierAccent, for: .normal)
        contextToggleButton.contentHorizontalAlignment = .leading
        contextToggleButton.addTarget(self, action: #selector(toggleContext), for: .touchUpInside)
        contextToggleButton.translatesAutoresizingMaskIntoConstraints = false

        // Reply context container
        setupContextContainer()

        // ★ 본문 전체 삭제 버튼 (우측 상단)
        let inputClearButton = UIButton(type: .system)
        inputClearButton.setImage(
            UIImage(systemName: "xmark.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)),
            for: .normal
        )
        inputClearButton.tintColor = AppColors.textMuted
        inputClearButton.alpha = 0
        inputClearButton.addTarget(self, action: #selector(clearInputText), for: .touchUpInside)
        inputClearButton.translatesAutoresizingMaskIntoConstraints = false
        self.inputClearButton = inputClearButton

        card.addSubview(headerStack)
        card.addSubview(inputTextView)
        card.addSubview(inputPlaceholderLabel)
        card.addSubview(inputClearButton)
        card.addSubview(contextToggleButton)
        card.addSubview(contextContainer)

        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 20),
            headerStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            headerStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),

            inputTextView.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 14),
            inputTextView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            inputTextView.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            inputTextView.heightAnchor.constraint(greaterThanOrEqualToConstant: 100),

            // Input placeholder overlay (Fix 1)
            inputPlaceholderLabel.topAnchor.constraint(equalTo: inputTextView.topAnchor, constant: 8),
            inputPlaceholderLabel.leadingAnchor.constraint(equalTo: inputTextView.leadingAnchor, constant: 5),
            inputPlaceholderLabel.trailingAnchor.constraint(equalTo: inputTextView.trailingAnchor, constant: -5),

            // Input clear button (v3 Fix 1)
            inputClearButton.topAnchor.constraint(equalTo: inputTextView.topAnchor, constant: 4),
            inputClearButton.trailingAnchor.constraint(equalTo: inputTextView.trailingAnchor, constant: 0),
            inputClearButton.widthAnchor.constraint(equalToConstant: 28),
            inputClearButton.heightAnchor.constraint(equalToConstant: 28),

            contextToggleButton.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),

            contextContainer.topAnchor.constraint(equalTo: contextToggleButton.bottomAnchor, constant: 12),
            contextContainer.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            contextContainer.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
        ])

        // ★ v7: contextToggle의 top을 프로퍼티로 관리 (템플릿 폼 카드 전환용)
        contextToggleToInputBottomConstraint = contextToggleButton.topAnchor.constraint(equalTo: inputTextView.bottomAnchor, constant: 4)
        contextToggleToInputBottomConstraint?.isActive = true

        // v6: 명시적 height constraint (초기에는 비활성)
        inputTextViewHeightConstraint = inputTextView.heightAnchor.constraint(equalToConstant: 300)
        inputTextViewHeightConstraint.isActive = false

        // Fix 3: Constraint toggle for expand/collapse
        toggleBottomConstraint = contextToggleButton.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        toggleBottomConstraint.isActive = true   // Initial: collapsed

        containerBottomConstraint = contextContainer.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -20)
        containerBottomConstraint.isActive = false  // Initial: inactive

        inputContainer = card
        contentStack.addArrangedSubview(card)
        updateCharacterCounter()
    }

    private func setupContextContainer() {
        contextContainer.subviews.forEach { $0.removeFromSuperview() }
        contextContainer.backgroundColor = AppColors.bg
        contextContainer.layer.cornerRadius = 10
        contextContainer.isHidden = true
        contextContainer.translatesAutoresizingMaskIntoConstraints = false

        let contextLabel = UILabel()
        contextLabel.text = L("ai_writer.reply_label")
        contextLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        contextLabel.textColor = AppColors.textMuted
        contextLabel.translatesAutoresizingMaskIntoConstraints = false

        contextTextView.backgroundColor = .clear
        contextTextView.font = .systemFont(ofSize: 13)
        contextTextView.textColor = AppColors.text
        contextTextView.tintColor = AppColors.tierAccent
        contextTextView.delegate = self
        contextTextView.isScrollEnabled = false
        contextTextView.textContainer.lineFragmentPadding = 0
        contextTextView.translatesAutoresizingMaskIntoConstraints = false

        // ★ 답장 전체 삭제 버튼 (우측 상단)
        let contextClearButton = UIButton(type: .system)
        contextClearButton.setImage(
            UIImage(systemName: "xmark.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)),
            for: .normal
        )
        contextClearButton.tintColor = AppColors.textMuted
        contextClearButton.alpha = 0
        contextClearButton.addTarget(self, action: #selector(clearContextText), for: .touchUpInside)
        contextClearButton.translatesAutoresizingMaskIntoConstraints = false
        self.contextClearButton = contextClearButton

        contextContainer.addSubview(contextLabel)
        contextContainer.addSubview(contextTextView)
        contextContainer.addSubview(contextPlaceholderLabel)
        contextContainer.addSubview(contextClearButton)

        NSLayoutConstraint.activate([
            contextLabel.topAnchor.constraint(equalTo: contextContainer.topAnchor, constant: 12),
            contextLabel.leadingAnchor.constraint(equalTo: contextContainer.leadingAnchor, constant: 14),

            contextTextView.topAnchor.constraint(equalTo: contextLabel.bottomAnchor, constant: 8),
            contextTextView.leadingAnchor.constraint(equalTo: contextContainer.leadingAnchor, constant: 14),
            contextTextView.trailingAnchor.constraint(equalTo: contextContainer.trailingAnchor, constant: -14),
            contextTextView.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
            contextTextView.bottomAnchor.constraint(equalTo: contextContainer.bottomAnchor, constant: -12),

            // Context placeholder overlay (Fix 4)
            contextPlaceholderLabel.topAnchor.constraint(equalTo: contextTextView.topAnchor, constant: 8),
            contextPlaceholderLabel.leadingAnchor.constraint(equalTo: contextTextView.leadingAnchor, constant: 5),
            contextPlaceholderLabel.trailingAnchor.constraint(equalTo: contextTextView.trailingAnchor, constant: -5),

            // Context clear button (v3 Fix 1)
            contextClearButton.topAnchor.constraint(equalTo: contextTextView.topAnchor, constant: 4),
            contextClearButton.trailingAnchor.constraint(equalTo: contextTextView.trailingAnchor, constant: 0),
            contextClearButton.widthAnchor.constraint(equalToConstant: 28),
            contextClearButton.heightAnchor.constraint(equalToConstant: 28),
        ])

        // v6: 명시적 height constraint (초기에는 비활성)
        contextTextViewHeightConstraint = contextTextView.heightAnchor.constraint(equalToConstant: 200)
        contextTextViewHeightConstraint.isActive = false
    }

    // MARK: - Template Section

    private func setupTemplateSection() {
        let titleLabel = UILabel()
        titleLabel.text = L("ai_writer.templates_title")
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = AppColors.textSub
        contentStack.addArrangedSubview(titleLabel)
        contentStack.setCustomSpacing(10, after: titleLabel)

        let templateScroll = UIScrollView()
        templateScroll.showsHorizontalScrollIndicator = false
        templateScroll.translatesAutoresizingMaskIntoConstraints = false

        let templateStack = UIStackView()
        templateStack.axis = .horizontal
        templateStack.spacing = 8
        templateStack.translatesAutoresizingMaskIntoConstraints = false

        templateScroll.addSubview(templateStack)
        NSLayoutConstraint.activate([
            templateStack.leadingAnchor.constraint(equalTo: templateScroll.contentLayoutGuide.leadingAnchor),
            templateStack.trailingAnchor.constraint(equalTo: templateScroll.contentLayoutGuide.trailingAnchor),
            templateStack.topAnchor.constraint(equalTo: templateScroll.contentLayoutGuide.topAnchor),
            templateStack.bottomAnchor.constraint(equalTo: templateScroll.contentLayoutGuide.bottomAnchor),
            templateStack.heightAnchor.constraint(equalTo: templateScroll.frameLayoutGuide.heightAnchor),
        ])

        for (i, template) in aiWriterTemplates.enumerated() {
            let btn = UIButton(type: .system)
            btn.setTitle("\(template.emoji) \(L(template.nameKey))", for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
            btn.setTitleColor(AppColors.text, for: .normal)
            btn.backgroundColor = AppColors.card
            btn.layer.cornerRadius = 18
            btn.contentEdgeInsets = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
            btn.layer.shadowColor = UIColor.black.cgColor
            btn.layer.shadowOpacity = 0.04
            btn.layer.shadowOffset = CGSize(width: 0, height: 1)
            btn.layer.shadowRadius = 3
            btn.tag = i
            btn.addTarget(self, action: #selector(templateTapped(_:)), for: .touchUpInside)
            templateStack.addArrangedSubview(btn)
        }

        contentStack.addArrangedSubview(templateScroll)
    }

    // MARK: - Options Card (grouped list-row style)

    private func setupOptionsCard() {
        let card = UIView()
        card.backgroundColor = AppColors.card
        card.layer.cornerRadius = 20
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = 0.04
        card.layer.shadowOffset = CGSize(width: 0, height: 1)
        card.layer.shadowRadius = 3
        card.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false

        let langRow = makeOptionRow(
            iconAssetName: "AIWriterOutputLanguageIcon",
            title: L("ai_writer.lang.section_title"),
            valueLabel: langValueLabel,
            defaultValue: L("ai_writer.lang.auto"),
            action: #selector(openLangSheet)
        )

        let toneRow = makeOptionRow(
            iconAssetName: "AIWriterToneIcon",
            title: L("ai_writer.tone_title"),
            valueLabel: toneValueLabel,
            defaultValue: "\u{1F4AC} " + L("tone.casual"),
            action: #selector(openToneSheet)
        )

        let lengthRow = makeOptionRow(
            iconAssetName: "AIWriterLengthIcon",
            title: L("ai_writer.length_title"),
            valueLabel: lengthValueLabel,
            defaultValue: L("ai_writer.length.medium"),
            action: #selector(openLengthSheet)
        )

        let divider1 = makeDivider()
        let divider2 = makeDivider()

        stack.addArrangedSubview(langRow)
        stack.addArrangedSubview(divider1)
        stack.addArrangedSubview(toneRow)
        stack.addArrangedSubview(divider2)
        stack.addArrangedSubview(lengthRow)

        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor),
        ])

        contentStack.addArrangedSubview(card)
    }

    private func makeAIWriterOptionIconBackgroundColor() -> UIColor {
        UIColor { traitCollection in
            if traitCollection.userInterfaceStyle == .dark {
                return UIColor(red: 44/255, green: 44/255, blue: 46/255, alpha: 1.0)
            } else {
                return UIColor(red: 242/255, green: 243/255, blue: 245/255, alpha: 1.0)
            }
        }
    }

    private func makeOptionRow(iconAssetName: String, title: String, valueLabel: UILabel, defaultValue: String, action: Selector) -> UIView {
        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: 60).isActive = true

        let tap = UITapGestureRecognizer(target: self, action: action)
        row.addGestureRecognizer(tap)

        let iconContainer = UIView()
        iconContainer.backgroundColor = makeAIWriterOptionIconBackgroundColor()
        iconContainer.layer.cornerRadius = 12
        iconContainer.translatesAutoresizingMaskIntoConstraints = false

        let iconImage = UIImageView()
        iconImage.image = UIImage(named: iconAssetName)?.withRenderingMode(.alwaysOriginal)
        iconImage.contentMode = .scaleAspectFit
        iconImage.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.addSubview(iconImage)

        NSLayoutConstraint.activate([
            iconContainer.widthAnchor.constraint(equalToConstant: 40),
            iconContainer.heightAnchor.constraint(equalToConstant: 40),
            iconImage.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconImage.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            iconImage.widthAnchor.constraint(equalToConstant: 24),
            iconImage.heightAnchor.constraint(equalToConstant: 24),
        ])

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        titleLabel.textColor = AppColors.text
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        valueLabel.text = defaultValue
        valueLabel.font = .systemFont(ofSize: 14, weight: .medium)
        valueLabel.textColor = AppColors.textSub
        valueLabel.translatesAutoresizingMaskIntoConstraints = false

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = AppColors.textMuted
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.setContentHuggingPriority(.required, for: .horizontal)

        row.addSubview(iconContainer)
        row.addSubview(titleLabel)
        row.addSubview(valueLabel)
        row.addSubview(chevron)

        NSLayoutConstraint.activate([
            iconContainer.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 20),
            iconContainer.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: 12),
            titleLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            chevron.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -20),
            chevron.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 12),

            valueLabel.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -6),
            valueLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])

        return row
    }

    private func makeDivider() -> UIView {
        let divider = UIView()
        divider.backgroundColor = AppColors.bg
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return divider
    }

    // MARK: - Bottom Bar (fixed CTA)

    private func setupBottomBar() {
        bottomBar.translatesAutoresizingMaskIntoConstraints = false

        let blurEffect = UIBlurEffect(style: .systemThinMaterial)
        let blurView = UIVisualEffectView(effect: blurEffect)
        blurView.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(blurView)

        generateButton.setTitle(L("ai_writer.generate"), for: .normal)
        generateButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        generateButton.backgroundColor = AppColors.tierAccent
        generateButton.setTitleColor(.white, for: .normal)
        generateButton.layer.cornerRadius = 16
        generateButton.translatesAutoresizingMaskIntoConstraints = false
        generateButton.addTarget(self, action: #selector(generateTapped), for: .touchUpInside)

        generateButton.addSubview(remainingBadge)
        NSLayoutConstraint.activate([
            remainingBadge.trailingAnchor.constraint(equalTo: generateButton.trailingAnchor, constant: -16),
            remainingBadge.centerYAnchor.constraint(equalTo: generateButton.centerYAnchor),
            remainingBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 22),
            remainingBadge.heightAnchor.constraint(equalToConstant: 22),
        ])
        remainingBadge.isHidden = true

        bottomBar.addSubview(generateButton)
        view.addSubview(bottomBar)

        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: bottomBar.topAnchor),
            blurView.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomBar.bottomAnchor),

            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            generateButton.topAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 12),
            generateButton.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 20),
            generateButton.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -20),
            generateButton.heightAnchor.constraint(equalToConstant: 54),
            generateButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
        ])
    }

    // MARK: - Result Area

    private func setupResultArea() {
        loadingIndicator.color = AppColors.tierAccent
        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(loadingIndicator)

        resultScrollView.isPagingEnabled = true
        resultScrollView.showsHorizontalScrollIndicator = false
        resultScrollView.isHidden = true
        resultScrollView.delegate = self
        resultScrollView.translatesAutoresizingMaskIntoConstraints = false

        pageControl.currentPageIndicatorTintColor = AppColors.tierAccent
        pageControl.pageIndicatorTintColor = AppColors.border
        pageControl.isHidden = true
        pageControl.translatesAutoresizingMaskIntoConstraints = false

        contentStack.addArrangedSubview(resultScrollView)
        contentStack.addArrangedSubview(pageControl)

        // ★ v8: 동적 높이 제약 (displayResults에서 갱신)
        resultScrollViewHeightConstraint = resultScrollView.heightAnchor.constraint(equalToConstant: 180)
        resultScrollViewHeightConstraint?.isActive = true
    }

    private func displayResults(_ messages: [String]) {
        resultCards.forEach { $0.removeFromSuperview() }
        resultCards.removeAll()
        resultLabels.removeAll()

        let cardWidth = view.bounds.width - 56

        for (i, msg) in messages.enumerated() {
            let card = UIView()
            card.backgroundColor = AppColors.card
            card.layer.cornerRadius = 20
            card.layer.shadowColor = UIColor.black.cgColor
            card.layer.shadowOpacity = 0.04
            card.layer.shadowOffset = CGSize(width: 0, height: 1)
            card.layer.shadowRadius = 3
            card.translatesAutoresizingMaskIntoConstraints = false

            // Left accent bar
            let accentBar = UIView()
            accentBar.backgroundColor = AppColors.tierAccent
            accentBar.layer.cornerRadius = 1.5
            accentBar.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(accentBar)

            // "AI-composed message" label
            let resultHeaderLabel = UILabel()
            resultHeaderLabel.text = L("ai_writer.result_label")
            resultHeaderLabel.font = .systemFont(ofSize: 11, weight: .semibold)
            resultHeaderLabel.textColor = AppColors.tierAccent
            resultHeaderLabel.translatesAutoresizingMaskIntoConstraints = false

            let label = UILabel()
            label.text = msg
            label.font = .systemFont(ofSize: 15)
            label.textColor = AppColors.text
            label.numberOfLines = 0
            label.translatesAutoresizingMaskIntoConstraints = false

            let copyBtn = UIButton(type: .system)
            copyBtn.setTitle(L("ai_writer.copy"), for: .normal)
            copyBtn.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
            copyBtn.setTitleColor(AppColors.tierAccent, for: .normal)
            copyBtn.backgroundColor = AppColors.tierAccent.withAlphaComponent(0.08)
            copyBtn.layer.cornerRadius = 16
            copyBtn.layer.borderWidth = 1.5
            copyBtn.layer.borderColor = AppColors.tierAccent.cgColor
            copyBtn.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
            copyBtn.tag = i
            copyBtn.addTarget(self, action: #selector(copyVariation(_:)), for: .touchUpInside)

            let regenerateBtn = UIButton(type: .system)
            regenerateBtn.setTitle(L("ai_writer.regenerate"), for: .normal)
            regenerateBtn.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
            regenerateBtn.setTitleColor(AppColors.textSub, for: .normal)
            regenerateBtn.backgroundColor = .clear
            regenerateBtn.layer.cornerRadius = 16
            regenerateBtn.layer.borderWidth = 1.5
            regenerateBtn.layer.borderColor = AppColors.border.cgColor
            regenerateBtn.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
            regenerateBtn.addTarget(self, action: #selector(regenerateTapped), for: .touchUpInside)

            let starBtn = UIButton(type: .system)
            starBtn.setImage(UIImage(systemName: "star"), for: .normal)
            starBtn.tintColor = AppColors.textMuted
            starBtn.tag = i
            starBtn.addTarget(self, action: #selector(favoriteVariation(_:)), for: .touchUpInside)

            let btnStack = UIStackView(arrangedSubviews: [copyBtn, regenerateBtn, starBtn])
            btnStack.axis = .horizontal
            btnStack.spacing = 8
            btnStack.translatesAutoresizingMaskIntoConstraints = false

            card.addSubview(resultHeaderLabel)
            card.addSubview(label)
            card.addSubview(btnStack)

            NSLayoutConstraint.activate([
                accentBar.leadingAnchor.constraint(equalTo: card.leadingAnchor),
                accentBar.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
                accentBar.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
                accentBar.widthAnchor.constraint(equalToConstant: 3),

                resultHeaderLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 20),
                resultHeaderLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),

                label.topAnchor.constraint(equalTo: resultHeaderLabel.bottomAnchor, constant: 10),
                label.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
                label.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),

                btnStack.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 16),
                btnStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
                btnStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -20),
            ])

            resultScrollView.addSubview(card)

            let xOffset = CGFloat(i) * (cardWidth + 8)
            NSLayoutConstraint.activate([
                card.leadingAnchor.constraint(equalTo: resultScrollView.leadingAnchor, constant: xOffset),
                card.topAnchor.constraint(equalTo: resultScrollView.topAnchor),
                card.widthAnchor.constraint(equalToConstant: cardWidth),
                card.bottomAnchor.constraint(equalTo: resultScrollView.bottomAnchor),
            ])

            resultCards.append(card)
            resultLabels.append(label)
        }

        // Slide-up animation
        resultScrollView.alpha = 0
        resultScrollView.transform = CGAffineTransform(translationX: 0, y: 16)
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0) {
            self.resultScrollView.alpha = 1
            self.resultScrollView.transform = .identity
        }

        pageControl.numberOfPages = messages.count
        pageControl.currentPage = 0
        pageControl.isHidden = messages.count <= 1
        resultScrollView.isHidden = false

        // ★ v8: 카드 intrinsic height 계산 후 scrollView 높이 동적 설정
        resultScrollView.layoutIfNeeded()
        var maxCardHeight: CGFloat = 180  // 최소 높이
        for card in resultCards {
            let cardHeight = card.systemLayoutSizeFitting(
                CGSize(width: cardWidth, height: UIView.layoutFittingCompressedSize.height),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            ).height
            maxCardHeight = max(maxCardHeight, cardHeight)
        }
        resultScrollViewHeightConstraint?.constant = maxCardHeight

        resultScrollView.contentSize = CGSize(
            width: CGFloat(messages.count) * (cardWidth + 8),
            height: maxCardHeight
        )
    }

    // MARK: - Bottom Sheet Infrastructure

    private func presentBottomSheet(content: UIView, height: CGFloat) {
        let overlay = UIView(frame: view.bounds)
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        overlay.alpha = 0
        let dismissTap = UITapGestureRecognizer(target: self, action: #selector(dismissSheet))
        overlay.addGestureRecognizer(dismissTap)
        view.addSubview(overlay)
        sheetOverlay = overlay

        let sheet = UIView()
        sheet.backgroundColor = AppColors.card
        sheet.layer.cornerRadius = 20
        sheet.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        sheet.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sheet)

        let handle = UIView()
        handle.backgroundColor = AppColors.border
        handle.layer.cornerRadius = 2
        handle.translatesAutoresizingMaskIntoConstraints = false
        sheet.addSubview(handle)

        sheet.addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            sheet.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sheet.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sheet.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sheet.heightAnchor.constraint(equalToConstant: height + view.safeAreaInsets.bottom),

            handle.topAnchor.constraint(equalTo: sheet.topAnchor, constant: 10),
            handle.centerXAnchor.constraint(equalTo: sheet.centerXAnchor),
            handle.widthAnchor.constraint(equalToConstant: 36),
            handle.heightAnchor.constraint(equalToConstant: 4),

            content.topAnchor.constraint(equalTo: handle.bottomAnchor, constant: 8),
            content.leadingAnchor.constraint(equalTo: sheet.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: sheet.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: sheet.safeAreaLayoutGuide.bottomAnchor),
        ])

        sheet.transform = CGAffineTransform(translationX: 0, y: height + view.safeAreaInsets.bottom)
        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0) {
            overlay.alpha = 1
            sheet.transform = .identity
        }

        switch content.tag {
        case 100: toneSheet = sheet
        case 200: lengthSheet = sheet
        case 300: langSheet = sheet
        default: break
        }
    }

    @objc private func dismissSheet() {
        guard let overlay = sheetOverlay else { return }
        let sheets = [toneSheet, lengthSheet, langSheet].compactMap { $0 }

        UIView.animate(withDuration: 0.25, animations: {
            overlay.alpha = 0
            sheets.forEach { $0.transform = CGAffineTransform(translationX: 0, y: 400) }
        }) { _ in
            overlay.removeFromSuperview()
            sheets.forEach { $0.removeFromSuperview() }
            self.sheetOverlay = nil
            self.toneSheet = nil
            self.lengthSheet = nil
            self.langSheet = nil
        }
    }

    // MARK: - Tone Bottom Sheet (3x4 grid)

    @objc private func openToneSheet() {
        view.endEditing(true)  // ★ v8: 키보드 해제
        let content = UIView()
        content.tag = 100

        let title = UILabel()
        title.text = L("ai_writer.tone_select_title")
        title.font = .systemFont(ofSize: 17, weight: .bold)
        title.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(title)

        let grid = UIStackView()
        grid.axis = .vertical
        grid.spacing = 8
        grid.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(grid)

        let chunkedTones = stride(from: 0, to: toneItems.count, by: 3).map {
            Array(toneItems[$0..<min($0 + 3, toneItems.count)])
        }

        for row in chunkedTones {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.spacing = 8
            rowStack.distribution = .fillEqually

            for item in row {
                let btn = UIButton(type: .system)
                let isSelected = item.id == selectedTone
                btn.setTitle("\(item.emoji)\n\(L(item.nameKey))", for: .normal)
                btn.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
                btn.titleLabel?.numberOfLines = 2
                btn.titleLabel?.textAlignment = .center
                btn.setTitleColor(isSelected ? AppColors.tierAccent : AppColors.textSub, for: .normal)
                btn.backgroundColor = isSelected
                    ? AppColors.tierAccent.withAlphaComponent(0.08)
                    : AppColors.bg
                btn.layer.cornerRadius = 16
                btn.layer.borderWidth = 1.5
                btn.layer.borderColor = isSelected
                    ? AppColors.tierAccent.cgColor
                    : AppColors.bg.cgColor
                btn.heightAnchor.constraint(equalToConstant: 72).isActive = true
                btn.accessibilityIdentifier = item.id
                btn.addTarget(self, action: #selector(toneSheetSelected(_:)), for: .touchUpInside)
                rowStack.addArrangedSubview(btn)
            }

            let remainder = 3 - row.count
            for _ in 0..<remainder {
                let spacer = UIView()
                rowStack.addArrangedSubview(spacer)
            }

            grid.addArrangedSubview(rowStack)
        }

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            title.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            title.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),

            grid.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 12),
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            grid.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -24),
        ])

        presentBottomSheet(content: content, height: 380)
    }

    @objc private func toneSheetSelected(_ sender: UIButton) {
        guard let toneId = sender.accessibilityIdentifier else { return }
        selectedTone = toneId

        if let item = toneItems.first(where: { $0.id == toneId }) {
            toneValueLabel.text = "\(item.emoji) \(L(item.nameKey))"
        }

        // ★ 선택 피드백: 모든 버튼 리셋 후 선택 항목 하이라이트
        if let grid = sender.superview?.superview { // rowStack → grid
            for case let rowStack as UIStackView in grid.subviews {
                for case let btn as UIButton in rowStack.arrangedSubviews {
                    UIView.animate(withDuration: 0.2) {
                        btn.backgroundColor = (btn === sender)
                            ? AppColors.tierAccent.withAlphaComponent(0.08)
                            : AppColors.bg
                        btn.layer.borderColor = (btn === sender)
                            ? AppColors.tierAccent.cgColor
                            : AppColors.bg.cgColor
                        btn.setTitleColor((btn === sender) ? AppColors.tierAccent : AppColors.textSub, for: .normal)
                    }
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            self.dismissSheet()
        }
    }

    // MARK: - Length Bottom Sheet

    @objc private func openLengthSheet() {
        view.endEditing(true)  // ★ v8: 키보드 해제
        let content = UIView()
        content.tag = 200

        let title = UILabel()
        title.text = L("ai_writer.length_select_title")
        title.font = .systemFont(ofSize: 17, weight: .bold)
        title.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(title)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        let lengthOptions: [(id: String, icon: String, name: String, desc: String)] = [
            ("short", "\u{1F4AC}", L("ai_writer.length.short"), L("ai_writer.length.short_desc")),
            ("medium", "\u{1F4DD}", L("ai_writer.length.medium"), L("ai_writer.length.medium_desc")),
            ("long", "\u{1F4C4}", L("ai_writer.length.long"), L("ai_writer.length.long_desc")),
        ]

        for opt in lengthOptions {
            let row = makeLengthSheetRow(
                id: opt.id,
                icon: opt.icon,
                name: opt.name,
                desc: opt.desc,
                isSelected: opt.id == selectedLength
            )
            stack.addArrangedSubview(row)
        }

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            title.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            title.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),

            stack.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -24),
        ])

        presentBottomSheet(content: content, height: 300)
    }

    private func makeLengthSheetRow(id: String, icon: String, name: String, desc: String, isSelected: Bool) -> UIView {
        let row = UIView()
        row.backgroundColor = isSelected ? AppColors.tierAccent.withAlphaComponent(0.08) : AppColors.bg
        row.layer.cornerRadius = 16
        row.layer.borderWidth = 1.5
        row.layer.borderColor = isSelected ? AppColors.tierAccent.cgColor : AppColors.bg.cgColor
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: 64).isActive = true
        row.accessibilityIdentifier = id

        let tap = UITapGestureRecognizer(target: self, action: #selector(lengthSheetSelected(_:)))
        row.addGestureRecognizer(tap)

        let iconLabel = UILabel()
        iconLabel.text = icon
        iconLabel.font = .systemFont(ofSize: 20)
        iconLabel.translatesAutoresizingMaskIntoConstraints = false

        let nameLabel = UILabel()
        nameLabel.text = name
        nameLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        nameLabel.textColor = isSelected ? AppColors.tierAccent : AppColors.text
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        let descLabel = UILabel()
        descLabel.text = desc
        descLabel.font = .systemFont(ofSize: 12)
        descLabel.textColor = AppColors.textSub
        descLabel.translatesAutoresizingMaskIntoConstraints = false

        let checkView = UIView()
        checkView.layer.cornerRadius = 11
        checkView.layer.borderWidth = 2
        checkView.layer.borderColor = isSelected ? AppColors.tierAccent.cgColor : AppColors.border.cgColor
        checkView.backgroundColor = isSelected ? AppColors.tierAccent : .clear
        checkView.translatesAutoresizingMaskIntoConstraints = false

        if isSelected {
            let checkmark = UIImageView(image: UIImage(systemName: "checkmark"))
            checkmark.tintColor = .white
            checkmark.translatesAutoresizingMaskIntoConstraints = false
            checkView.addSubview(checkmark)
            NSLayoutConstraint.activate([
                checkmark.centerXAnchor.constraint(equalTo: checkView.centerXAnchor),
                checkmark.centerYAnchor.constraint(equalTo: checkView.centerYAnchor),
                checkmark.widthAnchor.constraint(equalToConstant: 10),
                checkmark.heightAnchor.constraint(equalToConstant: 10),
            ])
        }

        row.addSubview(iconLabel)
        row.addSubview(nameLabel)
        row.addSubview(descLabel)
        row.addSubview(checkView)

        NSLayoutConstraint.activate([
            iconLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            iconLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            nameLabel.leadingAnchor.constraint(equalTo: iconLabel.trailingAnchor, constant: 14),
            nameLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 14),

            descLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            descLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),

            checkView.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            checkView.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            checkView.widthAnchor.constraint(equalToConstant: 22),
            checkView.heightAnchor.constraint(equalToConstant: 22),
        ])

        return row
    }

    @objc private func lengthSheetSelected(_ sender: UITapGestureRecognizer) {
        guard let selectedRow = sender.view,
              let id = selectedRow.accessibilityIdentifier else { return }
        selectedLength = id

        let lengths = ["short": L("ai_writer.length.short"),
                       "medium": L("ai_writer.length.medium"),
                       "long": L("ai_writer.length.long")]
        lengthValueLabel.text = lengths[id] ?? id

        // ★ 선택 피드백: 모든 행 리셋 후 선택 항목 하이라이트
        if let stack = selectedRow.superview as? UIStackView {
            for row in stack.arrangedSubviews {
                let isSelected = (row === selectedRow)
                UIView.animate(withDuration: 0.2) {
                    row.backgroundColor = isSelected
                        ? AppColors.tierAccent.withAlphaComponent(0.08)
                        : AppColors.bg
                    row.layer.borderColor = isSelected
                        ? AppColors.tierAccent.cgColor
                        : AppColors.bg.cgColor
                }
                // 체크마크 업데이트
                if let checkView = row.subviews.last {
                    UIView.animate(withDuration: 0.2) {
                        checkView.backgroundColor = isSelected ? AppColors.tierAccent : .clear
                        checkView.layer.borderColor = isSelected ? AppColors.tierAccent.cgColor : AppColors.border.cgColor
                    }
                    if isSelected && checkView.subviews.isEmpty {
                        let checkmark = UIImageView(image: UIImage(systemName: "checkmark"))
                        checkmark.tintColor = .white
                        checkmark.translatesAutoresizingMaskIntoConstraints = false
                        checkView.addSubview(checkmark)
                        NSLayoutConstraint.activate([
                            checkmark.centerXAnchor.constraint(equalTo: checkView.centerXAnchor),
                            checkmark.centerYAnchor.constraint(equalTo: checkView.centerYAnchor),
                            checkmark.widthAnchor.constraint(equalToConstant: 10),
                            checkmark.heightAnchor.constraint(equalToConstant: 10),
                        ])
                    } else if !isSelected {
                        checkView.subviews.forEach { $0.removeFromSuperview() }
                    }
                }
                // 이름 라벨 색상 업데이트
                if let nameLabel = row.subviews.first(where: { ($0 as? UILabel)?.font.pointSize == 15 }) as? UILabel {
                    nameLabel.textColor = isSelected ? AppColors.tierAccent : AppColors.text
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            self.dismissSheet()
        }
    }

    // MARK: - Language Bottom Sheet

    @objc private func openLangSheet() {
        view.endEditing(true)  // ★ v8: 키보드 해제
        let selectionViewController = UIViewController()
        selectionViewController.view.backgroundColor = AppColors.bg
        selectionViewController.title = L("ai_writer.lang.select_title")

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = AppColors.bg
        appearance.titleTextAttributes = [.foregroundColor: AppColors.text]
        appearance.largeTitleTextAttributes = [.foregroundColor: AppColors.text]

        let navigationController = UINavigationController(rootViewController: selectionViewController)
        navigationController.modalPresentationStyle = .fullScreen
        navigationController.navigationBar.prefersLargeTitles = false
        navigationController.navigationBar.tintColor = AppColors.tierAccent
        navigationController.navigationBar.standardAppearance = appearance
        navigationController.navigationBar.scrollEdgeAppearance = appearance

        selectionViewController.navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: L("common.cancel"),
            primaryAction: UIAction { [weak navigationController] _ in
                navigationController?.dismiss(animated: true)
            }
        )

        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        selectionViewController.view.addSubview(scrollView)

        let content = UIView()
        content.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(content)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        for lang in outputLanguages {
            let isSelected = lang.code == outputLanguage
            let displayName = localizedOutputLanguageDisplayName(for: lang.code)
            let row = UIControl()
            row.backgroundColor = AppColors.card
            row.layer.cornerRadius = 18
            row.layer.borderWidth = 1
            row.layer.borderColor = isSelected ? AppColors.tierAccent.cgColor : AppColors.border.cgColor
            row.translatesAutoresizingMaskIntoConstraints = false
            row.heightAnchor.constraint(equalToConstant: 60).isActive = true

            let rowAction = UIAction { [weak self, weak navigationController] _ in
                self?.applySelectedOutputLanguage(lang.code)
                navigationController?.dismiss(animated: true)
            }
            row.addAction(rowAction, for: .touchUpInside)

            let flagLabel = UILabel()
            flagLabel.text = lang.flag
            flagLabel.font = .systemFont(ofSize: 22)
            flagLabel.translatesAutoresizingMaskIntoConstraints = false

            let nameLabel = UILabel()
            nameLabel.text = displayName
            nameLabel.font = .systemFont(ofSize: 16, weight: isSelected ? .semibold : .medium)
            nameLabel.textColor = isSelected ? AppColors.tierAccent : AppColors.text
            nameLabel.translatesAutoresizingMaskIntoConstraints = false

            let checkImage = UIImageView(image: UIImage(systemName: "checkmark"))
            checkImage.tintColor = AppColors.tierAccent
            checkImage.isHidden = !isSelected
            checkImage.translatesAutoresizingMaskIntoConstraints = false

            row.addSubview(flagLabel)
            row.addSubview(nameLabel)
            row.addSubview(checkImage)

            NSLayoutConstraint.activate([
                flagLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 20),
                flagLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),

                nameLabel.leadingAnchor.constraint(equalTo: flagLabel.trailingAnchor, constant: 14),
                nameLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: checkImage.leadingAnchor, constant: -12),

                checkImage.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -20),
                checkImage.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                checkImage.widthAnchor.constraint(equalToConstant: 18),
                checkImage.heightAnchor.constraint(equalToConstant: 18),
            ])

            stack.addArrangedSubview(row)
        }

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: selectionViewController.view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: selectionViewController.view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: selectionViewController.view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: selectionViewController.view.bottomAnchor),

            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            content.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            content.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -32),
        ])

        present(navigationController, animated: true)
    }

    @objc private func langSheetSelected(_ sender: UITapGestureRecognizer) {
        guard let selectedRow = sender.view,
              let code = selectedRow.accessibilityIdentifier else { return }
        applySelectedOutputLanguage(code)

        // ★ 선택 피드백: 모든 행 리셋 후 선택 항목 하이라이트
        if let stack = selectedRow.superview as? UIStackView {
            for row in stack.arrangedSubviews {
                let isSelected = (row === selectedRow)

                UIView.animate(withDuration: 0.2) {
                    row.backgroundColor = isSelected
                        ? AppColors.tierAccent.withAlphaComponent(0.06)
                        : .clear
                }

                row.subviews
                    .filter { $0 is UIImageView && ($0 as? UIImageView)?.image == UIImage(systemName: "checkmark") }
                    .forEach { $0.removeFromSuperview() }

                if isSelected {
                    let check = UIImageView(image: UIImage(systemName: "checkmark"))
                    check.tintColor = AppColors.tierAccent
                    check.translatesAutoresizingMaskIntoConstraints = false
                    row.addSubview(check)
                    NSLayoutConstraint.activate([
                        check.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -20),
                        check.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                        check.widthAnchor.constraint(equalToConstant: 16),
                    ])
                }

                if let nameLabel = row.subviews.compactMap({ $0 as? UILabel }).first(where: { $0.font.pointSize == 15 }) {
                    nameLabel.font = .systemFont(ofSize: 15, weight: isSelected ? .semibold : .medium)
                    nameLabel.textColor = isSelected ? AppColors.tierAccent : AppColors.text
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            self.dismiss(animated: true)
        }
    }

    // MARK: - Clear Text Actions

    @objc private func clearInputText() {
        inputTextView.text = ""
        inputPlaceholderLabel.isHidden = false
        updateCharacterCounter()
        updateGenerateButtonState()
        updateClearButtonVisibility()
        // v6: 높이 리셋
        inputTextView.isScrollEnabled = false
        inputTextViewHeightConstraint.isActive = false
    }

    @objc private func clearContextText() {
        contextTextView.text = ""
        contextPlaceholderLabel.isHidden = false
        updateClearButtonVisibility()
        // v6: 높이 리셋
        contextTextView.isScrollEnabled = false
        contextTextViewHeightConstraint.isActive = false
    }

    private func updateClearButtonVisibility() {
        let inputHasText = !(inputTextView.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let contextHasText = !(contextTextView.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

        UIView.animate(withDuration: 0.15) {
            self.inputClearButton?.alpha = inputHasText ? 1.0 : 0
            self.contextClearButton?.alpha = contextHasText ? 1.0 : 0
        }
    }

    // MARK: - Template Form Card

    private func buildTemplateFormCard(for template: AIWriterTemplate) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        // ── 헤더: 이모지 + 템플릿 이름 ──
        let headerLabel = UILabel()
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        headerLabel.text = "\(template.emoji) \(L(template.nameKey))"
        headerLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        headerLabel.textColor = AppColors.text
        container.addSubview(headerLabel)

        // ── 구분선 ──
        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = AppColors.border
        container.addSubview(separator)

        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            headerLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            headerLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            separator.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 12),
            separator.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),
        ])

        // ── 필드들 ──
        templateFieldTextFields.removeAll()
        var previousAnchor = separator.bottomAnchor

        for (index, field) in template.fields.enumerated() {
            let label = UILabel()
            label.translatesAutoresizingMaskIntoConstraints = false
            let labelText = L(field.labelKey)
            if !field.required {
                label.text = "\(labelText) \(L("template.form.optional"))"
            } else {
                label.text = labelText
            }
            label.font = .systemFont(ofSize: 13, weight: .medium)
            label.textColor = AppColors.textSub
            container.addSubview(label)

            let textField = UITextField()
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.font = .systemFont(ofSize: 15)
            textField.textColor = AppColors.text
            textField.tintColor = AppColors.tierAccent
            textField.backgroundColor = AppColors.bg
            textField.layer.cornerRadius = 10
            textField.layer.borderWidth = 1
            textField.layer.borderColor = AppColors.border.cgColor
            textField.tag = index
            textField.delegate = self
            textField.returnKeyType = (index < template.fields.count - 1) ? .next : .done
            textField.addTarget(self, action: #selector(templateFieldChanged), for: .editingChanged)

            let leftPadding = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 44))
            textField.leftView = leftPadding
            textField.leftViewMode = .always
            let rightPadding = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 44))
            textField.rightView = rightPadding
            textField.rightViewMode = .always

            textField.attributedPlaceholder = NSAttributedString(
                string: labelText,
                attributes: [.foregroundColor: AppColors.textMuted]
            )

            container.addSubview(textField)
            templateFieldTextFields.append(textField)

            NSLayoutConstraint.activate([
                label.topAnchor.constraint(equalTo: previousAnchor, constant: 16),
                label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                label.trailingAnchor.constraint(equalTo: container.trailingAnchor),

                textField.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 6),
                textField.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                textField.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                textField.heightAnchor.constraint(equalToConstant: 44),
            ])

            previousAnchor = textField.bottomAnchor
        }

        // ── 템플릿 해제 버튼 ──
        let clearButton = UIButton(type: .system)
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.setTitle("\u{2715} \(L("template.form.clear_template"))", for: .normal)
        clearButton.setTitleColor(AppColors.textMuted, for: .normal)
        clearButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        clearButton.addTarget(self, action: #selector(clearTemplateTapped), for: .touchUpInside)
        container.addSubview(clearButton)

        NSLayoutConstraint.activate([
            clearButton.topAnchor.constraint(equalTo: previousAnchor, constant: 16),
            clearButton.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            clearButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
        ])

        return container
    }

    @objc private func clearTemplateTapped() {
        activeTemplate = nil

        // 1) 폼 카드 제거
        templateFormContainer?.removeFromSuperview()
        templateFormContainer = nil
        templateFieldTextFields.removeAll()

        // 2) ★ v7: contextToggle의 top 제약을 inputTextView.bottom으로 복원
        contextToggleToFormCardBottomConstraint?.isActive = false
        contextToggleToFormCardBottomConstraint = nil
        contextToggleToInputBottomConstraint?.isActive = true

        // 3) 자유입력 UI 복원
        inputTextView.isHidden = false
        inputTextView.text = ""
        inputPlaceholderLabel.isHidden = false

        // 4) 레이아웃 갱신
        view.layoutIfNeeded()

        updateGenerateButtonState()
        updateCharacterCounter()
        updateClearButtonVisibility()
    }

    @objc private func templateFieldChanged() {
        updateGenerateButtonState()
        updateCharacterCounter()
    }

    private func assembleTemplatePrompt(template: AIWriterTemplate) -> String {
        var prompt = L(template.promptKey)

        for (index, _) in template.fields.enumerated() {
            let value = templateFieldTextFields[safe: index]?.text ?? ""
            if !value.isEmpty {
                if let range = prompt.range(of: "\\[.*?\\]", options: .regularExpression) {
                    prompt = prompt.replacingCharacters(in: range, with: value)
                }
            }
        }

        return prompt
    }

    // MARK: - Context Actions

    @objc private func toggleContext() {
        isContextExpanded.toggle()

        if isContextExpanded {
            toggleBottomConstraint.isActive = false
            containerBottomConstraint.isActive = true
        } else {
            containerBottomConstraint.isActive = false
            toggleBottomConstraint.isActive = true
        }

        UIView.animate(withDuration: 0.25) {
            self.contextContainer.isHidden = !self.isContextExpanded

            if self.isContextExpanded {
                let closeIcon = UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .medium))
                self.contextToggleButton.setImage(closeIcon, for: .normal)
                self.contextToggleButton.setTitle(" " + L("ai_writer.reply_close"), for: .normal)
            } else {
                let chatIcon = UIImage(systemName: "bubble.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .medium))
                self.contextToggleButton.setImage(chatIcon, for: .normal)
                self.contextToggleButton.setTitle(" " + L("ai_writer.reply_paste"), for: .normal)
            }

            self.view.layoutIfNeeded()
        }
    }

    // MARK: - Template Action

    @objc private func templateTapped(_ sender: UIButton) {
        let template = aiWriterTemplates[sender.tag]
        activeTemplate = template

        // 1) 기존 자유입력 UI 숨기기
        inputTextView.isHidden = true
        inputPlaceholderLabel.isHidden = true
        inputClearButton?.alpha = 0

        // 2) 기존 폼 카드 제거 및 제약 정리
        //    (Template A → Template B 직접 전환 시에도 안전)
        if templateFormContainer != nil {
            templateFormContainer?.removeFromSuperview()
            templateFormContainer = nil
            contextToggleToFormCardBottomConstraint?.isActive = false
            contextToggleToFormCardBottomConstraint = nil
            // ★ inputBottom 복원을 건너뜀 — 바로 아래에서 새 formCard 제약으로 전환하므로 불필요
        }

        // 3) 새 폼 카드 생성
        let formCard = buildTemplateFormCard(for: template)
        templateFormContainer = formCard

        // 4) inputTextView의 부모 컨테이너(card)에 추가
        if let parentView = inputTextView.superview {
            parentView.addSubview(formCard)

            // formCard 위치: inputTextView와 같은 top/leading/trailing
            NSLayoutConstraint.activate([
                formCard.topAnchor.constraint(equalTo: inputTextView.topAnchor),
                formCard.leadingAnchor.constraint(equalTo: inputTextView.leadingAnchor),
                formCard.trailingAnchor.constraint(equalTo: inputTextView.trailingAnchor),
            ])

            // ★ v7 핵심: contextToggle의 top을 formCard.bottom으로 전환
            //   순서 중요: 반드시 기존 제약 비활성화 → 새 제약 활성화
            contextToggleToInputBottomConstraint?.isActive = false
            contextToggleToFormCardBottomConstraint = contextToggleButton.topAnchor.constraint(equalTo: formCard.bottomAnchor, constant: 4)
            contextToggleToFormCardBottomConstraint?.isActive = true
        }

        // 5) 톤 자동 설정
        if let toneIndex = toneItems.firstIndex(where: { $0.id == template.suggestedTone }) {
            selectedTone = template.suggestedTone
            if let item = toneItems[safe: toneIndex] {
                toneValueLabel.text = "\(item.emoji) \(L(item.nameKey))"
            }
        }

        // 6) 레이아웃 갱신 후 첫 번째 필드에 포커스
        view.layoutIfNeeded()
        templateFieldTextFields.first?.becomeFirstResponder()

        // 7) 버튼 상태 갱신
        updateGenerateButtonState()
        updateCharacterCounter()
    }

    // MARK: - Generate Actions

    private func updateGenerateButtonState() {
        let hasText: Bool

        if let template = activeTemplate {
            hasText = template.fields.enumerated().contains { index, field in
                guard field.required else { return false }
                let text = templateFieldTextFields[safe: index]?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return !text.isEmpty
            }
        } else {
            hasText = !(inputTextView.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }

        generateButton.alpha = hasText ? 1.0 : 0.4
        generateButton.isEnabled = hasText
    }

    private func updateGenerateButton() {
        let tier = SubscriptionStatus.shared.currentTier

        if tier == .free {
            let remaining = DailyUsageManager.shared.remainingComposes
            if remaining > 0 {
                showGenerateState(remaining: remaining)
            } else {
                showWatchAdState()
            }
        } else {
            showGenerateState(remaining: nil)
        }
    }

    private func showGenerateState(remaining: Int?) {
        generateButton.removeTarget(self, action: #selector(watchAdTapped), for: .touchUpInside)
        generateButton.addTarget(self, action: #selector(generateTapped), for: .touchUpInside)
        generateButton.setTitle(L("ai_writer.generate"), for: .normal)
        generateButton.backgroundColor = AppColors.tierAccent

        if let remaining = remaining {
            remainingBadge.isHidden = false
            remainingBadge.text = "\(remaining)"
        } else {
            remainingBadge.isHidden = true
        }
        updateGenerateButtonState()
    }

    private func showWatchAdState() {
        generateButton.removeTarget(self, action: #selector(generateTapped), for: .touchUpInside)
        generateButton.addTarget(self, action: #selector(watchAdTapped), for: .touchUpInside)
        generateButton.setTitle(L("ai_writer.watch_ad_to_write"), for: .normal)
        generateButton.backgroundColor = UIColor.systemOrange
        remainingBadge.isHidden = true
        updateGenerateButtonState()
    }

    @objc private func generateTapped() {
        let promptText: String

        if let template = activeTemplate {
            promptText = assembleTemplatePrompt(template: template)
        } else {
            promptText = inputTextView.text ?? ""
        }

        let prompt = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        lastPrompt = prompt
        requestCompose(prompt: prompt)
    }

    @objc private func watchAdTapped() {
        let rewardVC = RewardedAdsViewController(mode: .compose)
        rewardVC.modalPresentationStyle = .pageSheet
        if let sheet = rewardVC.sheetPresentationController {
            sheet.detents = [.medium()]
        }
        rewardVC.onDismiss = { [weak self] in
            self?.updateGenerateButton()
        }
        present(rewardVC, animated: true)
    }

    @objc private func regenerateTapped() {
        guard !lastPrompt.isEmpty else { return }
        requestCompose(prompt: lastPrompt)
    }

    // MARK: - Result Actions

    @objc private func copyVariation(_ sender: UIButton) {
        guard let label = resultLabels[safe: sender.tag] else { return }
        UIPasteboard.general.string = label.text
        sender.setTitle(L("ai_writer.copied"), for: .normal)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak sender] in
            sender?.setTitle(L("ai_writer.copy"), for: .normal)
        }
    }

    @objc private func favoriteVariation(_ sender: UIButton) {
        let isFilled = sender.currentImage == UIImage(systemName: "star.fill")
        sender.setImage(UIImage(systemName: isFilled ? "star" : "star.fill"), for: .normal)
        sender.tintColor = isFilled ? AppColors.textMuted : .systemYellow

        guard let itemId = lastSavedItemId else {
            sender.setImage(UIImage(systemName: isFilled ? "star.fill" : "star"), for: .normal)
            sender.tintColor = isFilled ? .systemYellow : AppColors.textMuted
            return
        }
        ComposeHistoryManager.shared.toggleFavorite(id: itemId)
    }

    // MARK: - Character Counter

    private func updateCharacterCounter() {
        let currentLength: Int
        if let template = activeTemplate {
            let assembled = assembleTemplatePrompt(template: template)
            currentLength = assembled.count
        } else {
            currentLength = inputTextView.text?.count ?? 0
        }

        let max = AppConstants.Limits.maxCharacters
        charCountLabel.text = "\(currentLength)/\(max)"
        if currentLength >= max {
            charCountLabel.textColor = .systemRed
        } else if currentLength >= max - 100 {
            charCountLabel.textColor = .systemOrange
        } else {
            charCountLabel.textColor = AppColors.textMuted
        }
    }

    // MARK: - Clipboard

    private func checkClipboardForReply() {
        guard !isContextExpanded,
              (contextTextView.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        showClipboardSuggestionBanner()
    }

    private func showClipboardSuggestionBanner() {
        guard UIPasteboard.general.hasStrings else { return }
        clipboardBanner.isHidden = false

        if !contentStack.arrangedSubviews.contains(clipboardBanner) {
            contentStack.insertArrangedSubview(clipboardBanner, at: 0)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.dismissClipboard()
        }
    }

    @objc private func acceptClipboard() {
        if let text = UIPasteboard.general.string,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            isContextExpanded = true
            contextContainer.isHidden = false

            toggleBottomConstraint.isActive = false
            containerBottomConstraint.isActive = true

            contextTextView.text = String(text.prefix(1000))
            contextPlaceholderLabel.isHidden = true

            let closeIcon = UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .medium))
            contextToggleButton.setImage(closeIcon, for: .normal)
            contextToggleButton.setTitle(" " + L("ai_writer.reply_close"), for: .normal)
        }
        dismissClipboard()
        updateClearButtonVisibility()
    }

    @objc private func dismissClipboard() {
        UIView.animate(withDuration: 0.2) {
            self.clipboardBanner.isHidden = true
        }
    }

    // MARK: - History

    @objc private func showHistory() {
        let historyVC = ComposeHistoryViewController()
        historyVC.onSelectItem = { [weak self] item in
            self?.inputTextView.text = item.prompt
            self?.selectedTone = item.tone
            self?.selectedLength = item.length
            if let toneItem = toneItems.first(where: { $0.id == item.tone }) {
                self?.toneValueLabel.text = "\(toneItem.emoji) \(L(toneItem.nameKey))"
            }
            let lengths = ["short": L("ai_writer.length.short"),
                           "medium": L("ai_writer.length.medium"),
                           "long": L("ai_writer.length.long")]
            self?.lengthValueLabel.text = lengths[item.length] ?? item.length
            self?.updateGenerateButtonState()
            self?.updateCharacterCounter()
        }
        navigationController?.pushViewController(historyVC, animated: true)
    }

    private func saveToHistory(prompt: String, result: String, body: [String: Any]) {
        let item = ComposeHistoryItem(
            prompt: prompt,
            replyContext: body["replyContext"] as? String,
            tone: selectedTone,
            length: selectedLength,
            result: result
        )
        ComposeHistoryManager.shared.addItem(item)
        lastSavedItemId = item.id
    }

    // MARK: - API

    private func requestCompose(prompt: String) {
        // [v3-C4] Guard against empty/whitespace-only prompts
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return }

        guard DailyUsageManager.shared.canUseCompose() else {
            showComposeLimitReachedAlert()
            return
        }

        // [v3-C1] Prevent double-tap submission
        generateButton.isEnabled = false
        generateButton.alpha = 0.5

        // [v3-C5] Capture current selections before async work
        let capturedTone = selectedTone
        let capturedLength = selectedLength
        let capturedOutputLanguage = outputLanguage

        let tier = SubscriptionStatus.shared.currentTier
        let resultCount = (tier == .free) ? 1 : 3

        resultScrollView.isHidden = false
        pageControl.isHidden = true
        loadingIndicator.startAnimating()

        let langCode: String
        if capturedOutputLanguage == "auto" {
            langCode = LocalizationManager.shared.currentLanguage.translationLanguageCode
        } else {
            langCode = capturedOutputLanguage
        }

        var body: [String: Any] = [
            "prompt": trimmedPrompt,
            "tone": capturedTone,
            "language": langCode,
            "length": capturedLength,
            "count": resultCount,
        ]

        if isContextExpanded,
           let context = contextTextView.text?.trimmingCharacters(in: .whitespacesAndNewlines),
           !context.isEmpty {
            body["replyContext"] = String(context.prefix(1000))
        }

        guard let url = URL(string: AppConstants.API.baseURL + "/api/compose"),
              let jsonData = try? JSONSerialization.data(withJSONObject: body) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = AppConstants.API.timeout

        lastPrompt = prompt

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            DispatchQueue.main.async {
                self?.loadingIndicator.stopAnimating()
                // [v3-C1] Re-enable generate button
                self?.generateButton.isEnabled = true
                self?.generateButton.alpha = 1.0

                guard let data = data, error == nil,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else {
                    self?.displayResults([L("ai_writer.error_generate")])
                    return
                }

                if let messages = json["messages"] as? [String], !messages.isEmpty {
                    self?.saveToHistory(prompt: prompt, result: messages[0], body: body)
                    self?.displayResults(messages)
                } else if let message = json["message"] as? String {
                    self?.saveToHistory(prompt: prompt, result: message, body: body)
                    self?.displayResults([message])
                } else {
                    self?.displayResults([L("ai_writer.error_generate")])
                    return
                }

                DailyUsageManager.shared.recordCompose()
                self?.updateGenerateButton()
            }
        }.resume()
    }

    // MARK: - Alerts

    private func showComposeLimitReachedAlert() {
        let tier = SubscriptionStatus.shared.currentTier

        if tier == .free {
            let alert = UIAlertController(
                title: L("compose.limit.title"),
                message: L("compose.limit.free_message"),
                preferredStyle: .alert
            )
            if DailyUsageManager.shared.canWatchComposeRewardedAd {
                alert.addAction(UIAlertAction(
                    title: L("compose.limit.watch_ad"),
                    style: .default
                ) { [weak self] _ in
                    self?.showRewardedAdForCompose()
                })
            }
            alert.addAction(UIAlertAction(
                title: L("compose.limit.upgrade"),
                style: .default
            ) { [weak self] _ in
                self?.presentPaywall()
            })
            alert.addAction(UIAlertAction(
                title: L("common.cancel"),
                style: .cancel
            ))
            present(alert, animated: true)
        } else {
            let alert = UIAlertController(
                title: L("compose.limit.title"),
                message: String(format: L("compose.limit.pro_message"),
                              FeatureGate.shared.dailyComposeLimit),
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(
                title: L("compose.limit.upgrade_premium"),
                style: .default
            ) { [weak self] _ in
                self?.presentPaywall()
            })
            alert.addAction(UIAlertAction(
                title: L("common.ok"),
                style: .cancel
            ))
            present(alert, animated: true)
        }
    }

    private func showRewardedAdForCompose() {
        let rewardVC = RewardedAdsViewController(mode: .compose)
        rewardVC.modalPresentationStyle = .fullScreen
        present(rewardVC, animated: true)
    }

    private func presentPaywall() {
        let paywallVC = PaywallViewController()
        paywallVC.modalPresentationStyle = .pageSheet
        present(paywallVC, animated: true)
    }
}

// MARK: - UITextViewDelegate

extension AIWriterViewController: UITextViewDelegate {
    func textViewDidBeginEditing(_ textView: UITextView) {
        if textView === inputTextView {
            inputPlaceholderLabel.isHidden = !textView.text.isEmpty
        } else if textView === contextTextView {
            contextPlaceholderLabel.isHidden = !textView.text.isEmpty
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.scrollToCaretInTextView(textView)
        }
    }

    func textViewDidChange(_ textView: UITextView) {
        if textView === inputTextView {
            // ★ v7: 템플릿 폼 활성 시 inputTextView 높이 관리 건너뜀
            if inputTextView.isHidden { return }
            if let text = textView.text, text.count > AppConstants.Limits.maxCharacters {
                textView.text = String(text.prefix(AppConstants.Limits.maxCharacters))
            }
            updateGenerateButtonState()
            updateCharacterCounter()
            inputPlaceholderLabel.isHidden = !textView.text.isEmpty

            // v6: 안정적 동적 높이 — 명시적 constraint
            let maxHeight: CGFloat = 300
            let measuredWidth = textView.bounds.width > 0 ? textView.bounds.width : textView.frame.width
            let fittingSize = textView.sizeThatFits(CGSize(width: measuredWidth, height: .greatestFiniteMagnitude))

            if fittingSize.height > maxHeight {
                if !textView.isScrollEnabled {
                    textView.isScrollEnabled = true
                }
                if !inputTextViewHeightConstraint.isActive {
                    inputTextViewHeightConstraint.constant = maxHeight
                    inputTextViewHeightConstraint.isActive = true
                }
                DispatchQueue.main.async {
                    let caretRect = textView.caretRect(for: textView.selectedTextRange?.end ?? textView.endOfDocument)
                    textView.scrollRectToVisible(caretRect.insetBy(dx: 0, dy: -4), animated: false)
                }
            } else {
                if textView.isScrollEnabled {
                    textView.isScrollEnabled = false
                    textView.invalidateIntrinsicContentSize()
                }
                if inputTextViewHeightConstraint.isActive {
                    inputTextViewHeightConstraint.isActive = false
                }
            }

            view.layoutIfNeeded()

        } else if textView === contextTextView {
            contextPlaceholderLabel.isHidden = !textView.text.isEmpty

            // v6: 안정적 동적 높이 — contextTextView
            let maxHeight: CGFloat = 200
            let measuredWidth = textView.bounds.width > 0 ? textView.bounds.width : textView.frame.width
            let fittingSize = textView.sizeThatFits(CGSize(width: measuredWidth, height: .greatestFiniteMagnitude))

            if fittingSize.height > maxHeight {
                if !textView.isScrollEnabled {
                    textView.isScrollEnabled = true
                }
                if !contextTextViewHeightConstraint.isActive {
                    contextTextViewHeightConstraint.constant = maxHeight
                    contextTextViewHeightConstraint.isActive = true
                }
                DispatchQueue.main.async {
                    let caretRect = textView.caretRect(for: textView.selectedTextRange?.end ?? textView.endOfDocument)
                    textView.scrollRectToVisible(caretRect.insetBy(dx: 0, dy: -4), animated: false)
                }
            } else {
                if textView.isScrollEnabled {
                    textView.isScrollEnabled = false
                    textView.invalidateIntrinsicContentSize()
                }
                if contextTextViewHeightConstraint.isActive {
                    contextTextViewHeightConstraint.isActive = false
                }
            }

            view.layoutIfNeeded()
        }

        updateClearButtonVisibility()
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        if textView === inputTextView {
            inputPlaceholderLabel.isHidden = !textView.text.isEmpty
        } else if textView === contextTextView {
            contextPlaceholderLabel.isHidden = !textView.text.isEmpty
        }
    }
}

// MARK: - UITextFieldDelegate (Template Form)

extension AIWriterViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if activeTemplate != nil {
            let currentIndex = textField.tag
            if currentIndex < templateFieldTextFields.count - 1 {
                templateFieldTextFields[currentIndex + 1].becomeFirstResponder()
            } else {
                textField.resignFirstResponder()
            }
            return false
        }
        return true
    }
}

// MARK: - UIScrollViewDelegate (Page Control)

extension AIWriterViewController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === resultScrollView else { return }
        let cardWidth = view.bounds.width - 56
        guard cardWidth > 0 else { return }
        let page = Int(round(scrollView.contentOffset.x / (cardWidth + 8)))
        pageControl.currentPage = page
    }
}
