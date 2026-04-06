import UIKit

class QuickNoteEditView: UIView {

    // MARK: - Callbacks

    var onSave: ((String) -> Void)?
    var onPaste: ((String) -> Void)?
    var onCopy: ((String) -> Void)?
    var onClose: (() -> Void)?
    var onClearText: (() -> Void)?
    var onCursorMoveRequested: ((Int) -> Void)?

    // MARK: - UI

    private let headerView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let headerTitleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 16, weight: .bold)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let doneButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle(L("quicknote.done"), for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let noteInputView: TranslationInputView = {
        let v = TranslationInputView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.setPlaceholder(L("quicknote.placeholder"))
        v.maxCharacters = AppConstants.Limits.quickNoteMaxLength
        v.hideCounter()
        v.isCaretTapEnabled = true
        return v
    }()

    private let charCountLabel: UILabel = {
        let l = UILabel()
        l.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        l.textAlignment = .right
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let actionBar: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let pasteButton: UIButton = {
        let btn = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        btn.setImage(UIImage(systemName: "doc.on.clipboard", withConfiguration: config), for: .normal)
        btn.setTitle(" " + L("quicknote.paste"), for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let copyButton: UIButton = {
        let btn = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        btn.setImage(UIImage(systemName: "doc.on.doc", withConfiguration: config), for: .normal)
        btn.setTitle(" " + L("quicknote.copy"), for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private var inputHeightConstraint: NSLayoutConstraint?
    var onHeightChanged: ((CGFloat) -> Void)?

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
        addSubview(headerView)
        headerView.addSubview(headerTitleLabel)
        headerView.addSubview(doneButton)
        addSubview(noteInputView)
        addSubview(charCountLabel)
        addSubview(actionBar)
        actionBar.addSubview(pasteButton)
        actionBar.addSubview(copyButton)

        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        pasteButton.addTarget(self, action: #selector(pasteTapped), for: .touchUpInside)
        copyButton.addTarget(self, action: #selector(copyTapped), for: .touchUpInside)

        inputHeightConstraint = noteInputView.heightAnchor.constraint(equalToConstant: 44)
        inputHeightConstraint?.isActive = true

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: topAnchor),
            headerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 44),

            headerTitleLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),
            headerTitleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            doneButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -12),
            doneButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            noteInputView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            noteInputView.leadingAnchor.constraint(equalTo: leadingAnchor),
            noteInputView.trailingAnchor.constraint(equalTo: trailingAnchor),

            charCountLabel.topAnchor.constraint(equalTo: noteInputView.bottomAnchor, constant: 2),
            charCountLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            actionBar.topAnchor.constraint(equalTo: charCountLabel.bottomAnchor, constant: 4),
            actionBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            actionBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            actionBar.heightAnchor.constraint(equalToConstant: 36),
            actionBar.bottomAnchor.constraint(equalTo: bottomAnchor),

            pasteButton.leadingAnchor.constraint(equalTo: actionBar.leadingAnchor, constant: 12),
            pasteButton.centerYAnchor.constraint(equalTo: actionBar.centerYAnchor),

            copyButton.trailingAnchor.constraint(equalTo: actionBar.trailingAnchor, constant: -12),
            copyButton.centerYAnchor.constraint(equalTo: actionBar.centerYAnchor),
        ])

        noteInputView.onHeightChanged = { [weak self] newHeight in
            self?.inputHeightConstraint?.constant = newHeight
            self?.onHeightChanged?(self?.idealHeight() ?? 130)
        }

        noteInputView.onClearText = { [weak self] in
            self?.onClearText?()
        }

        updateCharCount()
    }

    // MARK: - Public

    func setupCaretCallback() {
        noteInputView.onCaretTap = { [weak self] index in
            self?.onCursorMoveRequested?(index)
        }
    }

    func setCursorIndex(_ index: Int) {
        noteInputView.setCursorIndex(index)
    }

    func configure(with note: QuickNote?) {
        if let note = note {
            headerTitleLabel.text = L("quicknote.edit")
            noteInputView.insertText(note.content)
        } else {
            headerTitleLabel.text = L("quicknote.new")
        }
        updateCharCount()
    }

    func getCurrentText() -> String? {
        let text = noteInputView.currentText
        return text.isEmpty ? nil : text
    }

    func insertText(_ text: String) {
        let remaining = AppConstants.Limits.quickNoteMaxLength - noteInputView.currentText.count
        guard remaining > 0 else { return }
        let trimmed = String(text.prefix(remaining))
        noteInputView.insertText(trimmed)
        updateCharCount()
    }

    func deleteBackward() {
        noteInputView.deleteBackward()
        updateCharCount()
    }

    func setDisplayText(_ text: String) {
        noteInputView.setDisplayText(text)
    }

    func updateCharCount(_ count: Int) {
        let max = AppConstants.Limits.quickNoteMaxLength
        charCountLabel.text = "\(count)/\(max)"
        if count >= max {
            charCountLabel.textColor = .systemRed
        } else {
            charCountLabel.textColor = isDark ? UIColor(white: 0.5, alpha: 1) : .secondaryLabel
        }
    }

    func idealHeight() -> CGFloat {
        return 44 + (inputHeightConstraint?.constant ?? 44) + 20 + 36
    }

    func applyTheme(_ theme: KeyboardTheme?) {
        customTheme = theme
        noteInputView.applyTheme(theme)
    }

    func updateAppearance(isDark: Bool) {
        self.isDark = isDark
        let textColor: UIColor
        let mutedColor: UIColor
        let accentColor: UIColor

        if let theme = customTheme {
            backgroundColor = theme.keyboardBackground
            textColor = theme.keyTextColor
            mutedColor = theme.keyTextColor.withAlphaComponent(0.5)
            accentColor = theme.keyTextColor
        } else {
            backgroundColor = isDark ? UIColor(white: 0.12, alpha: 1) : UIColor(white: 0.95, alpha: 1)
            textColor = isDark ? .white : .label
            mutedColor = isDark ? UIColor(white: 0.5, alpha: 1) : .secondaryLabel
            accentColor = .systemBlue
        }

        headerTitleLabel.textColor = textColor
        doneButton.tintColor = accentColor
        charCountLabel.textColor = mutedColor
        pasteButton.tintColor = accentColor
        copyButton.tintColor = accentColor
        noteInputView.updateAppearance(isDark: isDark)
    }

    // MARK: - Private

    private func updateCharCount() {
        let count = noteInputView.currentText.count
        let max = AppConstants.Limits.quickNoteMaxLength
        charCountLabel.text = "\(count)/\(max)"
        if count >= max {
            charCountLabel.textColor = .systemRed
        } else {
            charCountLabel.textColor = isDark ? UIColor(white: 0.5, alpha: 1) : .secondaryLabel
        }
    }

    // MARK: - Actions

    @objc private func doneTapped() {
        onClose?()
    }

    @objc private func pasteTapped() {
        let content = noteInputView.currentText
        guard !content.isEmpty else { return }
        onPaste?(content)
    }

    @objc private func copyTapped() {
        let content = noteInputView.currentText
        guard !content.isEmpty else { return }
        onCopy?(content)
    }
}
