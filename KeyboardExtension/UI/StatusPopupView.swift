import UIKit

class StatusPopupView: UIView {

    var onUpgradeTap: (() -> Void)?
    var onDismiss: (() -> Void)?

    // MARK: - UI

    private let arrowView = UIView()
    private let popupContainer = UIView()
    private let headerLabel = UILabel()
    private let correctionRow = UIView()
    private let translationRow = UIView()
    private let correctionValueLabel = UILabel()
    private let translationValueLabel = UILabel()
    private let progressTrack = UIView()
    private let progressFill = UIView()
    private let planRow = UIView()
    private let planValueLabel = UILabel()
    private let upgradeButton = UIButton(type: .system)
    private let tapDismissView = UIView()

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
        // Transparent dismiss area (full keyboard extent)
        tapDismissView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tapDismissView)
        NSLayoutConstraint.activate([
            tapDismissView.topAnchor.constraint(equalTo: topAnchor),
            tapDismissView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tapDismissView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tapDismissView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        let dismissTap = UITapGestureRecognizer(target: self, action: #selector(dismissPopup))
        tapDismissView.addGestureRecognizer(dismissTap)

        // Arrow
        arrowView.translatesAutoresizingMaskIntoConstraints = false
        arrowView.layer.shadowColor = UIColor.black.cgColor
        arrowView.layer.shadowOffset = CGSize(width: -1, height: -1)
        arrowView.layer.shadowOpacity = 0.04
        arrowView.layer.shadowRadius = 2
        addSubview(arrowView)

        NSLayoutConstraint.activate([
            arrowView.widthAnchor.constraint(equalToConstant: 14),
            arrowView.heightAnchor.constraint(equalToConstant: 14),
            arrowView.topAnchor.constraint(equalTo: topAnchor, constant: 0),
            arrowView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 19),
        ])
        arrowView.transform = CGAffineTransform(rotationAngle: .pi / 4)

        // Popup container
        popupContainer.layer.cornerRadius = 14
        popupContainer.layer.shadowColor = UIColor.black.cgColor
        popupContainer.layer.shadowOffset = CGSize(width: 0, height: 8)
        popupContainer.layer.shadowOpacity = 0.18
        popupContainer.layer.shadowRadius = 30
        popupContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(popupContainer)

        NSLayoutConstraint.activate([
            popupContainer.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            popupContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            popupContainer.widthAnchor.constraint(equalToConstant: 200),
        ])

        // Bring arrow in front of container for visual overlap
        bringSubviewToFront(arrowView)

        // Content stack
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        popupContainer.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: popupContainer.topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: popupContainer.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: popupContainer.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: popupContainer.bottomAnchor, constant: -14),
        ])

        // Header
        headerLabel.font = .systemFont(ofSize: 11, weight: .bold)
        headerLabel.textColor = UIColor.systemGray
        let headerAttr = NSAttributedString(string: L("keyboard.status.remaining_today").uppercased(),
                                             attributes: [.kern: 0.5])
        headerLabel.attributedText = headerAttr
        stack.addArrangedSubview(headerLabel)

        // Correction row
        let corrRow = makeStatRow(
            title: L("reward.mode.correction"),
            valueLabel: correctionValueLabel,
            valueColor: UIColor(red: 1, green: 0.624, blue: 0.263, alpha: 1)
        )
        stack.addArrangedSubview(corrRow)

        // Translation row
        let transRow = makeStatRow(
            title: L("reward.mode.translation"),
            valueLabel: translationValueLabel,
            valueColor: UIColor(red: 0.192, green: 0.510, blue: 0.965, alpha: 1)
        )
        stack.addArrangedSubview(transRow)

        // Progress bar
        let progressContainer = UIView()
        progressContainer.translatesAutoresizingMaskIntoConstraints = false
        progressContainer.heightAnchor.constraint(equalToConstant: 4).isActive = true

        progressTrack.layer.cornerRadius = 2
        progressTrack.translatesAutoresizingMaskIntoConstraints = false
        progressContainer.addSubview(progressTrack)
        NSLayoutConstraint.activate([
            progressTrack.topAnchor.constraint(equalTo: progressContainer.topAnchor),
            progressTrack.leadingAnchor.constraint(equalTo: progressContainer.leadingAnchor),
            progressTrack.trailingAnchor.constraint(equalTo: progressContainer.trailingAnchor),
            progressTrack.bottomAnchor.constraint(equalTo: progressContainer.bottomAnchor),
        ])

        progressFill.layer.cornerRadius = 2
        progressFill.translatesAutoresizingMaskIntoConstraints = false
        progressContainer.addSubview(progressFill)
        NSLayoutConstraint.activate([
            progressFill.topAnchor.constraint(equalTo: progressContainer.topAnchor),
            progressFill.leadingAnchor.constraint(equalTo: progressContainer.leadingAnchor),
            progressFill.bottomAnchor.constraint(equalTo: progressContainer.bottomAnchor),
        ])

        stack.addArrangedSubview(progressContainer)

        // Separator
        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        stack.addArrangedSubview(separator)

        // Plan row
        let planRowView = UIView()
        planRowView.translatesAutoresizingMaskIntoConstraints = false
        let planTitleLabel = UILabel()
        planTitleLabel.text = L("keyboard.status.plan")
        planTitleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        planTitleLabel.translatesAutoresizingMaskIntoConstraints = false

        planValueLabel.font = .systemFont(ofSize: 13, weight: .bold)
        planValueLabel.translatesAutoresizingMaskIntoConstraints = false

        planRowView.addSubview(planTitleLabel)
        planRowView.addSubview(planValueLabel)
        NSLayoutConstraint.activate([
            planTitleLabel.leadingAnchor.constraint(equalTo: planRowView.leadingAnchor),
            planTitleLabel.centerYAnchor.constraint(equalTo: planRowView.centerYAnchor),
            planValueLabel.trailingAnchor.constraint(equalTo: planRowView.trailingAnchor),
            planValueLabel.centerYAnchor.constraint(equalTo: planRowView.centerYAnchor),
            planRowView.heightAnchor.constraint(equalToConstant: 24),
        ])
        stack.addArrangedSubview(planRowView)

        // Upgrade button
        upgradeButton.setTitle("Pro\(L("keyboard.status.upgrade_pro")) \u{2192}", for: .normal)
        upgradeButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        upgradeButton.setTitleColor(UIColor(red: 0.192, green: 0.510, blue: 0.965, alpha: 1), for: .normal)
        upgradeButton.contentHorizontalAlignment = .trailing
        upgradeButton.addTarget(self, action: #selector(upgradeTapped), for: .touchUpInside)
        stack.addArrangedSubview(upgradeButton)

        updateColors()
    }

    private func makeStatRow(title: String, valueLabel: UILabel, valueColor: UIColor) -> UIView {
        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        valueLabel.font = .systemFont(ofSize: 14, weight: .bold)
        valueLabel.textColor = valueColor
        valueLabel.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(titleLabel)
        row.addSubview(valueLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            valueLabel.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            valueLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            row.heightAnchor.constraint(equalToConstant: 22),
        ])

        return row
    }

    // MARK: - Public

    private var progressFillWidthConstraint: NSLayoutConstraint?

    func update(corrUsed: Int, corrTotal: Int, transUsed: Int, transTotal: Int, planName: String, isPro: Bool) {
        correctionValueLabel.text = "\(corrUsed)/\(corrTotal)"
        translationValueLabel.text = "\(transUsed)/\(transTotal)"
        planValueLabel.text = planName
        upgradeButton.isHidden = isPro

        // Update header localization
        let headerAttr = NSAttributedString(string: L("keyboard.status.remaining_today").uppercased(),
                                             attributes: [.kern: 0.5])
        headerLabel.attributedText = headerAttr

        // Progress bar
        let totalUsed = corrUsed + transUsed
        let totalMax = corrTotal + transTotal
        let fraction = totalMax > 0 ? CGFloat(totalUsed) / CGFloat(totalMax) : 0

        progressFillWidthConstraint?.isActive = false
        progressFillWidthConstraint = progressFill.widthAnchor.constraint(
            equalTo: progressTrack.widthAnchor,
            multiplier: min(fraction, 1.0)
        )
        progressFillWidthConstraint?.isActive = true

        // Gradient-like fill (accent to orange based on usage)
        if fraction >= 0.7 {
            progressFill.backgroundColor = UIColor(red: 1, green: 0.624, blue: 0.263, alpha: 1)
        } else {
            progressFill.backgroundColor = UIColor(red: 0.192, green: 0.510, blue: 0.965, alpha: 1)
        }
    }

    func updateColors() {
        let isDark = traitCollection.userInterfaceStyle == .dark
        let bg: UIColor = isDark ? UIColor(red: 0.227, green: 0.227, blue: 0.235, alpha: 1) : .white
        popupContainer.backgroundColor = bg
        arrowView.backgroundColor = bg
        progressTrack.backgroundColor = isDark ? UIColor.white.withAlphaComponent(0.1) : UIColor.black.withAlphaComponent(0.06)

        let textColor: UIColor = isDark ? .white : UIColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1)
        planValueLabel.textColor = UIColor.systemGray

        // Update stat row title labels
        for subview in popupContainer.subviews {
            for label in subview.subviews.compactMap({ $0 as? UILabel }) {
                if label !== correctionValueLabel && label !== translationValueLabel
                    && label !== planValueLabel && label !== headerLabel {
                    label.textColor = textColor
                }
            }
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateColors()
    }

    // MARK: - Actions

    @objc private func dismissPopup() {
        onDismiss?()
    }

    @objc private func upgradeTapped() {
        onUpgradeTap?()
    }
}
