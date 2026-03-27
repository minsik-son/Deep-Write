import UIKit

class PasteGuideViewController: UIViewController {

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColors.bg
        title = L("settings.paste_guide")
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
        contentStack.spacing = 20
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 20),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -32),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -40),
        ])

        // Description
        let descLabel = UILabel()
        descLabel.text = L("paste_guide.description")
        descLabel.font = .systemFont(ofSize: 15)
        descLabel.textColor = AppColors.textSub
        descLabel.numberOfLines = 0
        contentStack.addArrangedSubview(descLabel)

        // Steps
        let steps = [
            (L("paste_guide.step1.title"), L("paste_guide.step1.detail")),
            (L("paste_guide.step2.title"), L("paste_guide.step2.detail")),
            (L("paste_guide.step3.title"), L("paste_guide.step3.detail")),
        ]

        for (i, step) in steps.enumerated() {
            let card = makeStepCard(number: i + 1, title: step.0, detail: step.1)
            contentStack.addArrangedSubview(card)
        }

        // Open Settings button
        let openSettingsButton = UIButton(type: .system)
        openSettingsButton.setTitle(L("paste_guide.open_settings"), for: .normal)
        openSettingsButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        openSettingsButton.backgroundColor = AppColors.tierAccent
        openSettingsButton.setTitleColor(.white, for: .normal)
        openSettingsButton.layer.cornerRadius = 12
        openSettingsButton.translatesAutoresizingMaskIntoConstraints = false
        openSettingsButton.heightAnchor.constraint(equalToConstant: 48).isActive = true
        openSettingsButton.addTarget(self, action: #selector(openSettingsTapped), for: .touchUpInside)
        contentStack.addArrangedSubview(openSettingsButton)
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
