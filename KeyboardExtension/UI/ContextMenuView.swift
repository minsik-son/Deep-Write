import UIKit

class ContextMenuView: UIView {

    var onSettingsTap: (() -> Void)?
    var onHelpTap: (() -> Void)?
    var onDismiss: (() -> Void)?

    // MARK: - UI

    private let arrowView = UIView()
    private let menuContainer = UIView()
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
        // Transparent dismiss area
        tapDismissView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tapDismissView)
        NSLayoutConstraint.activate([
            tapDismissView.topAnchor.constraint(equalTo: topAnchor),
            tapDismissView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tapDismissView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tapDismissView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        let dismissTap = UITapGestureRecognizer(target: self, action: #selector(dismissMenu))
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

        // Menu container
        menuContainer.layer.cornerRadius = 12
        menuContainer.layer.shadowColor = UIColor.black.cgColor
        menuContainer.layer.shadowOffset = CGSize(width: 0, height: 8)
        menuContainer.layer.shadowOpacity = 0.18
        menuContainer.layer.shadowRadius = 30
        menuContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(menuContainer)

        NSLayoutConstraint.activate([
            menuContainer.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            menuContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            menuContainer.widthAnchor.constraint(equalToConstant: 180),
        ])

        bringSubviewToFront(arrowView)

        // Menu items stack
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        menuContainer.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: menuContainer.topAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: menuContainer.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: menuContainer.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: menuContainer.bottomAnchor, constant: -4),
        ])

        // Settings row
        let settingsRow = makeMenuRow(
            icon: "gearshape",
            iconColor: UIColor(red: 0.192, green: 0.510, blue: 0.965, alpha: 1),
            title: L("keyboard.menu.settings"),
            action: #selector(settingsTapped)
        )
        stack.addArrangedSubview(settingsRow)

        // Separator
        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        let sepWrapper = UIView()
        sepWrapper.addSubview(separator)
        separator.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: sepWrapper.topAnchor),
            separator.leadingAnchor.constraint(equalTo: sepWrapper.leadingAnchor, constant: 14),
            separator.trailingAnchor.constraint(equalTo: sepWrapper.trailingAnchor, constant: -14),
            separator.bottomAnchor.constraint(equalTo: sepWrapper.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),
        ])
        stack.addArrangedSubview(sepWrapper)

        // Help row
        let helpRow = makeMenuRow(
            icon: "questionmark.circle",
            iconColor: UIColor.systemGray,
            title: L("keyboard.menu.help"),
            action: #selector(helpTapped)
        )
        stack.addArrangedSubview(helpRow)

        updateColors()
    }

    private func makeMenuRow(icon: String, iconColor: UIColor, title: String, action: Selector) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.heightAnchor.constraint(equalToConstant: 40).isActive = true

        let iconView = UIImageView()
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        iconView.image = UIImage(systemName: icon, withConfiguration: config)
        iconView.tintColor = iconColor
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(iconView)
        container.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            iconView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            titleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
        ])

        let tap = UITapGestureRecognizer(target: self, action: action)
        container.addGestureRecognizer(tap)
        container.isUserInteractionEnabled = true

        return container
    }

    func updateColors() {
        let isDark = traitCollection.userInterfaceStyle == .dark
        let bg: UIColor = isDark ? UIColor(red: 0.227, green: 0.227, blue: 0.235, alpha: 1) : .white
        menuContainer.backgroundColor = bg
        arrowView.backgroundColor = bg

        let textColor: UIColor = isDark ? .white : UIColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1)
        for subview in menuContainer.subviews {
            for label in subview.subviews.compactMap({ findLabels(in: $0) }).flatMap({ $0 }) {
                label.textColor = textColor
            }
        }

        // Separator color
        for subview in (menuContainer.subviews.first as? UIStackView)?.arrangedSubviews ?? [] {
            for sep in subview.subviews where sep.frame.height <= 1 {
                sep.backgroundColor = isDark ? UIColor.white.withAlphaComponent(0.08) : UIColor.black.withAlphaComponent(0.08)
            }
        }
    }

    private func findLabels(in view: UIView) -> [UILabel] {
        var labels: [UILabel] = []
        if let label = view as? UILabel {
            labels.append(label)
        }
        for sub in view.subviews {
            labels.append(contentsOf: findLabels(in: sub))
        }
        return labels
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateColors()
    }

    // MARK: - Actions

    @objc private func settingsTapped() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onSettingsTap?()
    }

    @objc private func helpTapped() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onHelpTap?()
    }

    @objc private func dismissMenu() {
        onDismiss?()
    }
}
