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
    private var resultCards: [UIView] = []
    private var resultLabels: [UILabel] = []
    private let pageControl = UIPageControl()

    // Bottom bar
    private let bottomBar = UIView()

    // Clipboard banner
    private lazy var clipboardBanner: UIView = {
        let banner = UIView()
        banner.backgroundColor = AppColors.accent.withAlphaComponent(0.1)
        banner.layer.cornerRadius = 10
        banner.isHidden = true
        banner.translatesAutoresizingMaskIntoConstraints = false

        let icon = UILabel()
        icon.text = "\u{1F4CB}"
        icon.font = .systemFont(ofSize: 16)
        icon.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = L("ai_writer.clipboard_suggest")
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = AppColors.text
        label.translatesAutoresizingMaskIntoConstraints = false

        let useBtn = UIButton(type: .system)
        useBtn.setTitle(L("ai_writer.clipboard_use"), for: .normal)
        useBtn.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        useBtn.setTitleColor(AppColors.accent, for: .normal)
        useBtn.addTarget(self, action: #selector(acceptClipboard), for: .touchUpInside)
        useBtn.translatesAutoresizingMaskIntoConstraints = false

        let dismissBtn = UIButton(type: .system)
        dismissBtn.setTitle(L("ai_writer.clipboard_dismiss"), for: .normal)
        dismissBtn.titleLabel?.font = .systemFont(ofSize: 13)
        dismissBtn.setTitleColor(AppColors.textMuted, for: .normal)
        dismissBtn.addTarget(self, action: #selector(dismissClipboard), for: .touchUpInside)
        dismissBtn.translatesAutoresizingMaskIntoConstraints = false

        banner.addSubview(icon)
        banner.addSubview(label)
        banner.addSubview(useBtn)
        banner.addSubview(dismissBtn)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 12),
            icon.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
            dismissBtn.trailingAnchor.constraint(equalTo: banner.trailingAnchor, constant: -12),
            dismissBtn.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
            useBtn.trailingAnchor.constraint(equalTo: dismissBtn.leadingAnchor, constant: -12),
            useBtn.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
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
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
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

    // MARK: - Keyboard Avoidance

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

            if let textView = activeTextView, let container = textView.superview {
                let rect = container.convert(container.bounds, to: self.scrollView)
                self.scrollView.scrollRectToVisible(rect.insetBy(dx: 0, dy: -20), animated: true)
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
        inputTextView.tintColor = AppColors.accent
        inputTextView.delegate = self
        inputTextView.translatesAutoresizingMaskIntoConstraints = false

        // Reply toggle button (Fix 2: SF Symbol + new text)
        let chatIcon = UIImage(systemName: "bubble.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .medium))
        contextToggleButton.setImage(chatIcon, for: .normal)
        contextToggleButton.tintColor = AppColors.accent
        contextToggleButton.setTitle(" " + L("ai_writer.reply_paste"), for: .normal)
        contextToggleButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        contextToggleButton.setTitleColor(AppColors.accent, for: .normal)
        contextToggleButton.contentHorizontalAlignment = .leading
        contextToggleButton.addTarget(self, action: #selector(toggleContext), for: .touchUpInside)
        contextToggleButton.translatesAutoresizingMaskIntoConstraints = false

        // Reply context container
        setupContextContainer()

        card.addSubview(headerStack)
        card.addSubview(inputTextView)
        card.addSubview(inputPlaceholderLabel)
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

            contextToggleButton.topAnchor.constraint(equalTo: inputTextView.bottomAnchor, constant: 4),
            contextToggleButton.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),

            contextContainer.topAnchor.constraint(equalTo: contextToggleButton.bottomAnchor, constant: 12),
            contextContainer.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            contextContainer.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
        ])

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
        contextTextView.tintColor = AppColors.accent
        contextTextView.delegate = self
        contextTextView.translatesAutoresizingMaskIntoConstraints = false

        contextContainer.addSubview(contextLabel)
        contextContainer.addSubview(contextTextView)
        contextContainer.addSubview(contextPlaceholderLabel)

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
        ])
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
            btn.layer.cornerRadius = 20
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
            iconEmoji: "\u{1F310}",
            iconBg: UIColor(red: 0.91, green: 0.95, blue: 1.0, alpha: 1),
            title: L("ai_writer.lang.section_title"),
            valueLabel: langValueLabel,
            defaultValue: L("ai_writer.lang.auto"),
            action: #selector(openLangSheet)
        )

        let toneRow = makeOptionRow(
            iconEmoji: "\u{1F3AD}",
            iconBg: UIColor(red: 1.0, green: 0.95, blue: 0.91, alpha: 1),
            title: L("ai_writer.tone_title"),
            valueLabel: toneValueLabel,
            defaultValue: "\u{1F4AC} " + L("tone.casual"),
            action: #selector(openToneSheet)
        )

        let lengthRow = makeOptionRow(
            iconEmoji: "\u{1F4CF}",
            iconBg: UIColor(red: 0.91, green: 1.0, blue: 0.91, alpha: 1),
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

    private func makeOptionRow(iconEmoji: String, iconBg: UIColor, title: String, valueLabel: UILabel, defaultValue: String, action: Selector) -> UIView {
        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: 56).isActive = true

        let tap = UITapGestureRecognizer(target: self, action: action)
        row.addGestureRecognizer(tap)

        let iconContainer = UIView()
        iconContainer.backgroundColor = iconBg
        iconContainer.layer.cornerRadius = 10
        iconContainer.translatesAutoresizingMaskIntoConstraints = false

        let iconLabel = UILabel()
        iconLabel.text = iconEmoji
        iconLabel.font = .systemFont(ofSize: 18)
        iconLabel.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.addSubview(iconLabel)

        NSLayoutConstraint.activate([
            iconContainer.widthAnchor.constraint(equalToConstant: 36),
            iconContainer.heightAnchor.constraint(equalToConstant: 36),
            iconLabel.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconLabel.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
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
        generateButton.backgroundColor = AppColors.accent
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
        loadingIndicator.color = AppColors.accent
        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(loadingIndicator)

        resultScrollView.isPagingEnabled = true
        resultScrollView.showsHorizontalScrollIndicator = false
        resultScrollView.isHidden = true
        resultScrollView.delegate = self
        resultScrollView.translatesAutoresizingMaskIntoConstraints = false

        pageControl.currentPageIndicatorTintColor = AppColors.accent
        pageControl.pageIndicatorTintColor = AppColors.border
        pageControl.isHidden = true
        pageControl.translatesAutoresizingMaskIntoConstraints = false

        contentStack.addArrangedSubview(resultScrollView)
        contentStack.addArrangedSubview(pageControl)

        NSLayoutConstraint.activate([
            resultScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 180),
        ])
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
            accentBar.backgroundColor = AppColors.accent
            accentBar.layer.cornerRadius = 1.5
            accentBar.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(accentBar)

            // "AI-composed message" label
            let resultHeaderLabel = UILabel()
            resultHeaderLabel.text = L("ai_writer.result_label")
            resultHeaderLabel.font = .systemFont(ofSize: 11, weight: .semibold)
            resultHeaderLabel.textColor = AppColors.accent
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
            copyBtn.setTitleColor(AppColors.accent, for: .normal)
            copyBtn.backgroundColor = AppColors.accent.withAlphaComponent(0.08)
            copyBtn.layer.cornerRadius = 20
            copyBtn.layer.borderWidth = 1.5
            copyBtn.layer.borderColor = AppColors.accent.cgColor
            copyBtn.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
            copyBtn.tag = i
            copyBtn.addTarget(self, action: #selector(copyVariation(_:)), for: .touchUpInside)

            let regenerateBtn = UIButton(type: .system)
            regenerateBtn.setTitle(L("ai_writer.regenerate"), for: .normal)
            regenerateBtn.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
            regenerateBtn.setTitleColor(AppColors.textSub, for: .normal)
            regenerateBtn.backgroundColor = .clear
            regenerateBtn.layer.cornerRadius = 20
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
        resultScrollView.contentSize = CGSize(
            width: CGFloat(messages.count) * (cardWidth + 8),
            height: resultScrollView.bounds.height
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
                btn.setTitleColor(isSelected ? AppColors.accent : AppColors.textSub, for: .normal)
                btn.backgroundColor = isSelected
                    ? AppColors.accent.withAlphaComponent(0.08)
                    : AppColors.bg
                btn.layer.cornerRadius = 16
                btn.layer.borderWidth = 1.5
                btn.layer.borderColor = isSelected
                    ? AppColors.accent.cgColor
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

            grid.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 12),
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
        ])

        presentBottomSheet(content: content, height: 380)
    }

    @objc private func toneSheetSelected(_ sender: UIButton) {
        guard let toneId = sender.accessibilityIdentifier else { return }
        selectedTone = toneId

        if let item = toneItems.first(where: { $0.id == toneId }) {
            toneValueLabel.text = "\(item.emoji) \(L(item.nameKey))"
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.dismissSheet()
        }
    }

    // MARK: - Length Bottom Sheet

    @objc private func openLengthSheet() {
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

            stack.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
        ])

        presentBottomSheet(content: content, height: 300)
    }

    private func makeLengthSheetRow(id: String, icon: String, name: String, desc: String, isSelected: Bool) -> UIView {
        let row = UIView()
        row.backgroundColor = isSelected ? AppColors.accent.withAlphaComponent(0.08) : AppColors.bg
        row.layer.cornerRadius = 16
        row.layer.borderWidth = 1.5
        row.layer.borderColor = isSelected ? AppColors.accent.cgColor : AppColors.bg.cgColor
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
        nameLabel.textColor = isSelected ? AppColors.accent : AppColors.text
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        let descLabel = UILabel()
        descLabel.text = desc
        descLabel.font = .systemFont(ofSize: 12)
        descLabel.textColor = AppColors.textSub
        descLabel.translatesAutoresizingMaskIntoConstraints = false

        let checkView = UIView()
        checkView.layer.cornerRadius = 11
        checkView.layer.borderWidth = 2
        checkView.layer.borderColor = isSelected ? AppColors.accent.cgColor : AppColors.border.cgColor
        checkView.backgroundColor = isSelected ? AppColors.accent : .clear
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
        guard let id = sender.view?.accessibilityIdentifier else { return }
        selectedLength = id

        let lengths = ["short": L("ai_writer.length.short"),
                       "medium": L("ai_writer.length.medium"),
                       "long": L("ai_writer.length.long")]
        lengthValueLabel.text = lengths[id] ?? id

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.dismissSheet()
        }
    }

    // MARK: - Language Bottom Sheet

    @objc private func openLangSheet() {
        let content = UIView()
        content.tag = 300

        let title = UILabel()
        title.text = L("ai_writer.lang.select_title")
        title.font = .systemFont(ofSize: 17, weight: .bold)
        title.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(title)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        for lang in outputLanguages {
            let displayName = lang.code == "auto"
                ? L("ai_writer.lang.auto")
                : lang.nativeName
            let isSelected = lang.code == outputLanguage

            let row = UIView()
            row.translatesAutoresizingMaskIntoConstraints = false
            row.heightAnchor.constraint(equalToConstant: 48).isActive = true
            row.accessibilityIdentifier = lang.code
            let tap = UITapGestureRecognizer(target: self, action: #selector(langSheetSelected(_:)))
            row.addGestureRecognizer(tap)

            let flagLabel = UILabel()
            flagLabel.text = lang.flag
            flagLabel.font = .systemFont(ofSize: 20)
            flagLabel.translatesAutoresizingMaskIntoConstraints = false

            let nameLabel = UILabel()
            nameLabel.text = displayName
            nameLabel.font = .systemFont(ofSize: 15, weight: isSelected ? .semibold : .medium)
            nameLabel.textColor = isSelected ? AppColors.accent : AppColors.text
            nameLabel.translatesAutoresizingMaskIntoConstraints = false

            row.addSubview(flagLabel)
            row.addSubview(nameLabel)

            if isSelected {
                let check = UIImageView(image: UIImage(systemName: "checkmark"))
                check.tintColor = AppColors.accent
                check.translatesAutoresizingMaskIntoConstraints = false
                row.addSubview(check)
                NSLayoutConstraint.activate([
                    check.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -20),
                    check.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                    check.widthAnchor.constraint(equalToConstant: 16),
                ])
            }

            NSLayoutConstraint.activate([
                flagLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 20),
                flagLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                nameLabel.leadingAnchor.constraint(equalTo: flagLabel.trailingAnchor, constant: 12),
                nameLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            ])

            stack.addArrangedSubview(row)
        }

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            title.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
        ])

        presentBottomSheet(content: content, height: 500)
    }

    @objc private func langSheetSelected(_ sender: UITapGestureRecognizer) {
        guard let code = sender.view?.accessibilityIdentifier else { return }
        outputLanguage = code

        if let lang = outputLanguages.first(where: { $0.code == code }) {
            let displayName = lang.code == "auto" ? L("ai_writer.lang.auto") : lang.nativeName
            langValueLabel.text = displayName
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.dismissSheet()
        }
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
        inputTextView.text = L(template.promptKey)
        inputPlaceholderLabel.isHidden = true

        if let toneIndex = toneItems.firstIndex(where: { $0.id == template.suggestedTone }) {
            selectedTone = template.suggestedTone
            if let item = toneItems[safe: toneIndex] {
                toneValueLabel.text = "\(item.emoji) \(L(item.nameKey))"
            }
        }

        updateGenerateButtonState()
        updateCharacterCounter()
    }

    // MARK: - Generate Actions

    private func updateGenerateButtonState() {
        let hasText = !(inputTextView.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
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
        generateButton.backgroundColor = AppColors.accent

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
        guard let prompt = inputTextView.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !prompt.isEmpty else { return }
        lastPrompt = prompt
        requestCompose(prompt: prompt)
    }

    @objc private func watchAdTapped() {
        let rewardVC = RewardedAdsViewController(mode: .compose)
        rewardVC.modalPresentationStyle = .pageSheet
        if let sheet = rewardVC.sheetPresentationController {
            sheet.detents = [.medium()]
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
    }

    // MARK: - Character Counter

    private func updateCharacterCounter() {
        let count = inputTextView.text?.count ?? 0
        let max = AppConstants.Limits.maxCharacters
        charCountLabel.text = "\(count)/\(max)"
        if count >= max {
            charCountLabel.textColor = .systemRed
        } else if count >= max - 100 {
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
            langCode = AppGroupManager.shared.string(forKey: AppConstants.UserDefaultsKeys.appLanguage) ?? "ko"
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
                    self?.displayResults(messages)
                    self?.saveToHistory(prompt: prompt, result: messages[0], body: body)
                } else if let message = json["message"] as? String {
                    self?.displayResults([message])
                    self?.saveToHistory(prompt: prompt, result: message, body: body)
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

        guard scrollView.contentInset.bottom > 0, let container = textView.superview else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let rect = container.convert(container.bounds, to: self.scrollView)
            self.scrollView.scrollRectToVisible(rect.insetBy(dx: 0, dy: -20), animated: true)
        }
    }

    func textViewDidChange(_ textView: UITextView) {
        if textView === inputTextView {
            if let text = textView.text, text.count > AppConstants.Limits.maxCharacters {
                textView.text = String(text.prefix(AppConstants.Limits.maxCharacters))
            }
            updateGenerateButtonState()
            updateCharacterCounter()
            inputPlaceholderLabel.isHidden = !textView.text.isEmpty
        } else if textView === contextTextView {
            contextPlaceholderLabel.isHidden = !textView.text.isEmpty
        }
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        if textView === inputTextView {
            inputPlaceholderLabel.isHidden = !textView.text.isEmpty
        } else if textView === contextTextView {
            contextPlaceholderLabel.isHidden = !textView.text.isEmpty
        }
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
