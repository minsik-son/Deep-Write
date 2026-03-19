import UIKit

class QuickNoteListView: UIView {

    // MARK: - Callbacks

    var onNoteTap: ((QuickNote) -> Void)?
    var onNewNote: (() -> Void)?
    var onDeleteNote: ((UUID) -> Void)?
    var onClose: (() -> Void)?

    // MARK: - Data

    private var notes: [QuickNote] = []

    // MARK: - UI

    private let headerView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.text = L("quicknote.title")
        l.font = .systemFont(ofSize: 16, weight: .bold)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let closeButton: UIButton = {
        let btn = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        btn.setImage(UIImage(systemName: "chevron.left", withConfiguration: config), for: .normal)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let addButton: UIButton = {
        let btn = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        btn.setImage(UIImage(systemName: "plus", withConfiguration: config), for: .normal)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .plain)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        tv.register(QuickNoteCell.self, forCellReuseIdentifier: QuickNoteCell.reuseId)
        tv.rowHeight = UITableView.automaticDimension
        tv.estimatedRowHeight = 60
        return tv
    }()

    private let emptyTitleLabel: UILabel = {
        let l = UILabel()
        l.text = L("quicknote.empty_title")
        l.font = .systemFont(ofSize: 15, weight: .medium)
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let emptySubtitleLabel: UILabel = {
        let l = UILabel()
        l.text = L("quicknote.empty_subtitle")
        l.font = .systemFont(ofSize: 13)
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    // MARK: - Theme

    private var customTheme: KeyboardTheme?
    private var isDark = false

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
        reloadNotes()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupViews() {
        addSubview(headerView)
        headerView.addSubview(closeButton)
        headerView.addSubview(titleLabel)
        headerView.addSubview(addButton)
        addSubview(tableView)
        addSubview(emptyTitleLabel)
        addSubview(emptySubtitleLabel)

        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        addButton.addTarget(self, action: #selector(addTapped), for: .touchUpInside)

        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .clear

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: topAnchor),
            headerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 44),

            closeButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 8),
            closeButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 36),
            closeButton.heightAnchor.constraint(equalToConstant: 34),

            titleLabel.leadingAnchor.constraint(equalTo: closeButton.trailingAnchor, constant: 4),
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            addButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -12),
            addButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            addButton.widthAnchor.constraint(equalToConstant: 36),
            addButton.heightAnchor.constraint(equalToConstant: 36),

            tableView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomAnchor),

            emptyTitleLabel.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            emptyTitleLabel.centerYAnchor.constraint(equalTo: tableView.centerYAnchor, constant: -10),
            emptySubtitleLabel.topAnchor.constraint(equalTo: emptyTitleLabel.bottomAnchor, constant: 4),
            emptySubtitleLabel.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
        ])
    }

    // MARK: - Public

    func reloadNotes() {
        notes = QuickNoteManager.shared.getAllNotes()
        tableView.reloadData()
        updateEmptyState()
    }

    func applyTheme(_ theme: KeyboardTheme?) {
        customTheme = theme
    }

    func updateAppearance(isDark: Bool) {
        self.isDark = isDark
        let textColor: UIColor
        let mutedColor: UIColor
        let bodyBg: UIColor

        if let theme = customTheme {
            backgroundColor = theme.keyboardBackground
            bodyBg = theme.keyBackground
            textColor = theme.keyTextColor
            mutedColor = theme.keyTextColor.withAlphaComponent(0.5)
            addButton.tintColor = theme.keyTextColor
            closeButton.tintColor = theme.keyTextColor
        } else {
            backgroundColor = isDark ? UIColor(white: 0.12, alpha: 1) : UIColor(white: 0.95, alpha: 1)
            bodyBg = isDark ? UIColor(white: 0.18, alpha: 1) : .white
            textColor = isDark ? .white : .label
            mutedColor = isDark ? UIColor(white: 0.5, alpha: 1) : .secondaryLabel
            addButton.tintColor = textColor
            closeButton.tintColor = textColor
        }

        tableView.backgroundColor = bodyBg
        titleLabel.textColor = textColor
        emptyTitleLabel.textColor = mutedColor
        emptySubtitleLabel.textColor = mutedColor
        tableView.reloadData()
    }

    // MARK: - Private

    private func updateEmptyState() {
        let empty = notes.isEmpty
        emptyTitleLabel.isHidden = !empty
        emptySubtitleLabel.isHidden = !empty
        tableView.isHidden = empty
    }

    @objc private func closeTapped() {
        onClose?()
    }

    @objc private func addTapped() {
        onNewNote?()
    }

    private func relativeTimeString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return L("quicknote.just_now") }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        return "\(Int(interval / 86400))d"
    }
}

// MARK: - UITableViewDataSource & Delegate

extension QuickNoteListView: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        notes.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: QuickNoteCell.reuseId, for: indexPath) as! QuickNoteCell
        let note = notes[indexPath.row]
        cell.configure(
            content: note.content,
            time: relativeTimeString(from: note.updatedAt),
            theme: customTheme,
            isDark: isDark
        )
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        onNoteTap?(notes[indexPath.row])
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let delete = UIContextualAction(style: .destructive, title: L("quicknote.delete")) { [weak self] _, _, completion in
            guard let self = self else { completion(false); return }
            let noteId = self.notes[indexPath.row].id
            self.onDeleteNote?(noteId)
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }
}

// MARK: - QuickNoteCell

private class QuickNoteCell: UITableViewCell {

    static let reuseId = "QuickNoteCell"

    private let contentLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 14)
        l.numberOfLines = 1
        l.lineBreakMode = .byTruncatingTail
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let timeLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 11)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupCell()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupCell() {
        contentView.addSubview(contentLabel)
        contentView.addSubview(timeLabel)

        NSLayoutConstraint.activate([
            contentLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            contentLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            contentLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            timeLabel.topAnchor.constraint(equalTo: contentLabel.bottomAnchor, constant: 2),
            timeLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            timeLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
        ])
    }

    func configure(content: String, time: String, theme: KeyboardTheme?, isDark: Bool) {
        contentLabel.text = content
        timeLabel.text = time

        if let theme = theme {
            backgroundColor = theme.keyBackground
            contentLabel.textColor = theme.keyTextColor
            timeLabel.textColor = theme.keyTextColor.withAlphaComponent(0.5)
        } else {
            backgroundColor = isDark ? UIColor(white: 0.18, alpha: 1) : .white
            contentLabel.textColor = isDark ? .white : .label
            timeLabel.textColor = isDark ? UIColor(white: 0.5, alpha: 1) : .secondaryLabel
        }
    }
}
