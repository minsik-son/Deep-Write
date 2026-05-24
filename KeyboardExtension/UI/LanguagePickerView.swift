import UIKit

// MARK: - Language Model

struct LanguageItem {
    let code: String
    let displayName: String
}

// MARK: - LanguagePickerView (Image 5 Reference)

class LanguagePickerView: UIView {

    enum Tab {
        case source  // 입력언어
        case target  // 번역언어
    }

    var onLanguageSelected: ((_ tab: Tab, _ language: LanguageItem) -> Void)?
    var onDismiss: (() -> Void)?

    private var currentTab: Tab = .source
    private var selectedSourceCode: String = "ko"
    private var selectedTargetCode: String = "en"
    private var isSingleLanguageMode = false
    private var showAutoRow = false
    private static let autoSentinel = "__auto_current_keyboard__"

    static var supportedLanguages: [LanguageItem] {
        [
            LanguageItem(code: "ko", displayName: L("lang.ko")),
            LanguageItem(code: "en", displayName: L("lang.en")),
            LanguageItem(code: "ja", displayName: L("lang.ja")),
            LanguageItem(code: "zh-CN", displayName: L("lang.zh_cn")),
            LanguageItem(code: "zh-TW", displayName: L("lang.zh_tw")),
            LanguageItem(code: "vi", displayName: L("lang.vi")),
            LanguageItem(code: "th", displayName: L("lang.th")),
            LanguageItem(code: "id", displayName: L("lang.id")),
            LanguageItem(code: "es", displayName: L("lang.es")),
            LanguageItem(code: "fr", displayName: L("lang.fr")),
            LanguageItem(code: "de", displayName: L("lang.de")),
            LanguageItem(code: "ru", displayName: L("lang.ru")),
            LanguageItem(code: "it", displayName: L("lang.it")),
        ]
    }

    // MARK: - UI Elements

    private let headerView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let sourceTabButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle(L("langpicker.source_tab"), for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let targetTabButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle(L("langpicker.target_tab"), for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let tabIndicator: UIView = {
        let v = UIView()
        v.backgroundColor = .white
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .plain)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.separatorStyle = .none
        tv.backgroundColor = .clear
        tv.rowHeight = 48
        return tv
    }()

    private let singleHeaderLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()

    private let closeButton: UIButton = {
        let btn = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        btn.setImage(UIImage(systemName: "xmark", withConfiguration: config), for: .normal)
        btn.tintColor = .white
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.isHidden = true
        return btn
    }()

    private var tabIndicatorLeading: NSLayoutConstraint?
    private var tabIndicatorWidth: NSLayoutConstraint?

    // MARK: - Theme color
    private let themeBlue = UIColor(red: 0.18, green: 0.50, blue: 0.93, alpha: 1.0)

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
        updateTabUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupViews() {
        backgroundColor = themeBlue
        clipsToBounds = true

        // Header with tabs
        addSubview(headerView)
        headerView.addSubview(sourceTabButton)
        headerView.addSubview(targetTabButton)
        headerView.addSubview(tabIndicator)
        headerView.addSubview(singleHeaderLabel)
        headerView.addSubview(closeButton)

        NSLayoutConstraint.activate([
            singleHeaderLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            singleHeaderLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            closeButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -12),
            closeButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 30),
            closeButton.heightAnchor.constraint(equalToConstant: 30),
        ])

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: topAnchor),
            headerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 44),

            sourceTabButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            sourceTabButton.topAnchor.constraint(equalTo: headerView.topAnchor),
            sourceTabButton.bottomAnchor.constraint(equalTo: headerView.bottomAnchor),
            sourceTabButton.widthAnchor.constraint(equalTo: headerView.widthAnchor, multiplier: 0.5),

            targetTabButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            targetTabButton.topAnchor.constraint(equalTo: headerView.topAnchor),
            targetTabButton.bottomAnchor.constraint(equalTo: headerView.bottomAnchor),
            targetTabButton.widthAnchor.constraint(equalTo: headerView.widthAnchor, multiplier: 0.5),

            tabIndicator.bottomAnchor.constraint(equalTo: headerView.bottomAnchor),
            tabIndicator.heightAnchor.constraint(equalToConstant: 3),
        ])

        tabIndicatorLeading = tabIndicator.leadingAnchor.constraint(equalTo: headerView.leadingAnchor)
        tabIndicatorWidth = tabIndicator.widthAnchor.constraint(equalTo: headerView.widthAnchor, multiplier: 0.5)
        tabIndicatorLeading?.isActive = true
        tabIndicatorWidth?.isActive = true

        // Table
        addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(LanguageCell.self, forCellReuseIdentifier: "LanguageCell")

        sourceTabButton.addTarget(self, action: #selector(sourceTabTapped), for: .touchUpInside)
        targetTabButton.addTarget(self, action: #selector(targetTabTapped), for: .touchUpInside)
        closeButton.addTarget(self, action: #selector(closeButtonTapped), for: .touchUpInside)

        // Tap outside header to dismiss
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped(_:)))
        tapGesture.cancelsTouchesInView = false
        addGestureRecognizer(tapGesture)
    }

    // MARK: - Public

    func configure(sourceCode: String, targetCode: String, initialTab: Tab = .source) {
        isSingleLanguageMode = false
        sourceTabButton.isHidden = false
        targetTabButton.isHidden = false
        tabIndicator.isHidden = false
        singleHeaderLabel.isHidden = true
        closeButton.isHidden = true
        selectedSourceCode = sourceCode
        selectedTargetCode = targetCode
        currentTab = initialTab
        updateTabUI()
        tableView.reloadData()
    }

    func configureSingleLanguage(code: String, title: String, showAutoRow: Bool = false) {
        isSingleLanguageMode = true
        self.showAutoRow = showAutoRow
        sourceTabButton.isHidden = true
        targetTabButton.isHidden = true
        tabIndicator.isHidden = true
        singleHeaderLabel.isHidden = false
        singleHeaderLabel.text = title
        closeButton.isHidden = false
        selectedSourceCode = code
        currentTab = .source
        tableView.reloadData()
    }

    // MARK: - Tab Switching

    @objc private func sourceTabTapped() {
        currentTab = .source
        updateTabUI()
        tableView.reloadData()
    }

    @objc private func targetTabTapped() {
        currentTab = .target
        updateTabUI()
        tableView.reloadData()
    }

    @objc private func closeButtonTapped() {
        onDismiss?()
    }

    @objc private func backgroundTapped(_ gesture: UITapGestureRecognizer) {
        // Only dismiss if tapped on header area (not table)
    }

    private func updateTabUI() {
        let activeColor = UIColor.white
        let inactiveColor = UIColor.white.withAlphaComponent(0.5)

        sourceTabButton.setTitleColor(currentTab == .source ? activeColor : inactiveColor, for: .normal)
        targetTabButton.setTitleColor(currentTab == .target ? activeColor : inactiveColor, for: .normal)

        UIView.animate(withDuration: 0.25) {
            if self.currentTab == .source {
                self.tabIndicatorLeading?.constant = 0
            } else {
                self.tabIndicatorLeading?.constant = self.bounds.width / 2
            }
            self.layoutIfNeeded()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if currentTab == .target {
            tabIndicatorLeading?.constant = bounds.width / 2
        }
    }
}

// MARK: - UITableViewDataSource & Delegate

extension LanguagePickerView: UITableViewDataSource, UITableViewDelegate {

    private var hasAutoRowInCurrentConfig: Bool {
        showAutoRow && isSingleLanguageMode
    }

    private func languageForRow(_ row: Int) -> LanguageItem? {
        if hasAutoRowInCurrentConfig {
            if row == 0 {
                return LanguageItem(code: Self.autoSentinel, displayName: L("keyboard.correction_language.auto_current_keyboard"))
            }
            let langIndex = row - 1
            guard langIndex < LanguagePickerView.supportedLanguages.count else { return nil }
            return LanguagePickerView.supportedLanguages[langIndex]
        }
        guard row < LanguagePickerView.supportedLanguages.count else { return nil }
        return LanguagePickerView.supportedLanguages[row]
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let base = LanguagePickerView.supportedLanguages.count
        return hasAutoRowInCurrentConfig ? base + 1 : base
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "LanguageCell", for: indexPath) as! LanguageCell
        guard let lang = languageForRow(indexPath.row) else { return cell }

        let selectedCode = currentTab == .source ? selectedSourceCode : selectedTargetCode
        let isSelected = lang.code == selectedCode

        cell.configure(name: lang.displayName, isChecked: isSelected)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let lang = languageForRow(indexPath.row) else { return }

        if currentTab == .source {
            selectedSourceCode = lang.code
        } else {
            selectedTargetCode = lang.code
        }

        tableView.reloadData()
        onLanguageSelected?(currentTab, lang)
    }
}

// MARK: - LanguageCell

private class LanguageCell: UITableViewCell {

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let checkImageView: UIImageView = {
        let iv = UIImageView()
        iv.tintColor = .white
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
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

        contentView.addSubview(nameLabel)
        contentView.addSubview(checkImageView)

        NSLayoutConstraint.activate([
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            nameLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            checkImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            checkImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            checkImageView.widthAnchor.constraint(equalToConstant: 22),
            checkImageView.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    func configure(name: String, isChecked: Bool) {
        nameLabel.text = name
        checkImageView.image = isChecked ? UIImage(systemName: "checkmark") : nil
        nameLabel.font = isChecked ? .systemFont(ofSize: 16, weight: .bold) : .systemFont(ofSize: 16)
    }
}
