import UIKit

class PrivacyDashboardViewController: UIViewController {

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColors.bg
        title = L("settings.privacy_dashboard")
        setupUI()
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
        headerLabel.text = L("privacy.header")
        headerLabel.font = .systemFont(ofSize: 15)
        headerLabel.textColor = AppColors.textSub
        headerLabel.numberOfLines = 0
        contentStack.addArrangedSubview(headerLabel)

        // Not collected section
        let notCollectedTitle = makeSectionTitle(L("privacy.not_collected"))
        contentStack.addArrangedSubview(notCollectedTitle)

        let notCollectedItems: [(String, String)] = [
            ("keyboard.fill", L("privacy.keyboard_input")),
            ("creditcard", L("privacy.passwords_cards")),
            ("doc.on.clipboard", L("privacy.clipboard_data")),
            ("chart.bar", L("privacy.stats_data")),
        ]

        for item in notCollectedItems {
            let row = makePrivacyRow(icon: item.0, text: item.1, isCollected: false)
            contentStack.addArrangedSubview(row)
        }

        // Server communication section
        let serverTitle = makeSectionTitle(L("privacy.server_comm"))
        contentStack.addArrangedSubview(serverTitle)
        contentStack.setCustomSpacing(8, after: serverTitle)

        let serverItems: [(String, String)] = [
            ("checkmark.circle", L("privacy.ai_correction_server")),
            ("globe", L("privacy.ai_translation_server")),
        ]

        for item in serverItems {
            let row = makePrivacyRow(icon: item.0, text: item.1, isCollected: true)
            contentStack.addArrangedSubview(row)
        }

        // Ad Privacy section
        let adPrivacyTitle = makeSectionTitle(L("privacy.ad_privacy"))
        contentStack.addArrangedSubview(adPrivacyTitle)
        contentStack.setCustomSpacing(8, after: adPrivacyTitle)

        let adPrivacyButton = UIButton(type: .system)
        adPrivacyButton.setTitle(L("privacy.manage_ad_choices"), for: .normal)
        adPrivacyButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        adPrivacyButton.setTitleColor(.white, for: .normal)
        adPrivacyButton.backgroundColor = AppColors.tierAccent
        adPrivacyButton.layer.cornerRadius = 12
        adPrivacyButton.translatesAutoresizingMaskIntoConstraints = false
        adPrivacyButton.addTarget(self, action: #selector(manageAdPrivacyTapped), for: .touchUpInside)
        NSLayoutConstraint.activate([
            adPrivacyButton.heightAnchor.constraint(equalToConstant: 48),
        ])
        contentStack.addArrangedSubview(adPrivacyButton)
    }

    private func makeSectionTitle(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text.uppercased()
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = AppColors.textMuted
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    @objc private func manageAdPrivacyTapped() {
        if AdConsentManager.shared.privacyOptionsRequired {
            AdConsentManager.shared.presentPrivacyOptions(from: self)
        } else if let url = URL(string: LegalLinks.privacyChoices) {
            UIApplication.shared.open(url)
        }
    }

    private func makePrivacyRow(icon: String, text: String, isCollected: Bool) -> UIView {
        let card = UIView()
        card.backgroundColor = AppColors.card
        card.layer.cornerRadius = 12
        card.layer.borderWidth = 1
        card.layer.borderColor = AppColors.border.cgColor
        card.translatesAutoresizingMaskIntoConstraints = false

        let iconView = UIImageView()
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        iconView.image = UIImage(systemName: icon, withConfiguration: symbolConfig)
        iconView.tintColor = isCollected ? AppColors.orange : AppColors.green
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let textLabel = UILabel()
        textLabel.text = text
        textLabel.font = .systemFont(ofSize: 14)
        textLabel.textColor = AppColors.text
        textLabel.numberOfLines = 0
        textLabel.translatesAutoresizingMaskIntoConstraints = false

        let statusIcon = UIImageView()
        let statusSymbol = isCollected ? "arrow.up.arrow.down.circle" : "checkmark.circle.fill"
        statusIcon.image = UIImage(systemName: statusSymbol, withConfiguration: symbolConfig)
        statusIcon.tintColor = isCollected ? AppColors.orange : AppColors.green
        statusIcon.contentMode = .scaleAspectFit
        statusIcon.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(iconView)
        card.addSubview(textLabel)
        card.addSubview(statusIcon)

        NSLayoutConstraint.activate([
            card.heightAnchor.constraint(greaterThanOrEqualToConstant: 52),

            iconView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            iconView.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),

            textLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            textLabel.trailingAnchor.constraint(equalTo: statusIcon.leadingAnchor, constant: -8),
            textLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            textLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),

            statusIcon.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            statusIcon.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            statusIcon.widthAnchor.constraint(equalToConstant: 20),
            statusIcon.heightAnchor.constraint(equalToConstant: 20),
        ])

        return card
    }
}
