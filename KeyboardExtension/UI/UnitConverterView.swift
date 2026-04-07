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

    // MARK: - Picker Target

    private enum PickerTarget {
        case from
        case to
    }

    // MARK: - State

    private var currentCategory: UnitCategory = .length
    private var fromUnitIndex: Int = 0
    private var toUnitIndex: Int = 1
    private var inputValue: String = ""
    private var activePickerTarget: PickerTarget?

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
        v.clipsToBounds = false
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

    private let fromUnitChipButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.contentEdgeInsets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 8)
        btn.layer.cornerRadius = 13
        btn.clipsToBounds = true
        let chevron = UIImage(systemName: "chevron.down",
                              withConfiguration: UIImage.SymbolConfiguration(pointSize: 9, weight: .semibold))
        btn.setImage(chevron, for: .normal)
        btn.semanticContentAttribute = .forceRightToLeft
        btn.imageEdgeInsets = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 0)
        return btn
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

    private let toUnitChipButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.contentEdgeInsets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 8)
        btn.layer.cornerRadius = 13
        btn.clipsToBounds = true
        let chevron = UIImage(systemName: "chevron.down",
                              withConfiguration: UIImage.SymbolConfiguration(pointSize: 9, weight: .semibold))
        btn.setImage(chevron, for: .normal)
        btn.semanticContentAttribute = .forceRightToLeft
        btn.imageEdgeInsets = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 0)
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

    // Picker views
    private let unitPickerContainer: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.isHidden = true
        v.layer.cornerRadius = 12
        v.layer.shadowColor = UIColor.black.cgColor
        v.layer.shadowOffset = CGSize(width: 0, height: 2)
        v.layer.shadowRadius = 8
        v.layer.shadowOpacity = 0.15
        return v
    }()

    private let unitPickerStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 6
        sv.alignment = .center
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private var pickerTopConstraint: NSLayoutConstraint?

    // Row references for picker positioning
    private let fromRow = UIView()
    private let toRow = UIView()

    // MARK: - Colors

    private struct Colors {
        static let accentBlue = UIColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 1.0)
        static let accentTeal = UIColor(red: 0.0, green: 0.749, blue: 0.647, alpha: 1.0)
        static let chipBgLight = UIColor(red: 0.90, green: 0.90, blue: 0.92, alpha: 1.0)
        static let chipBgDark = UIColor(red: 0.22, green: 0.22, blue: 0.24, alpha: 1.0)
        static let pickerBgLight = UIColor.white
        static let pickerBgDark = UIColor(red: 0.18, green: 0.18, blue: 0.20, alpha: 1.0)
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
        fromRow.translatesAutoresizingMaskIntoConstraints = false
        toRow.translatesAutoresizingMaskIntoConstraints = false

        displayContainer.addSubview(fromRow)
        displayContainer.addSubview(swapButton)
        displayContainer.addSubview(toRow)

        fromRow.addSubview(fromUnitChipButton)
        fromRow.addSubview(fromLabel)
        toRow.addSubview(toUnitChipButton)
        toRow.addSubview(toLabel)

        // Picker container (above display)
        displayContainer.addSubview(unitPickerContainer)
        unitPickerContainer.addSubview(unitPickerStack)

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

            // From row — chip + label
            fromUnitChipButton.leadingAnchor.constraint(equalTo: fromRow.leadingAnchor),
            fromUnitChipButton.centerYAnchor.constraint(equalTo: fromRow.centerYAnchor),
            fromUnitChipButton.heightAnchor.constraint(equalToConstant: 26),

            fromLabel.leadingAnchor.constraint(equalTo: fromUnitChipButton.trailingAnchor, constant: 8),
            fromLabel.trailingAnchor.constraint(equalTo: fromRow.trailingAnchor),
            fromLabel.topAnchor.constraint(equalTo: fromRow.topAnchor),
            fromLabel.bottomAnchor.constraint(equalTo: fromRow.bottomAnchor),
            fromLabel.heightAnchor.constraint(equalToConstant: 34),

            // To row — chip + label
            toUnitChipButton.leadingAnchor.constraint(equalTo: toRow.leadingAnchor),
            toUnitChipButton.centerYAnchor.constraint(equalTo: toRow.centerYAnchor),
            toUnitChipButton.heightAnchor.constraint(equalToConstant: 26),

            toLabel.leadingAnchor.constraint(equalTo: toUnitChipButton.trailingAnchor, constant: 8),
            toLabel.trailingAnchor.constraint(equalTo: toRow.trailingAnchor),
            toLabel.topAnchor.constraint(equalTo: toRow.topAnchor),
            toLabel.bottomAnchor.constraint(equalTo: toRow.bottomAnchor),
            toLabel.heightAnchor.constraint(equalToConstant: 34),

            // Picker container
            unitPickerContainer.leadingAnchor.constraint(equalTo: displayContainer.leadingAnchor),
            unitPickerContainer.trailingAnchor.constraint(lessThanOrEqualTo: displayContainer.trailingAnchor),
            unitPickerContainer.heightAnchor.constraint(equalToConstant: 36),

            unitPickerStack.topAnchor.constraint(equalTo: unitPickerContainer.topAnchor, constant: 4),
            unitPickerStack.leadingAnchor.constraint(equalTo: unitPickerContainer.leadingAnchor, constant: 6),
            unitPickerStack.trailingAnchor.constraint(equalTo: unitPickerContainer.trailingAnchor, constant: -6),
            unitPickerStack.bottomAnchor.constraint(equalTo: unitPickerContainer.bottomAnchor, constant: -4),

            // Button grid
            buttonGrid.topAnchor.constraint(equalTo: displayContainer.bottomAnchor, constant: 4),
            buttonGrid.centerXAnchor.constraint(equalTo: centerXAnchor),
            buttonGrid.widthAnchor.constraint(lessThanOrEqualToConstant: 500),
            buttonGrid.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 4),
            buttonGrid.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
            buttonGrid.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])

        // Default picker position (will be updated when shown)
        pickerTopConstraint = unitPickerContainer.topAnchor.constraint(equalTo: fromRow.bottomAnchor, constant: 2)
        pickerTopConstraint?.isActive = true

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
        fromUnitChipButton.addTarget(self, action: #selector(fromChipTapped), for: .touchUpInside)
        toUnitChipButton.addTarget(self, action: #selector(toChipTapped), for: .touchUpInside)
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
        hidePicker()
        currentCategory = cat
        fromUnitIndex = 0
        toUnitIndex = min(1, cat.units.count - 1)
        inputValue = ""
        hapticFeedback.impactOccurred()
        updateDisplay()
    }

    @objc private func swapTapped() {
        hidePicker()
        let temp = fromUnitIndex
        fromUnitIndex = toUnitIndex
        toUnitIndex = temp
        hapticFeedback.impactOccurred()
        updateDisplay()
    }

    @objc private func fromChipTapped() {
        togglePicker(for: .from)
    }

    @objc private func toChipTapped() {
        togglePicker(for: .to)
    }

    @objc private func numpadTapped(_ sender: UIButton) {
        hidePicker()
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

    // MARK: - Picker

    private func togglePicker(for target: PickerTarget) {
        if activePickerTarget == target {
            hidePicker()
        } else {
            showPicker(for: target)
        }
    }

    private func showPicker(for target: PickerTarget) {
        // If switching targets, reset immediately without animation
        if activePickerTarget != nil {
            unitPickerContainer.layer.removeAllAnimations()
            unitPickerContainer.alpha = 0
        }

        activePickerTarget = target
        rebuildPickerItems(for: target)

        // Position picker near the target row
        pickerTopConstraint?.isActive = false
        switch target {
        case .from:
            pickerTopConstraint = unitPickerContainer.topAnchor.constraint(equalTo: fromRow.bottomAnchor, constant: 2)
        case .to:
            pickerTopConstraint = unitPickerContainer.topAnchor.constraint(equalTo: toRow.bottomAnchor, constant: 2)
        }
        pickerTopConstraint?.isActive = true

        unitPickerContainer.isHidden = false
        unitPickerContainer.alpha = 0
        UIView.animate(withDuration: 0.15) {
            self.unitPickerContainer.alpha = 1
        }

        hapticFeedback.impactOccurred()
    }

    private func hidePicker() {
        guard activePickerTarget != nil else { return }
        activePickerTarget = nil
        UIView.animate(withDuration: 0.1, animations: {
            self.unitPickerContainer.alpha = 0
        }) { _ in
            self.unitPickerContainer.isHidden = true
        }
    }

    private func rebuildPickerItems(for target: PickerTarget) {
        unitPickerStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let units = currentCategory.units
        let selectedIndex = target == .from ? fromUnitIndex : toUnitIndex

        for (i, unit) in units.enumerated() {
            let btn = UIButton(type: .system)
            btn.setTitle(unit.0, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
            btn.tag = i
            btn.layer.cornerRadius = 12
            btn.clipsToBounds = true
            btn.contentEdgeInsets = UIEdgeInsets(top: 4, left: 12, bottom: 4, right: 12)
            btn.addTarget(self, action: #selector(pickerItemTapped(_:)), for: .touchUpInside)

            if i == selectedIndex {
                btn.backgroundColor = Colors.accentTeal
                btn.setTitleColor(.white, for: .normal)
            } else {
                btn.backgroundColor = isDark ? Colors.chipBgDark : Colors.chipBgLight
                btn.setTitleColor(isDark ? .white : .black, for: .normal)
            }

            unitPickerStack.addArrangedSubview(btn)
        }
    }

    @objc private func pickerItemTapped(_ sender: UIButton) {
        guard let target = activePickerTarget else { return }
        let newIndex = sender.tag

        switch target {
        case .from:
            if newIndex == toUnitIndex {
                toUnitIndex = fromUnitIndex
            }
            fromUnitIndex = newIndex
        case .to:
            if newIndex == fromUnitIndex {
                fromUnitIndex = toUnitIndex
            }
            toUnitIndex = newIndex
        }

        hapticFeedback.impactOccurred()
        hidePicker()
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

        fromUnitChipButton.setTitle(units[fromUnitIndex].0, for: .normal)
        toUnitChipButton.setTitle(units[toUnitIndex].0, for: .normal)

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

        applyChipStyle(fromUnitChipButton)
        applyChipStyle(toUnitChipButton)
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
            insertButton.tintColor = theme.keyTextColor
            closeButton.tintColor = theme.keyTextColor
            swapButton.tintColor = theme.keyTextColor
        } else {
            backgroundColor = isDark
                ? UIColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1.0)
                : UIColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1.0)

            let textColor: UIColor = isDark ? .white : .black
            fromLabel.textColor = textColor
            toLabel.textColor = textColor
            insertButton.tintColor = textColor
            closeButton.tintColor = textColor
            swapButton.tintColor = textColor
        }

        applyChipStyle(fromUnitChipButton)
        applyChipStyle(toUnitChipButton)

        unitPickerContainer.backgroundColor = isDark ? Colors.pickerBgDark : Colors.pickerBgLight

        // Update numpad button colors
        for rowStack in buttonGrid.arrangedSubviews {
            guard let stack = rowStack as? UIStackView else { continue }
            for view in stack.arrangedSubviews {
                guard let btn = view as? UIButton else { continue }
                applyButtonColor(btn)
            }
        }
    }

    private func applyChipStyle(_ chip: UIButton) {
        chip.backgroundColor = isDark ? Colors.chipBgDark : Colors.chipBgLight
        chip.setTitleColor(Colors.accentTeal, for: .normal)
        chip.tintColor = Colors.accentTeal
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
