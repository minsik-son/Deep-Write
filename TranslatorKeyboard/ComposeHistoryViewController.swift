import UIKit

class ComposeHistoryViewController: UIViewController {

    var onSelectItem: ((ComposeHistoryItem) -> Void)?

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let segmentedControl = UISegmentedControl(items: [L("ai_writer.history_all"), L("ai_writer.history_favorites")])
    private let emptyLabel = UILabel()
    private let emptySubLabel = UILabel()

    private var allItems: [ComposeHistoryItem] = []
    private var favoriteItems: [ComposeHistoryItem] = []
    private var showingFavorites = false

    private var displayedItems: [ComposeHistoryItem] {
        return showingFavorites ? favoriteItems : allItems
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColors.bg
        title = L("ai_writer.history_title")
        setupNavigation()
        setupUI()
        reloadData()
    }

    // MARK: - Setup

    private func setupNavigation() {
        let menuBtn = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            style: .plain,
            target: self,
            action: #selector(showMenu)
        )
        navigationItem.rightBarButtonItem = menuBtn
    }

    private func setupUI() {
        segmentedControl.selectedSegmentIndex = 0
        segmentedControl.selectedSegmentTintColor = AppColors.accent
        segmentedControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        segmentedControl.setTitleTextAttributes([.foregroundColor: AppColors.textMuted], for: .normal)
        segmentedControl.backgroundColor = AppColors.card
        segmentedControl.addTarget(self, action: #selector(segmentChanged(_:)), for: .valueChanged)
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false

        tableView.delegate = self
        tableView.dataSource = self
        tableView.backgroundColor = .clear
        tableView.register(ComposeHistoryCell.self, forCellReuseIdentifier: "HistoryCell")
        tableView.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.text = L("ai_writer.history_empty")
        emptyLabel.font = .systemFont(ofSize: 17, weight: .medium)
        emptyLabel.textColor = AppColors.textMuted
        emptyLabel.textAlignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        emptySubLabel.text = L("ai_writer.history_empty_sub")
        emptySubLabel.font = .systemFont(ofSize: 14)
        emptySubLabel.textColor = AppColors.textMuted
        emptySubLabel.textAlignment = .center
        emptySubLabel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(segmentedControl)
        view.addSubview(tableView)
        view.addSubview(emptyLabel)
        view.addSubview(emptySubLabel)

        NSLayoutConstraint.activate([
            segmentedControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            segmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            segmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            tableView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 12),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -10),
            emptySubLabel.topAnchor.constraint(equalTo: emptyLabel.bottomAnchor, constant: 6),
            emptySubLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])
    }

    // MARK: - Data

    func reloadData() {
        allItems = ComposeHistoryManager.shared.items
        favoriteItems = allItems.filter { $0.isFavorite }
        tableView.reloadData()
        updateEmptyState()
    }

    private func updateEmptyState() {
        let isEmpty = displayedItems.isEmpty
        emptyLabel.isHidden = !isEmpty
        emptySubLabel.isHidden = !isEmpty
        tableView.isHidden = isEmpty
    }

    // MARK: - Actions

    @objc private func segmentChanged(_ sender: UISegmentedControl) {
        showingFavorites = sender.selectedSegmentIndex == 1
        tableView.reloadData()
        updateEmptyState()
    }

    @objc private func showMenu() {
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        let historyEnabled = ComposeHistoryManager.shared.isEnabled
        let toggleTitle = historyEnabled ? L("ai_writer.history_disable") : L("ai_writer.history_enable")
        alert.addAction(UIAlertAction(title: toggleTitle, style: .default) { _ in
            ComposeHistoryManager.shared.isEnabled = !historyEnabled
        })

        alert.addAction(UIAlertAction(title: L("ai_writer.history_clear_confirm"), style: .destructive) { [weak self] _ in
            self?.showClearAllConfirmation()
        })

        alert.addAction(UIAlertAction(title: L("common.cancel"), style: .cancel))
        present(alert, animated: true)
    }

    @objc private func showClearAllConfirmation() {
        let alert = UIAlertController(
            title: L("ai_writer.history_clear_title"),
            message: L("ai_writer.history_clear_message"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L("common.cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: L("ai_writer.history_clear_confirm"), style: .destructive) { [weak self] _ in
            ComposeHistoryManager.shared.clearAll()
            self?.reloadData()
        })
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource & Delegate

extension ComposeHistoryViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return displayedItems.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "HistoryCell", for: indexPath) as! ComposeHistoryCell
        let item = displayedItems[indexPath.row]
        cell.configure(with: item)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = displayedItems[indexPath.row]
        onSelectItem?(item)
        navigationController?.popViewController(animated: true)
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let item = displayedItems[indexPath.row]

        let favoriteAction = UIContextualAction(style: .normal, title: item.isFavorite ? "Unfav" : "Fav") { [weak self] _, _, completion in
            ComposeHistoryManager.shared.toggleFavorite(id: item.id)
            self?.reloadData()
            completion(true)
        }
        favoriteAction.backgroundColor = .systemYellow

        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            ComposeHistoryManager.shared.deleteItem(id: item.id)
            self?.reloadData()
            completion(true)
        }

        let copyAction = UIContextualAction(style: .normal, title: "Copy") { _, _, completion in
            UIPasteboard.general.string = item.result
            completion(true)
        }
        copyAction.backgroundColor = .systemBlue

        return UISwipeActionsConfiguration(actions: [deleteAction, favoriteAction, copyAction])
    }
}

// MARK: - ComposeHistoryCell

class ComposeHistoryCell: UITableViewCell {

    private let promptLabel = UILabel()
    private let resultPreview = UILabel()
    private let tonePill = UILabel()
    private let timeLabel = UILabel()
    private let favIcon = UIImageView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupCell()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupCell() {
        backgroundColor = AppColors.card

        promptLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        promptLabel.textColor = AppColors.text
        promptLabel.numberOfLines = 1

        resultPreview.font = .systemFont(ofSize: 13)
        resultPreview.textColor = AppColors.textSub
        resultPreview.numberOfLines = 2

        tonePill.font = .systemFont(ofSize: 11, weight: .medium)
        tonePill.textColor = AppColors.accent
        tonePill.backgroundColor = AppColors.accent.withAlphaComponent(0.1)
        tonePill.layer.cornerRadius = 8
        tonePill.clipsToBounds = true
        tonePill.textAlignment = .center

        timeLabel.font = .systemFont(ofSize: 11)
        timeLabel.textColor = AppColors.textMuted

        favIcon.tintColor = .systemYellow
        favIcon.contentMode = .scaleAspectFit

        let views: [UIView] = [promptLabel, resultPreview, tonePill, timeLabel, favIcon]
        views.forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }

        NSLayoutConstraint.activate([
            favIcon.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            favIcon.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            favIcon.widthAnchor.constraint(equalToConstant: 16),
            favIcon.heightAnchor.constraint(equalToConstant: 16),

            promptLabel.leadingAnchor.constraint(equalTo: favIcon.trailingAnchor, constant: 8),
            promptLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            promptLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),

            tonePill.leadingAnchor.constraint(equalTo: promptLabel.leadingAnchor),
            tonePill.topAnchor.constraint(equalTo: promptLabel.bottomAnchor, constant: 4),
            tonePill.widthAnchor.constraint(greaterThanOrEqualToConstant: 40),
            tonePill.heightAnchor.constraint(equalToConstant: 18),

            timeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            timeLabel.centerYAnchor.constraint(equalTo: tonePill.centerYAnchor),

            resultPreview.leadingAnchor.constraint(equalTo: promptLabel.leadingAnchor),
            resultPreview.topAnchor.constraint(equalTo: tonePill.bottomAnchor, constant: 6),
            resultPreview.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            resultPreview.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
        ])
    }

    func configure(with item: ComposeHistoryItem) {
        promptLabel.text = item.prompt
        resultPreview.text = item.result
        tonePill.text = "  \(item.tone)  "
        favIcon.image = UIImage(systemName: item.isFavorite ? "star.fill" : "star")

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        timeLabel.text = formatter.localizedString(for: item.timestamp, relativeTo: Date())
    }
}
