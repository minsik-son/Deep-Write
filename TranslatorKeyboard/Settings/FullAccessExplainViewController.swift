import UIKit

class FullAccessExplainViewController: UIViewController {

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private var statusContainer: UIView?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColors.bg
        title = L("settings.full_access_explain")
        setupUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateStatusUI()
    }

    private func setupUI() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 20),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -32),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -40),
        ])

        // Header
        let headerLabel = UILabel()
        headerLabel.text = L("full_access.header")
        headerLabel.font = .systemFont(ofSize: 15)
        headerLabel.textColor = AppColors.textSub
        headerLabel.numberOfLines = 0
        contentStack.addArrangedSubview(headerLabel)

        // Feature rows
        let features: [(String, String, Bool)] = [
            ("keyboard", L("full_access.basic_typing"), false),
            ("checkmark.circle", L("full_access.ai_correction"), true),
            ("globe", L("full_access.ai_translation"), true),
            ("doc.on.clipboard", L("full_access.clipboard"), true),
            ("paintpalette", L("full_access.theme_layout"), false),
        ]

        for feature in features {
            let row = makeFeatureRow(icon: feature.0, text: feature.1, requiresFullAccess: feature.2)
            contentStack.addArrangedSubview(row)
        }

        // Setup guide step cards
        let steps = [
            (L("full_access.setup_step1.title"), L("full_access.setup_step1.detail")),
            (L("full_access.setup_step2.title"), L("full_access.setup_step2.detail")),
        ]

        let guideSpacing = UIView()
        guideSpacing.translatesAutoresizingMaskIntoConstraints = false
        guideSpacing.heightAnchor.constraint(equalToConstant: 4).isActive = true
        contentStack.addArrangedSubview(guideSpacing)

        for (i, step) in steps.enumerated() {
            let card = makeStepCard(number: i + 1, title: step.0, detail: step.1)
            contentStack.addArrangedSubview(card)
        }

        // Status container (will be updated in viewWillAppear)
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(container)
        statusContainer = container
    }

    private func updateStatusUI() {
        guard let container = statusContainer else { return }
        container.subviews.forEach { $0.removeFromSuperview() }

        let isGranted = AppGroupManager.shared.bool(forKey: AppConstants.UserDefaultsKeys.keyboardFullAccessEnabled)

        if isGranted {
            let statusStack = UIStackView()
            statusStack.axis = .horizontal
            statusStack.spacing = 8
            statusStack.alignment = .center
            statusStack.translatesAutoresizingMaskIntoConstraints = false

            let checkIcon = UIImageView()
            checkIcon.image = UIImage(systemName: "checkmark.circle.fill")
            checkIcon.tintColor = .systemGreen
            checkIcon.contentMode = .scaleAspectFit
            checkIcon.translatesAutoresizingMaskIntoConstraints = false

            let statusLabel = UILabel()
            statusLabel.text = L("full_access.already_granted")
            statusLabel.font = .systemFont(ofSize: 15, weight: .medium)
            statusLabel.textColor = .systemGreen
            statusLabel.numberOfLines = 0
            statusLabel.translatesAutoresizingMaskIntoConstraints = false

            statusStack.addArrangedSubview(checkIcon)
            statusStack.addArrangedSubview(statusLabel)

            container.addSubview(statusStack)
            NSLayoutConstraint.activate([
                checkIcon.widthAnchor.constraint(equalToConstant: 24),
                checkIcon.heightAnchor.constraint(equalToConstant: 24),
                statusStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
                statusStack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                statusStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
            ])
        } else {
            let settingsButton = UIButton(type: .system)
            settingsButton.setTitle(L("full_access.go_settings"), for: .normal)
            settingsButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
            settingsButton.backgroundColor = AppColors.tierAccent
            settingsButton.setTitleColor(.white, for: .normal)
            settingsButton.layer.cornerRadius = 12
            settingsButton.translatesAutoresizingMaskIntoConstraints = false
            settingsButton.addTarget(self, action: #selector(openSettingsTapped), for: .touchUpInside)

            container.addSubview(settingsButton)
            NSLayoutConstraint.activate([
                settingsButton.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
                settingsButton.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                settingsButton.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                settingsButton.heightAnchor.constraint(equalToConstant: 48),
                settingsButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
            ])
        }
    }

    private func makeFeatureRow(icon: String, text: String, requiresFullAccess: Bool) -> UIView {
        let card = UIView()
        card.backgroundColor = AppColors.card
        card.layer.cornerRadius = 12
        card.layer.borderWidth = 1
        card.layer.borderColor = AppColors.border.cgColor
        card.translatesAutoresizingMaskIntoConstraints = false

        let iconView = UIImageView()
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        iconView.image = UIImage(systemName: icon, withConfiguration: symbolConfig)
        iconView.tintColor = AppColors.tierAccent
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let textLabel = UILabel()
        textLabel.text = text
        textLabel.font = .systemFont(ofSize: 14)
        textLabel.textColor = AppColors.text
        textLabel.numberOfLines = 0
        textLabel.translatesAutoresizingMaskIntoConstraints = false

        let badgeLabel = UILabel()
        badgeLabel.text = requiresFullAccess ? L("full_access.required") : L("full_access.not_required")
        badgeLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        badgeLabel.textColor = requiresFullAccess ? AppColors.orange : AppColors.green
        badgeLabel.textAlignment = .center
        badgeLabel.backgroundColor = (requiresFullAccess ? AppColors.orange : AppColors.green).withAlphaComponent(0.15)
        badgeLabel.layer.cornerRadius = 4
        badgeLabel.clipsToBounds = true
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(iconView)
        card.addSubview(textLabel)
        card.addSubview(badgeLabel)

        NSLayoutConstraint.activate([
            card.heightAnchor.constraint(greaterThanOrEqualToConstant: 56),

            iconView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            iconView.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),

            textLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            textLabel.centerYAnchor.constraint(equalTo: card.centerYAnchor),

            badgeLabel.leadingAnchor.constraint(greaterThanOrEqualTo: textLabel.trailingAnchor, constant: 8),
            badgeLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            badgeLabel.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            badgeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 50),
            badgeLabel.heightAnchor.constraint(equalToConstant: 22),
        ])

        return card
    }

    private func makeStepCard(number: Int, title: String, detail: String) -> UIView {
        let card = UIView()
        card.backgroundColor = AppColors.card
        card.layer.cornerRadius = 14
        card.layer.borderWidth = 1
        card.layer.borderColor = AppColors.border.cgColor

        let badge = UILabel()
        badge.text = "\(number)"
        badge.font = .systemFont(ofSize: 14, weight: .bold)
        badge.textColor = .white
        badge.textAlignment = .center
        badge.backgroundColor = AppColors.tierAccent
        badge.layer.cornerRadius = 12
        badge.layer.masksToBounds = true
        badge.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = AppColors.text
        titleLabel.numberOfLines = 0
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let detailLabel = UILabel()
        detailLabel.text = detail
        detailLabel.font = .systemFont(ofSize: 13)
        detailLabel.textColor = AppColors.textSub
        detailLabel.numberOfLines = 0
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(badge)
        card.addSubview(titleLabel)
        card.addSubview(detailLabel)
        card.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            badge.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            badge.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            badge.widthAnchor.constraint(equalToConstant: 24),
            badge.heightAnchor.constraint(equalToConstant: 24),

            titleLabel.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),

            detailLabel.topAnchor.constraint(equalTo: badge.bottomAnchor, constant: 10),
            detailLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            detailLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            detailLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
        ])

        return card
    }

    @objc private func openSettingsTapped() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}
