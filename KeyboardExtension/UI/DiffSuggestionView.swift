import UIKit

class DiffSuggestionView: UIView {

    var onRecommendedTap: ((String) -> Void)?
    var onAlternativeTap: ((String) -> Void)?

    private let recommendedColumn = UIView()
    private let alternativeColumn = UIView()
    private let divider = UIView()

    private let recommendedLabel = UILabel()
    private let alternativeLabel = UILabel()
    private let recommendedTextLabel = UILabel()
    private let alternativeTextLabel = UILabel()

    private var recommendedText: String = ""
    private var alternativeText: String = ""

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
        layer.cornerRadius = 10
        clipsToBounds = true

        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowOpacity = 0.2
        layer.shadowRadius = 0.5

        // Two columns side by side
        recommendedColumn.translatesAutoresizingMaskIntoConstraints = false
        alternativeColumn.translatesAutoresizingMaskIntoConstraints = false
        divider.translatesAutoresizingMaskIntoConstraints = false

        addSubview(recommendedColumn)
        addSubview(divider)
        addSubview(alternativeColumn)

        NSLayoutConstraint.activate([
            recommendedColumn.topAnchor.constraint(equalTo: topAnchor),
            recommendedColumn.leadingAnchor.constraint(equalTo: leadingAnchor),
            recommendedColumn.bottomAnchor.constraint(equalTo: bottomAnchor),

            divider.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            divider.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            divider.leadingAnchor.constraint(equalTo: recommendedColumn.trailingAnchor),
            divider.widthAnchor.constraint(equalToConstant: 0.5),

            alternativeColumn.topAnchor.constraint(equalTo: topAnchor),
            alternativeColumn.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            alternativeColumn.trailingAnchor.constraint(equalTo: trailingAnchor),
            alternativeColumn.bottomAnchor.constraint(equalTo: bottomAnchor),

            recommendedColumn.widthAnchor.constraint(equalTo: alternativeColumn.widthAnchor),
        ])

        // Recommended column content
        setupColumn(recommendedColumn,
                     label: recommendedLabel,
                     textLabel: recommendedTextLabel,
                     headerText: L("keyboard.suggestion.recommended"),
                     headerColor: UIColor(red: 0.192, green: 0.510, blue: 0.965, alpha: 1),
                     tapAction: #selector(recommendedTapped))

        // Alternative column content
        setupColumn(alternativeColumn,
                     label: alternativeLabel,
                     textLabel: alternativeTextLabel,
                     headerText: L("keyboard.suggestion.alternative"),
                     headerColor: UIColor.systemGray,
                     tapAction: #selector(alternativeTapped))

        updateColors()
    }

    private func setupColumn(_ column: UIView, label: UILabel, textLabel: UILabel, headerText: String, headerColor: UIColor, tapAction: Selector) {
        let headerAttr = NSAttributedString(
            string: headerText.uppercased(),
            attributes: [
                .font: UIFont.systemFont(ofSize: 10, weight: .bold),
                .foregroundColor: headerColor,
                .kern: 0.3,
            ]
        )
        label.attributedText = headerAttr
        label.translatesAutoresizingMaskIntoConstraints = false

        textLabel.font = .systemFont(ofSize: 14, weight: .regular)
        textLabel.numberOfLines = 0

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = 1.4
        textLabel.translatesAutoresizingMaskIntoConstraints = false

        column.addSubview(label)
        column.addSubview(textLabel)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: column.topAnchor, constant: 10),
            label.leadingAnchor.constraint(equalTo: column.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: column.trailingAnchor, constant: -12),

            textLabel.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 6),
            textLabel.leadingAnchor.constraint(equalTo: column.leadingAnchor, constant: 12),
            textLabel.trailingAnchor.constraint(equalTo: column.trailingAnchor, constant: -12),
            textLabel.bottomAnchor.constraint(lessThanOrEqualTo: column.bottomAnchor, constant: -10),
        ])

        let tap = UITapGestureRecognizer(target: self, action: tapAction)
        column.addGestureRecognizer(tap)
        column.isUserInteractionEnabled = true
    }

    // MARK: - Public

    func update(original: String, recommended: String, alternative: String) {
        self.recommendedText = recommended
        self.alternativeText = alternative

        // Highlight changed words in recommended (blue)
        recommendedTextLabel.attributedText = highlightDiff(
            original: original,
            corrected: recommended,
            highlightColor: UIColor(red: 0.192, green: 0.510, blue: 0.965, alpha: 1)
        )

        // Highlight changed words in alternative (orange)
        alternativeTextLabel.attributedText = highlightDiff(
            original: original,
            corrected: alternative,
            highlightColor: UIColor(red: 1, green: 0.624, blue: 0.263, alpha: 1)
        )
    }

    private func highlightDiff(original: String, corrected: String, highlightColor: UIColor) -> NSAttributedString {
        let isDark = traitCollection.userInterfaceStyle == .dark
        let baseColor: UIColor = isDark ? .white : .black

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = 1.4

        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .regular),
            .foregroundColor: baseColor,
            .paragraphStyle: paragraphStyle,
        ]

        let highlightAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: highlightColor,
            .paragraphStyle: paragraphStyle,
        ]

        let originalWords = original.components(separatedBy: " ")
        let correctedWords = corrected.components(separatedBy: " ")

        let originalSet = Set(originalWords)

        let result = NSMutableAttributedString()
        for (i, word) in correctedWords.enumerated() {
            if i > 0 {
                result.append(NSAttributedString(string: " ", attributes: baseAttrs))
            }
            if originalSet.contains(word) {
                result.append(NSAttributedString(string: word, attributes: baseAttrs))
            } else {
                result.append(NSAttributedString(string: word, attributes: highlightAttrs))
            }
        }

        return result
    }

    func updateColors() {
        let isDark = traitCollection.userInterfaceStyle == .dark
        let bgColor: UIColor = isDark ? UIColor(white: 0.29, alpha: 1) : .white
        backgroundColor = bgColor

        recommendedColumn.backgroundColor = isDark
            ? UIColor(red: 0.192, green: 0.510, blue: 0.965, alpha: 0.10)
            : UIColor(red: 0.192, green: 0.510, blue: 0.965, alpha: 0.05)

        alternativeColumn.backgroundColor = .clear
        divider.backgroundColor = isDark ? UIColor.white.withAlphaComponent(0.1) : UIColor.separator
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateColors()
    }

    // MARK: - Actions

    @objc private func recommendedTapped() {
        onRecommendedTap?(recommendedText)
    }

    @objc private func alternativeTapped() {
        onAlternativeTap?(alternativeText)
    }
}
