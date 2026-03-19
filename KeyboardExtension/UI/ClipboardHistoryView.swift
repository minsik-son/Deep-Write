import UIKit

class ClipboardHistoryView: UIView {

    var onItemSelected: ((String) -> Void)?
    var onDismiss: (() -> Void)?

    private var items: [ClipboardItem] = []
    private var isDark = false
    private var customTheme: KeyboardTheme?

    // MARK: - Views

    private let headerView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let closeButton: UIButton = {
        let btn = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        btn.setImage(UIImage(systemName: "xmark", withConfiguration: config), for: .normal)
        btn.tintColor = .label
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = L("clipboard.title")
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = .label
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let deleteAllButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle(L("clipboard.delete_all"), for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 14)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let headerSeparator: UIView = {
        let v = UIView()
        v.backgroundColor = .separator
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .plain)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.separatorStyle = .none
        tv.rowHeight = UITableView.automaticDimension
        tv.estimatedRowHeight = 70
        return tv
    }()

    // Empty state
    private let emptyContainerView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.isHidden = true
        return v
    }()

    private let emptyIconView: UIImageView = {
        let config = UIImage.SymbolConfiguration(pointSize: 36, weight: .light)
        let iv = UIImageView(image: UIImage(systemName: "doc.on.clipboard", withConfiguration: config))
        iv.tintColor = .secondaryLabel
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let emptyTitleLabel: UILabel = {
        let label = UILabel()
        label.text = L("clipboard.empty.title")
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let emptySubtitleLabel: UILabel = {
        let label = UILabel()
        label.text = L("clipboard.empty.subtitle")
        label.font = .systemFont(ofSize: 13)
        label.textColor = .tertiaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // Onboarding card
    private let onboardingCard: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.layer.cornerRadius = 12
        v.isHidden = true
        return v
    }()

    private let onboardingTitleLabel: UILabel = {
        let label = UILabel()
        label.text = L("clipboard.onboarding.title")
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let onboardingBodyLabel: UILabel = {
        let label = UILabel()
        label.text = L("clipboard.onboarding.body")
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let onboardingPasteLabel: UILabel = {
        let label = UILabel()
        label.text = L("clipboard.onboarding.paste_notice")
        label.font = .systemFont(ofSize: 12)
        label.textColor = .tertiaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let onboardingConfirmButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle(L("clipboard.onboarding.confirm"), for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

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
        backgroundColor = UIColor(white: 0.95, alpha: 1)

        addSubview(headerView)
        headerView.addSubview(closeButton)
        headerView.addSubview(titleLabel)
        headerView.addSubview(deleteAllButton)
        addSubview(headerSeparator)
        addSubview(tableView)
        addSubview(emptyContainerView)
        emptyContainerView.addSubview(emptyIconView)
        emptyContainerView.addSubview(emptyTitleLabel)
        emptyContainerView.addSubview(emptySubtitleLabel)
        addSubview(onboardingCard)
        onboardingCard.addSubview(onboardingTitleLabel)
        onboardingCard.addSubview(onboardingBodyLabel)
        onboardingCard.addSubview(onboardingPasteLabel)
        onboardingCard.addSubview(onboardingConfirmButton)

        let headerHeight: CGFloat = 44

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: topAnchor),
            headerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: headerHeight),

            closeButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 12),
            closeButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 36),
            closeButton.heightAnchor.constraint(equalToConstant: 36),

            titleLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            deleteAllButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -12),
            deleteAllButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            headerSeparator.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            headerSeparator.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerSeparator.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerSeparator.heightAnchor.constraint(equalToConstant: 0.5),

            tableView.topAnchor.constraint(equalTo: headerSeparator.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomAnchor),

            // Empty state
            emptyContainerView.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyContainerView.centerYAnchor.constraint(equalTo: centerYAnchor),

            emptyIconView.topAnchor.constraint(equalTo: emptyContainerView.topAnchor),
            emptyIconView.centerXAnchor.constraint(equalTo: emptyContainerView.centerXAnchor),

            emptyTitleLabel.topAnchor.constraint(equalTo: emptyIconView.bottomAnchor, constant: 12),
            emptyTitleLabel.centerXAnchor.constraint(equalTo: emptyContainerView.centerXAnchor),

            emptySubtitleLabel.topAnchor.constraint(equalTo: emptyTitleLabel.bottomAnchor, constant: 6),
            emptySubtitleLabel.centerXAnchor.constraint(equalTo: emptyContainerView.centerXAnchor),
            emptySubtitleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 40),
            emptySubtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -40),
            emptySubtitleLabel.bottomAnchor.constraint(equalTo: emptyContainerView.bottomAnchor),

            // Onboarding card
            onboardingCard.centerXAnchor.constraint(equalTo: centerXAnchor),
            onboardingCard.centerYAnchor.constraint(equalTo: centerYAnchor),
            onboardingCard.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            onboardingCard.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),

            onboardingTitleLabel.topAnchor.constraint(equalTo: onboardingCard.topAnchor, constant: 20),
            onboardingTitleLabel.leadingAnchor.constraint(equalTo: onboardingCard.leadingAnchor, constant: 16),
            onboardingTitleLabel.trailingAnchor.constraint(equalTo: onboardingCard.trailingAnchor, constant: -16),

            onboardingBodyLabel.topAnchor.constraint(equalTo: onboardingTitleLabel.bottomAnchor, constant: 10),
            onboardingBodyLabel.leadingAnchor.constraint(equalTo: onboardingCard.leadingAnchor, constant: 16),
            onboardingBodyLabel.trailingAnchor.constraint(equalTo: onboardingCard.trailingAnchor, constant: -16),

            onboardingPasteLabel.topAnchor.constraint(equalTo: onboardingBodyLabel.bottomAnchor, constant: 10),
            onboardingPasteLabel.leadingAnchor.constraint(equalTo: onboardingCard.leadingAnchor, constant: 16),
            onboardingPasteLabel.trailingAnchor.constraint(equalTo: onboardingCard.trailingAnchor, constant: -16),

            onboardingConfirmButton.topAnchor.constraint(equalTo: onboardingPasteLabel.bottomAnchor, constant: 14),
            onboardingConfirmButton.centerXAnchor.constraint(equalTo: onboardingCard.centerXAnchor),
            onboardingConfirmButton.bottomAnchor.constraint(equalTo: onboardingCard.bottomAnchor, constant: -16),
        ])

        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(ClipboardCell.self, forCellReuseIdentifier: "ClipboardCell")

        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        deleteAllButton.addTarget(self, action: #selector(deleteAllTapped), for: .touchUpInside)
        onboardingConfirmButton.addTarget(self, action: #selector(onboardingConfirmTapped), for: .touchUpInside)
    }

    // MARK: - Actions

    @objc private func closeTapped() { onDismiss?() }

    @objc private func deleteAllTapped() {
        HistoryManager.shared.deleteAllItems(ofType: .clipboard)
        items = []
        tableView.reloadData()
        updateEmptyState()
    }

    @objc private func onboardingConfirmTapped() {
        let defaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier)
        defaults?.set(true, forKey: AppConstants.UserDefaultsKeys.clipboardOnboardingShown)

        UIView.animate(withDuration: 0.2) {
            self.onboardingCard.alpha = 0
        } completion: { _ in
            self.onboardingCard.isHidden = true
            self.onboardingCard.alpha = 1
        }
    }

    // MARK: - Public

    func reloadData() {
        let historyItems = HistoryManager.shared.loadItems(ofType: .clipboard)
        items = historyItems.map { item in
            ClipboardItem(
                id: item.id,
                text: item.originalText,
                copiedAt: item.createdAt
            )
        }
        tableView.reloadData()
        updateEmptyState()
        checkOnboarding()
    }

    func applyTheme(_ theme: KeyboardTheme?) {
        customTheme = theme
    }

    func updateAppearance(isDark: Bool) {
        self.isDark = isDark
        let bg: UIColor
        let textColor: UIColor
        let mutedColor: UIColor

        if let theme = customTheme {
            bg = theme.keyboardBackground
            textColor = theme.keyTextColor
            mutedColor = theme.keyTextColor.withAlphaComponent(0.5)
        } else {
            bg = isDark ? UIColor(white: 0.12, alpha: 1) : UIColor(white: 0.95, alpha: 1)
            textColor = isDark ? .white : .label
            mutedColor = isDark ? UIColor(white: 0.5, alpha: 1) : .secondaryLabel
        }

        backgroundColor = bg
        headerView.backgroundColor = bg
        tableView.backgroundColor = bg
        titleLabel.textColor = textColor
        closeButton.tintColor = textColor
        deleteAllButton.setTitleColor(customTheme != nil ? mutedColor : (isDark ? UIColor(white: 0.6, alpha: 1) : .systemRed), for: .normal)
        emptyIconView.tintColor = mutedColor
        emptyTitleLabel.textColor = mutedColor
        emptySubtitleLabel.textColor = mutedColor.withAlphaComponent(0.7)
        onboardingCard.backgroundColor = customTheme != nil ? bg : (isDark ? UIColor(white: 0.18, alpha: 1) : .white)
        onboardingTitleLabel.textColor = textColor
        onboardingBodyLabel.textColor = mutedColor
        onboardingPasteLabel.textColor = mutedColor.withAlphaComponent(0.7)
        tableView.reloadData()
    }

    // MARK: - Private

    private func updateEmptyState() {
        let isEmpty = items.isEmpty
        emptyContainerView.isHidden = !isEmpty
        tableView.isHidden = isEmpty
        deleteAllButton.isHidden = isEmpty
    }

    private func checkOnboarding() {
        let defaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier)
        let shown = defaults?.bool(forKey: AppConstants.UserDefaultsKeys.clipboardOnboardingShown) ?? false
        if !shown {
            onboardingCard.isHidden = false
            tableView.isHidden = true
            emptyContainerView.isHidden = true
        } else {
            onboardingCard.isHidden = true
        }
    }

    // MARK: - Relative Time

    private func relativeTimeString(from date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 {
            return L("clipboard.time.just_now")
        } else if seconds < 3600 {
            let minutes = seconds / 60
            return String(format: L("clipboard.time.minutes_ago"), minutes)
        } else if seconds < 86400 {
            let hours = seconds / 3600
            return String(format: L("clipboard.time.hours_ago"), hours)
        } else if seconds < 172800 {
            return L("clipboard.time.yesterday")
        } else {
            let days = seconds / 86400
            return String(format: L("clipboard.time.days_ago"), days)
        }
    }
}

// MARK: - UITableViewDataSource

extension ClipboardHistoryView: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ClipboardCell", for: indexPath) as! ClipboardCell
        let item = items[indexPath.row]
        cell.configure(
            text: item.preview,
            time: relativeTimeString(from: item.copiedAt),
            isDark: isDark,
            theme: customTheme
        )
        cell.onDelete = { [weak self] in
            guard let self = self else { return }
            let itemToDelete = self.items[indexPath.row]
            HistoryManager.shared.deleteItem(id: itemToDelete.id)
            self.items.remove(at: indexPath.row)
            tableView.deleteRows(at: [indexPath], with: .automatic)
            self.updateEmptyState()
        }
        return cell
    }
}

// MARK: - UITableViewDelegate

extension ClipboardHistoryView: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = items[indexPath.row]
        onItemSelected?(item.text)
    }
}

// MARK: - ClipboardCell

private class ClipboardCell: UITableViewCell {

    var onDelete: (() -> Void)?

    private let cardView: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 10
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let previewLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.numberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let timeLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .caption2)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let deleteButton: UIButton = {
        let btn = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        btn.setImage(UIImage(systemName: "trash", withConfiguration: config), for: .normal)
        btn.tintColor = .secondaryLabel
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupCell()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupCell() {
        backgroundColor = .clear
        selectionStyle = .none

        contentView.addSubview(cardView)
        cardView.addSubview(previewLabel)
        cardView.addSubview(timeLabel)
        cardView.addSubview(deleteButton)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),

            previewLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 10),
            previewLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 12),
            previewLabel.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -8),

            timeLabel.topAnchor.constraint(equalTo: previewLabel.bottomAnchor, constant: 4),
            timeLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 12),
            timeLabel.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -10),

            deleteButton.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            deleteButton.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -12),
            deleteButton.widthAnchor.constraint(equalToConstant: 32),
            deleteButton.heightAnchor.constraint(equalToConstant: 32),
        ])

        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
    }

    @objc private func deleteTapped() {
        onDelete?()
    }

    func configure(text: String, time: String, isDark: Bool, theme: KeyboardTheme? = nil) {
        previewLabel.text = text
        timeLabel.text = time
        if let theme = theme {
            cardView.backgroundColor = theme.keyboardBackground
            previewLabel.textColor = theme.keyTextColor
            timeLabel.textColor = theme.keyTextColor.withAlphaComponent(0.5)
        } else {
            cardView.backgroundColor = isDark ? .systemGray5 : .systemGray6
            previewLabel.textColor = isDark ? .white : .label
            timeLabel.textColor = .secondaryLabel
        }
    }
}
