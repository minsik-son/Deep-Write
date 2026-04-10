import UIKit
import StoreKit

// MARK: - Notification Names

extension Notification.Name {
    static let subscriptionStatusDidChange = Notification.Name("subscriptionStatusDidChange")
}

class SettingsViewController: UITableViewController {

    // MARK: - Data Model

    private enum AccessoryType {
        case chevron
        case toggle(key: String)
        case planBanner
        case subscriptionStatus
    }

    private var toggleKeyMap: [Int: String] = [:]
    private var isRestoringPurchases = false

    private struct SettingsItem {
        let title: String
        let iconName: String
        let iconBackgroundColor: UIColor
        let accessory: AccessoryType
    }

    private var sections: [(title: String?, items: [SettingsItem])] {
        var result: [(title: String?, items: [SettingsItem])] = []

        let tier = SubscriptionStatus.shared.currentTier
        if tier == .pro || tier == .premium {
            // Pro/Premium: PlanBanner 대신 Subscription 카드를 헤더 없이 최상단 배치
            result.append((
                title: nil,
                items: [
                    SettingsItem(title: "", iconName: "", iconBackgroundColor: .clear, accessory: .subscriptionStatus),
                    SettingsItem(title: L("settings.manage_subscription"), iconName: "gear", iconBackgroundColor: AppColors.tierAccent, accessory: .chevron),
                    SettingsItem(title: L("settings.restore_purchases"), iconName: "arrow.counterclockwise", iconBackgroundColor: .systemGray, accessory: .chevron),
                ]
            ))
        } else {
            // Free: 기존 PlanBanner 유지
            result.append((
                title: nil,
                items: [
                    SettingsItem(title: "", iconName: "", iconBackgroundColor: .clear, accessory: .planBanner),
                ]
            ))
        }

        // 나머지 섹션
        result.append(contentsOf: [
            // Appearance
            (
                title: L("settings.section.appearance"),
                items: [
                    SettingsItem(title: L("settings.dark_mode"), iconName: "moon", iconBackgroundColor: UIColor(red: 0.345, green: 0.337, blue: 0.839, alpha: 1), accessory: .toggle(key: AppConstants.UserDefaultsKeys.appDarkMode)),
                ]
            ),
            // Keyboard
            (
                title: L("settings.section.keyboard"),
                items: [
                    SettingsItem(title: L("settings.language"), iconName: "globe", iconBackgroundColor: AppColors.tierAccent, accessory: .chevron),
                    SettingsItem(title: L("settings.layout"), iconName: "keyboard", iconBackgroundColor: AppColors.green, accessory: .chevron),
                    SettingsItem(title: L("settings.keyboard_appearance"), iconName: "circle.lefthalf.filled", iconBackgroundColor: .systemIndigo, accessory: .chevron),
                    SettingsItem(title: L("settings.toolbar"), iconName: "slider.horizontal.3", iconBackgroundColor: .systemOrange, accessory: .chevron),
                    SettingsItem(title: L("settings.autocomplete"), iconName: "text.badge.checkmark", iconBackgroundColor: .systemGreen, accessory: .toggle(key: AppConstants.UserDefaultsKeys.autoComplete)),
                    SettingsItem(title: L("settings.auto_capitalize"), iconName: "textformat.size", iconBackgroundColor: AppColors.tierBlue, accessory: .toggle(key: AppConstants.UserDefaultsKeys.autoCapitalize)),
                    SettingsItem(title: L("settings.haptic"), iconName: "iphone.radiowaves.left.and.right", iconBackgroundColor: AppColors.pink, accessory: .toggle(key: AppConstants.UserDefaultsKeys.hapticFeedback)),
                    SettingsItem(title: L("settings.quick_notes"), iconName: "note.text", iconBackgroundColor: .systemYellow, accessory: .chevron),
                ]
            ),
            // AI
            (
                title: L("settings.section.ai"),
                items: [
                    SettingsItem(title: L("settings.ai_correction"), iconName: "wand.and.stars", iconBackgroundColor: AppColors.tierAccent, accessory: .chevron),
                    SettingsItem(title: L("settings.ai_translation"), iconName: "arrow.right.arrow.left", iconBackgroundColor: AppColors.green, accessory: .chevron),
                ]
            ),
            // Privacy
            (
                title: L("settings.section.privacy"),
                items: [
                    SettingsItem(title: L("settings.privacy_dashboard"), iconName: "shield.checkered", iconBackgroundColor: AppColors.green, accessory: .chevron),
                    SettingsItem(title: L("settings.full_access_explain"), iconName: "lock.open", iconBackgroundColor: AppColors.tierAccent, accessory: .chevron),
                ]
            ),
            // About
            (
                title: L("settings.section.about"),
                items: [
                    SettingsItem(title: L("settings.redo_onboarding"), iconName: "arrow.counterclockwise", iconBackgroundColor: .systemBlue, accessory: .chevron),
                    SettingsItem(title: L("settings.paste_guide"), iconName: "doc.on.clipboard", iconBackgroundColor: .systemTeal, accessory: .chevron),
                    SettingsItem(title: L("settings.rate_us"), iconName: "star", iconBackgroundColor: .systemRed, accessory: .chevron),
                    SettingsItem(title: L("settings.faq"), iconName: "questionmark.circle", iconBackgroundColor: .systemGray, accessory: .chevron),
                    SettingsItem(title: L("settings.privacy"), iconName: "hand.raised.fill", iconBackgroundColor: .systemGreen, accessory: .chevron),
                    SettingsItem(title: L("settings.terms"), iconName: "doc.text", iconBackgroundColor: .systemGray, accessory: .chevron),
                ]
            ),
        ])

        return result
    }

    // MARK: - Admin Mode

    private var versionTapCount = 0
    private var versionTapTimer: Timer?

    private lazy var versionFooterView: UIView = {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 60))

        let label = UILabel()
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        label.text = "Translator Keyboard v\(version) (\(build))"
        label.font = .systemFont(ofSize: 13)
        label.textColor = AppColors.textMuted
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isUserInteractionEnabled = true

        let tap = UITapGestureRecognizer(target: self, action: #selector(versionLabelTapped))
        label.addGestureRecognizer(tap)

        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        return container
    }()

    // MARK: - Lifecycle

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = L("settings.title")
        navigationController?.navigationBar.prefersLargeTitles = false

        let titleFont = UIFont.boldSystemFont(ofSize: 18)
        navigationController?.navigationBar.titleTextAttributes = [.font: titleFont]

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "SettingsCell")
        tableView.register(PlanBannerCell.self, forCellReuseIdentifier: PlanBannerCell.reuseIdentifier)
        tableView.register(SubscriptionStatusCell.self, forCellReuseIdentifier: SubscriptionStatusCell.reuseIdentifier)
        tableView.tableFooterView = versionFooterView

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSubscriptionStatusChanged),
            name: .subscriptionStatusDidChange,
            object: nil
        )
    }

    @objc private func handleSubscriptionStatusChanged() {
        toggleKeyMap.removeAll()
        tableView.reloadData()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationItem.title = L("settings.title")
        updateAdminBadge()
        toggleKeyMap.removeAll()
        tableView.reloadData()
    }

    // MARK: - UITableViewDataSource

    override func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].items.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section].title
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = sections[indexPath.section].items[indexPath.row]

        if case .planBanner = item.accessory {
            let cell = tableView.dequeueReusableCell(withIdentifier: PlanBannerCell.reuseIdentifier, for: indexPath) as! PlanBannerCell
            cell.selectionStyle = .none
            return cell
        }

        if case .subscriptionStatus = item.accessory {
            let cell = tableView.dequeueReusableCell(withIdentifier: SubscriptionStatusCell.reuseIdentifier, for: indexPath) as! SubscriptionStatusCell
            cell.updateStatus()
            cell.selectionStyle = .none
            return cell
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: "SettingsCell", for: indexPath)

        var config = cell.defaultContentConfiguration()
        config.text = item.title
        config.image = makeIcon(symbolName: item.iconName, backgroundColor: item.iconBackgroundColor)
        cell.contentConfiguration = config

        switch item.accessory {
        case .chevron:
            cell.accessoryType = .disclosureIndicator
            cell.accessoryView = nil
            cell.selectionStyle = .default
        case .toggle(let key):
            let toggle = UISwitch()
            let defaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier)
            let defaultValue: Bool
            if key == AppConstants.UserDefaultsKeys.appDarkMode {
                defaultValue = false
            } else if key == AppConstants.UserDefaultsKeys.autoComplete {
                defaultValue = false
            } else {
                defaultValue = true
            }
            toggle.isOn = defaults?.object(forKey: key) == nil ? defaultValue : AppGroupManager.shared.bool(forKey: key)
            toggle.tag = indexPath.section * 100 + indexPath.row
            toggleKeyMap[toggle.tag] = key
            toggle.addTarget(self, action: #selector(toggleChanged(_:)), for: .valueChanged)
            cell.accessoryType = .none
            cell.accessoryView = toggle
            cell.selectionStyle = .none
        case .planBanner, .subscriptionStatus:
            break
        }

        return cell
    }

    // MARK: - UITableViewDelegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let sectionTitle = sections[indexPath.section].title
        let item = sections[indexPath.section].items[indexPath.row]

        // Plan Banner
        if case .planBanner = item.accessory {
            let paywall = PaywallViewController()
            paywall.modalPresentationStyle = .fullScreen
            present(paywall, animated: true)
            return
        }

        // Subscription Status cell — no action
        if case .subscriptionStatus = item.accessory {
            return
        }

        var vc: UIViewController?

        // Subscription section — title이 nil이므로 accessory 기반 판별
        if case .subscriptionStatus = sections[indexPath.section].items.first?.accessory {
            switch indexPath.row {
            case 1: manageSubscriptionTapped()
            case 2: restorePurchasesTapped()
            default: break
            }
            return
        }

        // Keyboard section
        if sectionTitle == L("settings.section.keyboard") {
            switch indexPath.row {
            case 0: vc = LanguageSettingsViewController()
            case 1: vc = LayoutSettingsViewController()
            case 2: vc = KeyboardAppearanceSettingsViewController()
            case 3: vc = ToolbarCustomizationViewController()
            case 7: vc = QuickNoteListViewController()
            default: break
            }
        }

        // AI section
        if sectionTitle == L("settings.section.ai") {
            switch indexPath.row {
            case 0: vc = AICorrectionInfoViewController()
            case 1: vc = AITranslationInfoViewController()
            default: break
            }
        }

        // Privacy section
        if sectionTitle == L("settings.section.privacy") {
            switch indexPath.row {
            case 0: vc = PrivacyDashboardViewController()
            case 1: vc = FullAccessExplainViewController()
            default: break
            }
        }

        // About section
        if sectionTitle == L("settings.section.about") {
            switch indexPath.row {
            case 0:
                let defaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier) ?? UserDefaults.standard
                defaults.set(false, forKey: AppConstants.UserDefaultsKeys.hasCompletedOnboarding)
                let onboarding = OnboardingViewController()
                onboarding.modalPresentationStyle = .fullScreen
                present(onboarding, animated: true)
            case 1: vc = PasteGuideViewController()
            case 2:
                if let url = URL(string: "itms-apps://itunes.apple.com/app/id\(AppConstants.mainBundleIdentifier)") {
                    UIApplication.shared.open(url)
                }
            case 3:
                if let url = URL(string: LegalLinks.faq) {
                    UIApplication.shared.open(url)
                }
            case 4:
                if let url = URL(string: LegalLinks.privacy) {
                    UIApplication.shared.open(url)
                }
            case 5:
                if let url = URL(string: LegalLinks.terms) {
                    UIApplication.shared.open(url)
                }
            default: break
            }
        }

        if let vc = vc {
            navigationController?.pushViewController(vc, animated: true)
        }
    }

    // MARK: - Actions

    @objc private func toggleChanged(_ sender: UISwitch) {
        guard let key = toggleKeyMap[sender.tag] else { return }
        AppGroupManager.shared.set(sender.isOn, forKey: key)
        if key == AppConstants.UserDefaultsKeys.appDarkMode {
            view.window?.overrideUserInterfaceStyle = sender.isOn ? .dark : .light
        }
    }

    // MARK: - Subscription Management

    @MainActor
    private func manageSubscriptionTapped() {
        if #available(iOS 15.0, *) {
            guard let windowScene = view.window?.windowScene else {
                openSubscriptionManagementURL()
                return
            }
            Task {
                do {
                    try await AppStore.showManageSubscriptions(in: windowScene)
                } catch {
                    openSubscriptionManagementURL()
                }
            }
        } else {
            openSubscriptionManagementURL()
        }
    }

    private func openSubscriptionManagementURL() {
        if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
            UIApplication.shared.open(url)
        }
    }

    private func restorePurchasesTapped() {
        guard !isRestoringPurchases else { return }

        let alert = UIAlertController(
            title: L("settings.restore.title"),
            message: L("settings.restore.message"),
            preferredStyle: .alert
        )

        let restoreAction = UIAlertAction(title: L("settings.restore.confirm"), style: .default) { [weak self] _ in
            guard let self = self else { return }
            self.isRestoringPurchases = true

            Task { @MainActor in
                defer { self.isRestoringPurchases = false }
                do {
                    try await StoreKitManager.shared.restorePurchases()
                    self.toggleKeyMap.removeAll()
                    self.tableView.reloadData()
                    self.showRestoreResult()
                } catch {
                    self.showRestoreError()
                }
            }
        }

        alert.addAction(restoreAction)
        alert.addAction(UIAlertAction(title: L("common.cancel"), style: .cancel))
        present(alert, animated: true)
    }

    private func showRestoreResult() {
        let tier = SubscriptionStatus.shared.currentTier
        let message: String
        if tier == .free {
            message = L("settings.restore.no_subscription")
        } else {
            message = String(format: L("settings.restore.success"), L("home.plan.\(tier.rawValue)"))
        }

        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L("common.ok"), style: .default))
        present(alert, animated: true)
    }

    private func showRestoreError() {
        let alert = UIAlertController(
            title: L("settings.restore.error_title"),
            message: L("settings.restore.error_message"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L("common.ok"), style: .default))
        present(alert, animated: true)
    }

    // MARK: - Admin Mode Actions

    @objc private func versionLabelTapped() {
        versionTapCount += 1
        versionTapTimer?.invalidate()

        if versionTapCount >= 10 {
            versionTapCount = 0
            if AdminMode.shared.isEnabled {
                showAdminDeactivateAlert()
            } else {
                showAdminCodeAlert()
            }
        } else {
            versionTapTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
                self?.versionTapCount = 0
            }
        }
    }

    private func showAdminCodeAlert() {
        let alert = UIAlertController(title: "Admin Mode", message: "Enter admin code", preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "Code"
            field.isSecureTextEntry = true
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Activate", style: .default) { [weak self] _ in
            guard let code = alert.textFields?.first?.text else { return }
            if AdminMode.shared.activate(code: code) {
                self?.updateAdminBadge()
                let success = UIAlertController(title: "Admin Mode Activated", message: "All feature limits are now unlocked.", preferredStyle: .alert)
                success.addAction(UIAlertAction(title: "OK", style: .default))
                self?.present(success, animated: true)
            } else {
                let fail = UIAlertController(title: "Invalid Code", message: nil, preferredStyle: .alert)
                fail.addAction(UIAlertAction(title: "OK", style: .default))
                self?.present(fail, animated: true)
            }
        })
        present(alert, animated: true)
    }

    private func showAdminDeactivateAlert() {
        let alert = UIAlertController(title: "Admin Mode Active", message: "Do you want to deactivate admin mode?", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Keep Active", style: .cancel))
        alert.addAction(UIAlertAction(title: "Deactivate", style: .destructive) { [weak self] _ in
            AdminMode.shared.deactivate()
            self?.updateAdminBadge()
        })
        present(alert, animated: true)
    }

    private func updateAdminBadge() {
        if AdminMode.shared.isEnabled {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                title: "ADMIN",
                style: .plain,
                target: self,
                action: #selector(versionLabelTapped)
            )
            navigationItem.rightBarButtonItem?.tintColor = .systemRed
        } else {
            navigationItem.rightBarButtonItem = nil
        }
    }

    // MARK: - Icon Helper

    private func makeIcon(symbolName: String, backgroundColor: UIColor) -> UIImage? {
        let size: CGFloat = 32
        let cornerRadius: CGFloat = 8
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: CGSize(width: size, height: size))
            let path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
            backgroundColor.setFill()
            path.fill()

            let symbolConfig = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            if let symbol = UIImage(systemName: symbolName, withConfiguration: symbolConfig)?.withTintColor(.white, renderingMode: .alwaysOriginal) {
                let symbolSize = symbol.size
                let symbolOrigin = CGPoint(
                    x: (size - symbolSize.width) / 2,
                    y: (size - symbolSize.height) / 2
                )
                symbol.draw(at: symbolOrigin)
            }
        }
    }
}

// MARK: - Plan Banner Cell

private class PlanBannerCell: UITableViewCell {

    static let reuseIdentifier = "PlanBannerCell"

    private let planTitleLabel: UILabel = {
        let label = UILabel()
        label.text = L("settings.plan.current")
        label.font = .systemFont(ofSize: 13, weight: .regular)
        label.textColor = AppColors.textMuted
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let planNameLabel: UILabel = {
        let label = UILabel()
        label.text = ""
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.textColor = AppColors.text
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let upgradeContainerView: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let gradientContainer = UIView()
        gradientContainer.layer.cornerRadius = 16
        gradientContainer.clipsToBounds = true
        gradientContainer.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(gradientContainer)

        let gradient = CAGradientLayer()
        gradient.colors = [
            UIColor(red: 0.290, green: 0.102, blue: 0.541, alpha: 1).cgColor,
            UIColor(red: 0.420, green: 0.247, blue: 0.627, alpha: 1).cgColor,
            UIColor(red: 0.545, green: 0.361, blue: 0.784, alpha: 1).cgColor,
        ]
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        gradient.frame = CGRect(x: 0, y: 0, width: 200, height: 32)
        gradientContainer.layer.addSublayer(gradient)

        let highlightLine = UIView()
        highlightLine.backgroundColor = UIColor.white.withAlphaComponent(0.15)
        highlightLine.translatesAutoresizingMaskIntoConstraints = false
        gradientContainer.addSubview(highlightLine)

        let crownView = UIImageView(image: UIImage(named: "CrownIcon")?.withRenderingMode(.alwaysTemplate))
        crownView.tintColor = .systemYellow
        crownView.contentMode = .scaleAspectFit
        crownView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(crownView)

        let upgradeLabel = UILabel()
        upgradeLabel.text = L("settings.plan.upgrade")
        upgradeLabel.font = .systemFont(ofSize: 12, weight: .bold)
        upgradeLabel.textColor = .white
        upgradeLabel.numberOfLines = 1
        upgradeLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(upgradeLabel)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 32),

            gradientContainer.topAnchor.constraint(equalTo: container.topAnchor),
            gradientContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            gradientContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            gradientContainer.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            highlightLine.topAnchor.constraint(equalTo: gradientContainer.topAnchor),
            highlightLine.leadingAnchor.constraint(equalTo: gradientContainer.leadingAnchor),
            highlightLine.trailingAnchor.constraint(equalTo: gradientContainer.trailingAnchor),
            highlightLine.heightAnchor.constraint(equalToConstant: 1),

            crownView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            crownView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            crownView.widthAnchor.constraint(equalToConstant: 14),
            crownView.heightAnchor.constraint(equalToConstant: 14),

            upgradeLabel.leadingAnchor.constraint(equalTo: crownView.trailingAnchor, constant: 5),
            upgradeLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            upgradeLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
        ])

        return container
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let gradientContainer = upgradeContainerView.subviews.first,
           let gradient = gradientContainer.layer.sublayers?.first as? CAGradientLayer,
           gradientContainer.bounds.width > 0 {
            gradient.frame = gradientContainer.bounds
        }
    }

    private func setupUI() {
        let leftStack = UIStackView(arrangedSubviews: [planTitleLabel, planNameLabel])
        leftStack.axis = .vertical
        leftStack.spacing = 2
        leftStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(leftStack)
        contentView.addSubview(upgradeContainerView)

        NSLayoutConstraint.activate([
            leftStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            leftStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            leftStack.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 12),
            leftStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -12),

            upgradeContainerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            upgradeContainerView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])

        updatePlanStatus()
    }

    func updatePlanStatus() {
        let tier = SubscriptionStatus.shared.currentTier
        switch tier {
        case .free:
            planNameLabel.text = L("home.plan.free")
            upgradeContainerView.isHidden = false
        case .pro:
            planNameLabel.text = L("home.plan.pro")
            upgradeContainerView.isHidden = true
        case .premium:
            planNameLabel.text = L("home.plan.premium")
            upgradeContainerView.isHidden = true
        }
    }
}

// MARK: - SubscriptionStatusCell

private class SubscriptionStatusCell: UITableViewCell {

    static let reuseIdentifier = "SubscriptionStatusCell"

    private let badgeContainer: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 12
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let badgeLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13, weight: .bold)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let badgeIconView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let statusDot: UIView = {
        let dot = UIView()
        dot.layer.cornerRadius = 3.5
        dot.backgroundColor = AppColors.green
        dot.translatesAutoresizingMaskIntoConstraints = false
        return dot
    }()

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.text = L("settings.subscription.active")
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = AppColors.green
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        selectionStyle = .none

        badgeContainer.addSubview(badgeIconView)
        badgeContainer.addSubview(badgeLabel)

        let rightStack = UIStackView(arrangedSubviews: [statusDot, statusLabel])
        rightStack.axis = .horizontal
        rightStack.spacing = 5
        rightStack.alignment = .center
        rightStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(badgeContainer)
        contentView.addSubview(rightStack)

        NSLayoutConstraint.activate([
            badgeIconView.leadingAnchor.constraint(equalTo: badgeContainer.leadingAnchor, constant: 10),
            badgeIconView.centerYAnchor.constraint(equalTo: badgeContainer.centerYAnchor),
            badgeIconView.widthAnchor.constraint(equalToConstant: 14),
            badgeIconView.heightAnchor.constraint(equalToConstant: 14),

            badgeLabel.leadingAnchor.constraint(equalTo: badgeIconView.trailingAnchor, constant: 4),
            badgeLabel.trailingAnchor.constraint(equalTo: badgeContainer.trailingAnchor, constant: -10),
            badgeLabel.topAnchor.constraint(equalTo: badgeContainer.topAnchor),
            badgeLabel.bottomAnchor.constraint(equalTo: badgeContainer.bottomAnchor),

            badgeContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            badgeContainer.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            badgeContainer.heightAnchor.constraint(equalToConstant: 28),

            statusDot.widthAnchor.constraint(equalToConstant: 7),
            statusDot.heightAnchor.constraint(equalToConstant: 7),

            rightStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            rightStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            badgeContainer.trailingAnchor.constraint(lessThanOrEqualTo: rightStack.leadingAnchor, constant: -8),

            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
        ])
    }

    func updateStatus() {
        let tier = SubscriptionStatus.shared.currentTier
        applyTierColors(tier: tier)
        statusLabel.text = L("settings.subscription.active")
    }

    private func applyTierColors(tier: UserTier) {
        switch tier {
        case .pro:
            badgeIconView.image = UIImage(named: "CrownIcon")
            badgeLabel.text = L("home.plan.pro")
            badgeLabel.textColor = AppColors.gold
            badgeContainer.backgroundColor = AppColors.goldSoft
        case .premium:
            badgeIconView.image = UIImage(named: "DiamondIcon")
            badgeLabel.text = L("home.plan.premium")
            badgeLabel.textColor = AppColors.purple
            badgeContainer.backgroundColor = AppColors.purpleSoft
        case .free:
            break // Free일 때는 이 셀 자체가 표시되지 않음
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            let tier = SubscriptionStatus.shared.currentTier
            applyTierColors(tier: tier)
        }
    }
}
