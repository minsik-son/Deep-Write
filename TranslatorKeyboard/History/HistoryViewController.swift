import UIKit

class HistoryViewController: UIViewController {

    private var allItems: [HistoryItem] = []
    private var filteredItems: [HistoryItem] = []
    private var groupedItems: [(title: String, items: [HistoryItem])] = []
    private var selectedFilter: HistoryType?

    private let filterStack = UIStackView()
    private let tableView = UITableView(frame: .zero, style: .grouped)
    private let emptyLabel = UILabel()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColors.bg
        title = L("history.title")
        setupNavigation()
        setupFilterBar()
        setupTableView()
        setupEmptyState()
        NotificationCenter.default.addObserver(self, selector: #selector(handleLanguageChange), name: .languageDidChange, object: nil)
    }

    @objc private func handleLanguageChange() {
        title = L("history.title")
        let filterTitles = [L("history.filter.all"), L("history.filter.translate"), L("history.filter.correct"), L("history.filter.clipboard")]
        for (i, view) in filterStack.arrangedSubviews.enumerated() {
            if let btn = view as? UIButton, i < filterTitles.count {
                btn.setTitle(filterTitles[i], for: .normal)
            }
        }
        emptyLabel.text = L("history.empty")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadData()
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
    }

    private func setupFilterBar() {
        filterStack.axis = .horizontal
        filterStack.spacing = 8
        filterStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(filterStack)
        NSLayoutConstraint.activate([
            filterStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            filterStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
        ])

        let filters: [(String, HistoryType?)] = [
            (L("history.filter.all"), nil),
            (L("history.filter.translate"), .translation),
            (L("history.filter.correct"), .correction),
            (L("history.filter.clipboard"), .clipboard),
        ]

        for (i, filter) in filters.enumerated() {
            let btn = UIButton(type: .system)
            btn.setTitle(filter.0, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
            btn.layer.cornerRadius = 16
            btn.clipsToBounds = true
            btn.contentEdgeInsets = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
            btn.tag = i
            btn.addTarget(self, action: #selector(filterTapped(_:)), for: .touchUpInside)
            filterStack.addArrangedSubview(btn)
        }

        updateFilterAppearance()
    }

    private func setupTableView() {
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(HistoryCell.self, forCellReuseIdentifier: "HistoryCell")
        tableView.sectionHeaderTopPadding = 0
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: filterStack.bottomAnchor, constant: 12),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func setupEmptyState() {
        emptyLabel.text = L("history.empty")
        emptyLabel.font = .systemFont(ofSize: 15)
        emptyLabel.textColor = AppColors.textMuted
        emptyLabel.textAlignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    // MARK: - Actions

    func selectFilter(_ type: HistoryType?) {
        selectedFilter = type
        updateFilterAppearance()
        reloadData()
    }

    @objc private func filterTapped(_ sender: UIButton) {
        let filters: [HistoryType?] = [nil, .translation, .correction, .clipboard]
        selectedFilter = filters[sender.tag]
        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseOut) {
            self.updateFilterAppearance()
        }
        applyFilter()
    }

    private func updateFilterAppearance() {
        let filters: [HistoryType?] = [nil, .translation, .correction, .clipboard]
        for case let btn as UIButton in filterStack.arrangedSubviews {
            let isSelected = filters[btn.tag] == selectedFilter
            if isSelected {
                btn.backgroundColor = AppColors.accent
                btn.setTitleColor(.white, for: .normal)
                btn.transform = CGAffineTransform(scaleX: 1.04, y: 1.04)
            } else {
                btn.backgroundColor = AppColors.card
                btn.setTitleColor(AppColors.textMuted, for: .normal)
                btn.transform = .identity
            }
            btn.layer.borderWidth = 0
        }
    }

    private func reloadData() {
        allItems = HistoryManager.shared.loadItems()
        applyFilter()
    }

    private func applyFilter() {
        if let filter = selectedFilter {
            filteredItems = allItems.filter { $0.type == filter }
        } else {
            filteredItems = allItems
        }
        groupedItems = groupItemsByDate(filteredItems)
        tableView.reloadData()
        emptyLabel.isHidden = !filteredItems.isEmpty
        tableView.isHidden = filteredItems.isEmpty
    }

    // MARK: - Date Grouping

    private func groupItemsByDate(_ items: [HistoryItem]) -> [(title: String, items: [HistoryItem])] {
        let calendar = Calendar.current

        var groups: [String: [HistoryItem]] = [:]
        var orderedKeys: [String] = []

        for item in items {
            let key: String
            if calendar.isDateInToday(item.createdAt) {
                key = L("history.date.today")
            } else if calendar.isDateInYesterday(item.createdAt) {
                key = L("history.date.yesterday")
            } else {
                let formatter = DateFormatter()
                formatter.locale = Locale.current
                let currentLang = LocalizationManager.shared.currentLanguage
                switch currentLang {
                case .ko:
                    formatter.dateFormat = "M월 d일"
                case .ja:
                    formatter.dateFormat = "M月d日"
                case .zhHans:
                    formatter.dateFormat = "M月d日"
                default:
                    formatter.dateFormat = "MMM d"
                }
                key = formatter.string(from: item.createdAt)
            }

            if groups[key] == nil {
                groups[key] = []
                orderedKeys.append(key)
            }
            groups[key]?.append(item)
        }

        return orderedKeys.compactMap { key in
            guard let items = groups[key] else { return nil }
            return (title: key, items: items)
        }
    }

    // MARK: - Relative Time

    private func relativeTime(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return L("clipboard.time.now") }
        if interval < 3600 { return String(format: L("clipboard.time.minutes_ago"), Int(interval / 60)) }
        if interval < 86400 { return String(format: L("clipboard.time.hours_ago"), Int(interval / 3600)) }
        return String(format: L("clipboard.time.days_ago"), Int(interval / 86400))
    }
}

// MARK: - UITableViewDataSource & Delegate

extension HistoryViewController: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int {
        groupedItems.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        groupedItems[section].items.count
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let header = UIView()
        header.backgroundColor = .clear

        let label = UILabel()
        label.text = groupedItems[section].title
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = AppColors.textMuted
        label.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -20),
            label.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -6),
        ])

        return header
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        36
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        nil
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "HistoryCell", for: indexPath) as! HistoryCell
        let item = groupedItems[indexPath.section].items[indexPath.row]
        cell.configure(with: item, relativeTime: relativeTime(from: item.createdAt))
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = groupedItems[indexPath.section].items[indexPath.row]
        let textToCopy = item.resultText ?? item.originalText
        UIPasteboard.general.string = textToCopy

        let toast = UILabel()
        toast.text = L("ai_writer.copied")
        toast.font = .systemFont(ofSize: 13, weight: .medium)
        toast.textColor = .white
        toast.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        toast.textAlignment = .center
        toast.layer.cornerRadius = 8
        toast.clipsToBounds = true
        toast.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toast)
        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toast.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            toast.widthAnchor.constraint(greaterThanOrEqualToConstant: 100),
            toast.heightAnchor.constraint(equalToConstant: 32),
        ])
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            toast.removeFromSuperview()
        }
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let delete = UIContextualAction(style: .destructive, title: nil) { [weak self] _, _, completion in
            guard let self else { completion(false); return }
            let item = self.groupedItems[indexPath.section].items[indexPath.row]
            HistoryManager.shared.deleteItem(id: item.id)
            self.reloadData()
            completion(true)
        }
        delete.image = UIImage(systemName: "trash")
        return UISwipeActionsConfiguration(actions: [delete])
    }
}

// MARK: - HistoryCell

class HistoryCell: UITableViewCell {

    private let cardView = UIView()
    private let tagLabel = UILabel()
    private let timeLabel = UILabel()
    private let originalLabel = UILabel()
    private let separator = UIView()
    private let resultLabel = UILabel()

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

        cardView.backgroundColor = AppColors.card
        cardView.layer.cornerRadius = 16
        cardView.layer.borderWidth = 1
        cardView.layer.borderColor = AppColors.border.cgColor
        cardView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cardView)

        tagLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        tagLabel.textColor = .white
        tagLabel.layer.cornerRadius = 6
        tagLabel.clipsToBounds = true
        tagLabel.textAlignment = .center
        tagLabel.translatesAutoresizingMaskIntoConstraints = false

        timeLabel.font = .systemFont(ofSize: 12)
        timeLabel.textColor = AppColors.textMuted
        timeLabel.translatesAutoresizingMaskIntoConstraints = false

        originalLabel.font = .systemFont(ofSize: 14)
        originalLabel.textColor = AppColors.text
        originalLabel.numberOfLines = 2
        originalLabel.translatesAutoresizingMaskIntoConstraints = false

        separator.backgroundColor = AppColors.border
        separator.translatesAutoresizingMaskIntoConstraints = false

        resultLabel.font = .systemFont(ofSize: 15, weight: .medium)
        resultLabel.textColor = AppColors.text
        resultLabel.numberOfLines = 2
        resultLabel.translatesAutoresizingMaskIntoConstraints = false

        cardView.addSubview(tagLabel)
        cardView.addSubview(timeLabel)
        cardView.addSubview(originalLabel)
        cardView.addSubview(separator)
        cardView.addSubview(resultLabel)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),

            tagLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 12),
            tagLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 14),
            tagLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 40),
            tagLabel.heightAnchor.constraint(equalToConstant: 20),

            timeLabel.centerYAnchor.constraint(equalTo: tagLabel.centerYAnchor),
            timeLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -14),

            originalLabel.topAnchor.constraint(equalTo: tagLabel.bottomAnchor, constant: 10),
            originalLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 14),
            originalLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -14),

            separator.topAnchor.constraint(equalTo: originalLabel.bottomAnchor, constant: 8),
            separator.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 14),
            separator.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -14),
            separator.heightAnchor.constraint(equalToConstant: 0.5),

            resultLabel.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 8),
            resultLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 14),
            resultLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -14),
            resultLabel.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -12),
        ])
    }

    func configure(with item: HistoryItem, relativeTime: String) {
        timeLabel.text = relativeTime
        originalLabel.text = item.originalText

        switch item.type {
        case .translation:
            tagLabel.text = " \(item.metadata ?? "KO \u{2192} EN") "
            tagLabel.backgroundColor = AppColors.accent
            originalLabel.textColor = AppColors.textSub
            resultLabel.text = item.resultText
            separator.isHidden = false
            resultLabel.isHidden = false
        case .correction:
            tagLabel.text = " \(item.metadata ?? L("home.stat.corrections")) "
            tagLabel.backgroundColor = AppColors.orange
            originalLabel.textColor = AppColors.textSub
            resultLabel.text = item.resultText
            separator.isHidden = false
            resultLabel.isHidden = false
        case .clipboard:
            tagLabel.text = " \(item.metadata ?? "Text") "
            tagLabel.backgroundColor = AppColors.green
            originalLabel.textColor = AppColors.text
            separator.isHidden = true
            resultLabel.isHidden = true
        }
    }
}
