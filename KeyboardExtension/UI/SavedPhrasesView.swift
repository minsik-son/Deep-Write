import UIKit

class SavedPhrasesView: UIView {

    var onPhraseSelected: ((String) -> Void)?
    var onAddPhrase: (() -> Void)?
    var onDismiss: (() -> Void)?

    private var phrases: [String] = []
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

    private let addButton: UIButton = {
        let btn = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        btn.setImage(UIImage(systemName: "plus", withConfiguration: config), for: .normal)
        btn.tintColor = .label
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = L("savedphrases.title")
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = .label
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .plain)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        tv.rowHeight = UITableView.automaticDimension
        tv.estimatedRowHeight = 44
        return tv
    }()

    private let emptyLabel: UILabel = {
        let label = UILabel()
        label.text = L("savedphrases.empty")
        label.font = .systemFont(ofSize: 15)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()

    private let emptyAddButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle(L("savedphrases.add"), for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.isHidden = true
        return btn
    }()

    private let headerSeparator: UIView = {
        let v = UIView()
        v.backgroundColor = .separator
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
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
        headerView.addSubview(addButton)
        addSubview(headerSeparator)
        addSubview(tableView)
        addSubview(emptyLabel)
        addSubview(emptyAddButton)

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

            addButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -12),
            addButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            addButton.widthAnchor.constraint(equalToConstant: 36),
            addButton.heightAnchor.constraint(equalToConstant: 36),

            headerSeparator.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            headerSeparator.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerSeparator.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerSeparator.heightAnchor.constraint(equalToConstant: 0.5),

            tableView.topAnchor.constraint(equalTo: headerSeparator.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -16),

            emptyAddButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyAddButton.topAnchor.constraint(equalTo: emptyLabel.bottomAnchor, constant: 12),
        ])

        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "PhraseCell")

        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        addButton.addTarget(self, action: #selector(addTapped), for: .touchUpInside)
        emptyAddButton.addTarget(self, action: #selector(addTapped), for: .touchUpInside)
    }

    // MARK: - Actions

    @objc private func closeTapped() { onDismiss?() }
    @objc private func addTapped() { onAddPhrase?() }

    // MARK: - Public

    func reloadData() {
        phrases = SavedPhrasesManager.shared.getPhrases()
        tableView.reloadData()
        updateEmptyState()
    }

    func applyTheme(_ theme: KeyboardTheme?) {
        customTheme = theme
    }

    func updateAppearance(isDark: Bool) {
        self.isDark = isDark
        let bg: UIColor
        let bodyBg: UIColor
        let textColor: UIColor
        let mutedColor: UIColor

        if let theme = customTheme {
            bg = theme.keyboardBackground
            bodyBg = theme.keyBackground
            textColor = theme.keyTextColor
            mutedColor = theme.keyTextColor.withAlphaComponent(0.5)
        } else {
            bg = isDark ? UIColor(white: 0.12, alpha: 1) : UIColor(white: 0.95, alpha: 1)
            bodyBg = isDark ? UIColor(white: 0.18, alpha: 1) : .white
            textColor = isDark ? .white : .label
            mutedColor = isDark ? UIColor(white: 0.5, alpha: 1) : .secondaryLabel
        }

        backgroundColor = bg
        headerView.backgroundColor = bg
        tableView.backgroundColor = bodyBg
        titleLabel.textColor = textColor
        closeButton.tintColor = textColor
        addButton.tintColor = textColor
        emptyLabel.textColor = mutedColor
        tableView.reloadData()
    }

    // MARK: - Private

    private func updateEmptyState() {
        let isEmpty = phrases.isEmpty
        emptyLabel.isHidden = !isEmpty
        emptyAddButton.isHidden = !isEmpty
        tableView.isHidden = isEmpty
    }
}

// MARK: - UITableViewDataSource

extension SavedPhrasesView: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return phrases.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "PhraseCell", for: indexPath)
        cell.textLabel?.text = phrases[indexPath.row]
        cell.textLabel?.font = .systemFont(ofSize: 15)
        cell.textLabel?.numberOfLines = 2
        cell.textLabel?.lineBreakMode = .byTruncatingTail
        cell.selectionStyle = .default
        if let theme = customTheme {
            cell.backgroundColor = theme.keyBackground
            cell.textLabel?.textColor = theme.keyTextColor
            let selectedBg = UIView()
            selectedBg.backgroundColor = theme.keyTextColor.withAlphaComponent(0.1)
            cell.selectedBackgroundView = selectedBg
        } else {
            cell.backgroundColor = isDark ? UIColor(white: 0.18, alpha: 1) : .white
            cell.textLabel?.textColor = isDark ? .white : .label
            cell.selectedBackgroundView = nil
        }
        return cell
    }
}

// MARK: - UITableViewDelegate

extension SavedPhrasesView: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let phrase = phrases[indexPath.row]
        onPhraseSelected?(phrase)
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let deleteAction = UIContextualAction(style: .destructive, title: L("savedphrases.delete")) { [weak self] _, _, completionHandler in
            SavedPhrasesManager.shared.deletePhrase(at: indexPath.row)
            self?.phrases.remove(at: indexPath.row)
            tableView.deleteRows(at: [indexPath], with: .automatic)
            self?.updateEmptyState()
            completionHandler(true)
        }
        return UISwipeActionsConfiguration(actions: [deleteAction])
    }
}
