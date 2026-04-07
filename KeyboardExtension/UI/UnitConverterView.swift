import UIKit

// MARK: - Unit Converter View

final class UnitConverterView: UIView {

    // MARK: - Callbacks

    var onClose: (() -> Void)?
    var onInsert: ((String) -> Void)?

    // MARK: - Unit Categories

    private enum UnitCategory: Int, CaseIterable {
        case length = 0
        case weight
        case temperature
        case volume

        var title: String {
            switch self {
            case .length:      return L("unit.category.length")
            case .weight:      return L("unit.category.weight")
            case .temperature:  return L("unit.category.temperature")
            case .volume:      return L("unit.category.volume")
            }
        }

        var units: [(String, Dimension)] {
            switch self {
            case .length:
                return [("mm", UnitLength.millimeters),
                        ("cm", UnitLength.centimeters),
                        ("m", UnitLength.meters),
                        ("in", UnitLength.inches),
                        ("ft", UnitLength.feet)]
            case .weight:
                return [("g", UnitMass.grams),
                        ("kg", UnitMass.kilograms),
                        ("lb", UnitMass.pounds)]
            case .temperature:
                return [("\u{00B0}C", UnitTemperature.celsius),
                        ("\u{00B0}F", UnitTemperature.fahrenheit)]
            case .volume:
                return [("mL", UnitVolume.milliliters),
                        ("L", UnitVolume.liters),
                        ("oz", UnitVolume.fluidOunces)]
            }
        }
    }

    // MARK: - State

    private var currentCategory: UnitCategory = .length
    private var fromUnitIndex: Int = 0
    private var toUnitIndex: Int = 1
    private var inputValue: String = ""

    // MARK: - Formatter

    private let numberFormatter: NumberFormatter = {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.maximumFractionDigits = 6
        nf.minimumFractionDigits = 0
        return nf
    }()

    // MARK: - Haptic

    private let hapticFeedback = UIImpactFeedbackGenerator(style: .light)

    // MARK: - Theme State

    private var isDark: Bool = false
    private var customTheme: KeyboardTheme?

    // MARK: - UI Components

    private let headerContainer: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let insertButton: UIButton = {
        let btn = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        btn.setImage(UIImage(systemName: "square.and.arrow.up", withConfiguration: config), for: .normal)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.accessibilityLabel = "Insert result"
        return btn
    }()

    private let closeButton: UIButton = {
        let btn = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        btn.setImage(UIImage(systemName: "xmark", withConfiguration: config), for: .normal)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.accessibilityLabel = "Close converter"
        return btn
    }()

    private let categorySegment: UISegmentedControl = {
        let seg = UISegmentedControl()
        seg.translatesAutoresizingMaskIntoConstraints = false
        return seg
    }()

    private let displayContainer: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let fromLabel: UILabel = {
        let l = UILabel()
        l.font = .monospacedDigitSystemFont(ofSize: 28, weight: .medium)
        l.textAlignment = .right
        l.adjustsFontSizeToFitWidth = true
        l.minimumScaleFactor = 0.4
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let fromUnitButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.contentHorizontalAlignment = .left
        return btn
    }()

    private let arrowLabel: UILabel = {
        let l = UILabel()
        l.text = "\u{2192}"
        l.font = .systemFont(ofSize: 16, weight: .regular)
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let toLabel: UILabel = {
        let l = UILabel()
        l.font = .monospacedDigitSystemFont(ofSize: 28, weight: .medium)
        l.textAlignment = .right
        l.adjustsFontSizeToFitWidth = true
        l.minimumScaleFactor = 0.4
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let toUnitButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.contentHorizontalAlignment = .left
        return btn
    }()

    private let swapButton: UIButton = {
        let btn = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        btn.setImage(UIImage(systemName: "arrow.up.arrow.down", withConfiguration: config), for: .normal)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.accessibilityLabel = "Swap units"
        return btn
    }()

    private let buttonGrid: UIStackView = {
        let sv = UIStackView()
        sv.axis = .vertical
        sv.distribution = .fillEqually
        sv.spacing = 4
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    // MARK: - Colors

    private struct Colors {
        static let accentBlue = UIColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 1.0)
        static let accentTeal = UIColor(red: 0.0, green: 0.749, blue: 0.647, alpha: 1.0)
        static let functionBgLight = UIColor(red: 0.65, green: 0.65, blue: 0.65, alpha: 1.0)
        static let functionBgDark = UIColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1.0)
        static let numberBgLight = UIColor(red: 0.88, green: 0.88, blue: 0.88, alpha: 1.0)
        static let numberBgDark = UIColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0)
    }

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        hapticFeedback.prepare()
        setupUI()
        setupActions()
        updateDisplay()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup UI

    private func setupUI() {
        addSubview(headerContainer)
        headerContainer.addSubview(insertButton)
        headerContainer.addSubview(closeButton)
        headerContainer.addSubview(categorySegment)

        addSubview(displayContainer)
        addSubview(buttonGrid)

        // Category segment setup
        for (i, cat) in UnitCategory.allCases.enumerated() {
            categorySegment.insertSegment(withTitle: cat.title, at: i, animated: false)
        }
        categorySegment.selectedSegmentIndex = 0

        // Display area
        let fromRow = UIView()
        fromRow.translatesAutoresizingMaskIntoConstraints = false
        let toRow = UIView()
        toRow.translatesAutoresizingMaskIntoConstraints = false

        displayContainer.addSubview(fromRow)
        displayContainer.addSubview(swapButton)
        displayContainer.addSubview(toRow)

        fromRow.addSubview(fromUnitButton)
        fromRow.addSubview(fromLabel)
        toRow.addSubview(toUnitButton)
        toRow.addSubview(toLabel)

        NSLayoutConstraint.activate([
            // Header
            headerContainer.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            headerContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            headerContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            headerContainer.heightAnchor.constraint(equalToConstant: 36),

            insertButton.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor, constant: 4),
            insertButton.centerYAnchor.constraint(equalTo: headerContainer.centerYAnchor),
            insertButton.widthAnchor.constraint(equalToConstant: 30),
            insertButton.heightAnchor.constraint(equalToConstant: 30),

            closeButton.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor, constant: -4),
            closeButton.centerYAnchor.constraint(equalTo: headerContainer.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 30),
            closeButton.heightAnchor.constraint(equalToConstant: 30),

            categorySegment.leadingAnchor.constraint(equalTo: insertButton.trailingAnchor, constant: 8),
            categorySegment.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -8),
            categorySegment.centerYAnchor.constraint(equalTo: headerContainer.centerYAnchor),
            categorySegment.heightAnchor.constraint(equalToConstant: 28),

            // Display
            displayContainer.topAnchor.constraint(equalTo: headerContainer.bottomAnchor, constant: 4),
            displayContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            displayContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            fromRow.topAnchor.constraint(equalTo: displayContainer.topAnchor),
            fromRow.leadingAnchor.constraint(equalTo: displayContainer.leadingAnchor),
            fromRow.trailingAnchor.constraint(equalTo: swapButton.leadingAnchor, constant: -8),

            swapButton.centerYAnchor.constraint(equalTo: displayContainer.centerYAnchor),
            swapButton.trailingAnchor.constraint(equalTo: displayContainer.trailingAnchor),
            swapButton.widthAnchor.constraint(equalToConstant: 30),
            swapButton.heightAnchor.constraint(equalToConstant: 30),

            toRow.topAnchor.constraint(equalTo: fromRow.bottomAnchor, constant: 2),
            toRow.leadingAnchor.constraint(equalTo: displayContainer.leadingAnchor),
            toRow.trailingAnchor.constraint(equalTo: swapButton.leadingAnchor, constant: -8),
            toRow.bottomAnchor.constraint(equalTo: displayContainer.bottomAnchor),

            // From row
            fromUnitButton.leadingAnchor.constraint(equalTo: fromRow.leadingAnchor),
            fromUnitButton.centerYAnchor.constraint(equalTo: fromRow.centerYAnchor),
            fromUnitButton.widthAnchor.constraint(equalToConstant: 36),

            fromLabel.leadingAnchor.constraint(equalTo: fromUnitButton.trailingAnchor, constant: 4),
            fromLabel.trailingAnchor.constraint(equalTo: fromRow.trailingAnchor),
            fromLabel.topAnchor.constraint(equalTo: fromRow.topAnchor),
            fromLabel.bottomAnchor.constraint(equalTo: fromRow.bottomAnchor),
            fromLabel.heightAnchor.constraint(equalToConstant: 34),

            // To row
            toUnitButton.leadingAnchor.constraint(equalTo: toRow.leadingAnchor),
            toUnitButton.centerYAnchor.constraint(equalTo: toRow.centerYAnchor),
            toUnitButton.widthAnchor.constraint(equalToConstant: 36),

            toLabel.leadingAnchor.constraint(equalTo: toUnitButton.trailingAnchor, constant: 4),
            toLabel.trailingAnchor.constraint(equalTo: toRow.trailingAnchor),
            toLabel.topAnchor.constraint(equalTo: toRow.topAnchor),
            toLabel.bottomAnchor.constraint(equalTo: toRow.bottomAnchor),
            toLabel.heightAnchor.constraint(equalToConstant: 34),

            // Button grid
            buttonGrid.topAnchor.constraint(equalTo: displayContainer.bottomAnchor, constant: 4),
            buttonGrid.centerXAnchor.constraint(equalTo: centerXAnchor),
            buttonGrid.widthAnchor.constraint(lessThanOrEqualToConstant: 500),
            buttonGrid.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 4),
            buttonGrid.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
            buttonGrid.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])

        let leadingFill = buttonGrid.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4)
        leadingFill.priority = .defaultHigh
        let trailingFill = buttonGrid.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4)
        trailingFill.priority = .defaultHigh
        NSLayoutConstraint.activate([leadingFill, trailingFill])

        buildNumpad()
    }

    private func buildNumpad() {
        let rows: [[(String, Int)]] = [
            [("7", 7), ("8", 8), ("9", 9), ("\u{232B}", 100)],
            [("4", 4), ("5", 5), ("6", 6), ("AC", 101)],
            [("1", 1), ("2", 2), ("3", 3), (".", 10)],
        ]

        for rowData in rows {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.distribution = .fillEqually
            rowStack.spacing = 4

            for (title, tag) in rowData {
                let btn = makeNumpadButton(title: title, tag: tag)
                rowStack.addArrangedSubview(btn)
            }

            buttonGrid.addArrangedSubview(rowStack)
        }

        // Last row: 0, 00, Insert
        let lastRow = UIStackView()
        lastRow.axis = .horizontal
        lastRow.distribution = .fillEqually
        lastRow.spacing = 4
        lastRow.addArrangedSubview(makeNumpadButton(title: "0", tag: 0))
        lastRow.addArrangedSubview(makeNumpadButton(title: "00", tag: 11))
        let insertBtn = makeNumpadButton(title: L("unit.insert"), tag: 300)
        insertBtn.backgroundColor = Colors.accentBlue
        insertBtn.setTitleColor(.white, for: .normal)
        lastRow.addArrangedSubview(insertBtn)
        buttonGrid.addArrangedSubview(lastRow)
    }

    private func makeNumpadButton(title: String, tag: Int) -> UIButton {
        let btn = UIButton(type: .custom)
        btn.setTitle(title, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 20, weight: .medium)
        btn.tag = tag
        btn.layer.cornerRadius = 8
        btn.clipsToBounds = true
        btn.addTarget(self, action: #selector(numpadTapped(_:)), for: .touchUpInside)
        return btn
    }

    // MARK: - Actions

    private func setupActions() {
        insertButton.addTarget(self, action: #selector(insertTapped), for: .touchUpInside)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        categorySegment.addTarget(self, action: #selector(categoryChanged), for: .valueChanged)
        swapButton.addTarget(self, action: #selector(swapTapped), for: .touchUpInside)
        fromUnitButton.addTarget(self, action: #selector(cycleFromUnit), for: .touchUpInside)
        toUnitButton.addTarget(self, action: #selector(cycleToUnit), for: .touchUpInside)
    }

    @objc private func insertTapped() {
        let result = convertedValueString()
        guard !result.isEmpty else { return }
        onInsert?(result)
        onClose?()
    }

    @objc private func closeTapped() {
        onClose?()
    }

    @objc private func categoryChanged() {
        guard let cat = UnitCategory(rawValue: categorySegment.selectedSegmentIndex) else { return }
        currentCategory = cat
        fromUnitIndex = 0
        toUnitIndex = min(1, cat.units.count - 1)
        inputValue = ""
        hapticFeedback.impactOccurred()
        updateDisplay()
    }

    @objc private func swapTapped() {
        let temp = fromUnitIndex
        fromUnitIndex = toUnitIndex
        toUnitIndex = temp
        hapticFeedback.impactOccurred()
        updateDisplay()
    }

    @objc private func cycleFromUnit() {
        let units = currentCategory.units
        fromUnitIndex = (fromUnitIndex + 1) % units.count
        if fromUnitIndex == toUnitIndex {
            fromUnitIndex = (fromUnitIndex + 1) % units.count
        }
        hapticFeedback.impactOccurred()
        updateDisplay()
    }

    @objc private func cycleToUnit() {
        let units = currentCategory.units
        toUnitIndex = (toUnitIndex + 1) % units.count
        if toUnitIndex == fromUnitIndex {
            toUnitIndex = (toUnitIndex + 1) % units.count
        }
        hapticFeedback.impactOccurred()
        updateDisplay()
    }

    @objc private func numpadTapped(_ sender: UIButton) {
        hapticFeedback.impactOccurred()
        let tag = sender.tag

        switch tag {
        case 0...9:
            inputValue += String(tag)
        case 10: // decimal point
            if !inputValue.contains(".") {
                inputValue += inputValue.isEmpty ? "0." : "."
            }
        case 11: // 00
            if !inputValue.isEmpty && inputValue != "0" {
                inputValue += "00"
            }
        case 100: // backspace
            if !inputValue.isEmpty {
                inputValue.removeLast()
            }
        case 101: // AC
            inputValue = ""
        case 300: // insert
            insertTapped()
            return
        default:
            break
        }

        updateDisplay()
    }

    // MARK: - Conversion

    private func convertedValue() -> Double? {
        guard let value = Double(inputValue), !inputValue.isEmpty else { return nil }
        let units = currentCategory.units
        guard fromUnitIndex < units.count, toUnitIndex < units.count else { return nil }

        let fromUnit = units[fromUnitIndex].1
        let toUnit = units[toUnitIndex].1
        let measurement = Measurement(value: value, unit: fromUnit)
        return measurement.converted(to: toUnit).value
    }

    private func convertedValueString() -> String {
        guard let result = convertedValue() else { return "" }
        return numberFormatter.string(from: NSNumber(value: result)) ?? String(result)
    }

    // MARK: - Display

    private func updateDisplay() {
        let units = currentCategory.units

        fromUnitButton.setTitle(units[fromUnitIndex].0, for: .normal)
        toUnitButton.setTitle(units[toUnitIndex].0, for: .normal)

        if inputValue.isEmpty {
            fromLabel.text = "0"
            toLabel.text = "0"
        } else {
            if let val = Double(inputValue) {
                fromLabel.text = numberFormatter.string(from: NSNumber(value: val)) ?? inputValue
            } else {
                fromLabel.text = inputValue
            }
            let result = convertedValueString()
            toLabel.text = result.isEmpty ? "0" : result
        }
    }

    // MARK: - Theme

    func applyTheme(_ theme: KeyboardTheme?) {
        customTheme = theme
    }

    func updateAppearance(isDark: Bool) {
        self.isDark = isDark

        if let theme = customTheme {
            backgroundColor = theme.keyboardBackground
            fromLabel.textColor = theme.keyTextColor
            toLabel.textColor = theme.keyTextColor
            arrowLabel.textColor = theme.keyTextColor.withAlphaComponent(0.5)
            insertButton.tintColor = theme.keyTextColor
            closeButton.tintColor = theme.keyTextColor
            swapButton.tintColor = theme.keyTextColor
            fromUnitButton.setTitleColor(Colors.accentTeal, for: .normal)
            toUnitButton.setTitleColor(Colors.accentTeal, for: .normal)
        } else {
            backgroundColor = isDark
                ? UIColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1.0)
                : UIColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1.0)

            let textColor: UIColor = isDark ? .white : .black
            fromLabel.textColor = textColor
            toLabel.textColor = textColor
            arrowLabel.textColor = isDark ? UIColor(white: 0.5, alpha: 1) : UIColor(white: 0.5, alpha: 1)
            insertButton.tintColor = textColor
            closeButton.tintColor = textColor
            swapButton.tintColor = textColor
            fromUnitButton.setTitleColor(Colors.accentTeal, for: .normal)
            toUnitButton.setTitleColor(Colors.accentTeal, for: .normal)
        }

        // Update numpad button colors
        for rowStack in buttonGrid.arrangedSubviews {
            guard let stack = rowStack as? UIStackView else { continue }
            for view in stack.arrangedSubviews {
                guard let btn = view as? UIButton else { continue }
                applyButtonColor(btn)
            }
        }
    }

    private func applyButtonColor(_ btn: UIButton) {
        let tag = btn.tag

        switch tag {
        case 100, 101: // function buttons
            btn.backgroundColor = isDark ? Colors.functionBgDark : Colors.functionBgLight
            btn.setTitleColor(.white, for: .normal)
        case 300: // insert
            btn.backgroundColor = Colors.accentBlue
            btn.setTitleColor(.white, for: .normal)
        default: // number buttons
            if let theme = customTheme {
                btn.backgroundColor = theme.keyBackground
                btn.setTitleColor(theme.keyTextColor, for: .normal)
            } else {
                btn.backgroundColor = isDark ? Colors.numberBgDark : Colors.numberBgLight
                btn.setTitleColor(isDark ? .white : .black, for: .normal)
            }
        }
    }
}
