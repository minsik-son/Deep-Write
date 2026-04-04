import UIKit

// MARK: - Calculator View

final class CalculatorView: UIView {

    // MARK: - Callbacks

    var onClose: (() -> Void)?
    var onInsert: ((String) -> Void)?

    // MARK: - Calculator State

    private enum CalcOperator {
        case add, subtract, multiply, divide
    }

    private var currentInput: String = "0"
    private var previousValue: Double = 0
    private var currentOperator: CalcOperator?
    private var shouldResetInput: Bool = false
    private var expressionString: String = ""
    private var lastResult: Double = 0
    private var hasDecimalPoint: Bool = false
    private var justPressedEquals: Bool = false
    private var isErrorState: Bool = false

    // MARK: - Number Formatter

    private let numberFormatter: NumberFormatter = {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.maximumFractionDigits = 8
        nf.minimumFractionDigits = 0
        return nf
    }()

    // MARK: - Haptic

    private let hapticFeedback = UIImpactFeedbackGenerator(style: .light)

    // MARK: - UI Components

    private let displayContainer: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let expressionLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14, weight: .regular)
        label.textAlignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let resultLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedDigitSystemFont(ofSize: 40, weight: .medium)
        label.textAlignment = .right
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.3
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
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
        btn.accessibilityLabel = "Close calculator"
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

    // MARK: - Color Constants

    private struct Colors {
        static let operatorBg = UIColor(red: 0.0, green: 0.749, blue: 0.647, alpha: 1.0)
        static let operatorText = UIColor.white
        static let equalsBg = UIColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 1.0)
        static let equalsText = UIColor.white
        static let functionBgLight = UIColor(red: 0.65, green: 0.65, blue: 0.65, alpha: 1.0)
        static let functionBgDark = UIColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1.0)
        static let functionText = UIColor.white
        static let numberBgLight = UIColor(red: 0.88, green: 0.88, blue: 0.88, alpha: 1.0)
        static let numberBgDark = UIColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0)
        static let numberTextLight = UIColor.black
        static let numberTextDark = UIColor.white
    }

    // MARK: - Button Type

    private enum ButtonType {
        case number
        case function
        case calcOperator
        case equals
    }

    // MARK: - Theme State

    private var isDark: Bool = false
    private var customTheme: KeyboardTheme?

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
        addSubview(displayContainer)
        displayContainer.addSubview(insertButton)
        displayContainer.addSubview(closeButton)
        displayContainer.addSubview(expressionLabel)
        displayContainer.addSubview(resultLabel)
        addSubview(buttonGrid)

        NSLayoutConstraint.activate([
            displayContainer.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            displayContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            displayContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),

            insertButton.topAnchor.constraint(equalTo: displayContainer.topAnchor, constant: 2),
            insertButton.leadingAnchor.constraint(equalTo: displayContainer.leadingAnchor, constant: 4),
            insertButton.widthAnchor.constraint(equalToConstant: 30),
            insertButton.heightAnchor.constraint(equalToConstant: 30),

            closeButton.topAnchor.constraint(equalTo: displayContainer.topAnchor, constant: 2),
            closeButton.trailingAnchor.constraint(equalTo: displayContainer.trailingAnchor, constant: -4),
            closeButton.widthAnchor.constraint(equalToConstant: 30),
            closeButton.heightAnchor.constraint(equalToConstant: 30),

            expressionLabel.trailingAnchor.constraint(equalTo: displayContainer.trailingAnchor, constant: -8),
            expressionLabel.leadingAnchor.constraint(equalTo: insertButton.trailingAnchor, constant: 8),
            expressionLabel.topAnchor.constraint(equalTo: insertButton.bottomAnchor, constant: 0),

            resultLabel.trailingAnchor.constraint(equalTo: displayContainer.trailingAnchor, constant: -8),
            resultLabel.leadingAnchor.constraint(equalTo: displayContainer.leadingAnchor, constant: 8),
            resultLabel.topAnchor.constraint(equalTo: expressionLabel.bottomAnchor, constant: 0),
            resultLabel.bottomAnchor.constraint(equalTo: displayContainer.bottomAnchor, constant: -2),

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

        let buttonData: [[(String, Int, ButtonType)]] = [
            [("7", 7, .number), ("8", 8, .number), ("9", 9, .number), ("\u{00F7}", 201, .calcOperator), ("\u{232B}", 100, .function)],
            [("4", 4, .number), ("5", 5, .number), ("6", 6, .number), ("\u{00D7}", 202, .calcOperator), ("AC", 101, .function)],
            [("1", 1, .number), ("2", 2, .number), ("3", 3, .number), ("\u{2212}", 203, .calcOperator), ("%", 102, .function)],
            [("\u{00B1}", 103, .function), ("0", 0, .number), (".", 10, .number), ("+", 200, .calcOperator), ("=", 300, .equals)],
        ]

        for rowData in buttonData {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.distribution = .fillEqually
            rowStack.spacing = 4

            for (title, tag, type) in rowData {
                let btn = makeCalcButton(title: title, tag: tag, type: type)
                rowStack.addArrangedSubview(btn)
            }

            buttonGrid.addArrangedSubview(rowStack)
        }
    }

    private func makeCalcButton(title: String, tag: Int, type: ButtonType) -> UIButton {
        let btn = UIButton(type: .custom)
        btn.setTitle(title, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 22, weight: .medium)
        btn.tag = tag
        btn.layer.cornerRadius = 8
        btn.clipsToBounds = true
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(calcButtonTapped(_:)), for: .touchUpInside)

        switch tag {
        case 100: btn.accessibilityLabel = "Backspace"
        case 101: btn.accessibilityLabel = "All Clear"
        case 102: btn.accessibilityLabel = "Percent"
        case 103: btn.accessibilityLabel = "Plus minus"
        case 200: btn.accessibilityLabel = "Plus"
        case 201: btn.accessibilityLabel = "Divide"
        case 202: btn.accessibilityLabel = "Multiply"
        case 203: btn.accessibilityLabel = "Minus"
        case 300: btn.accessibilityLabel = "Equals"
        default: btn.accessibilityLabel = title
        }

        return btn
    }

    // MARK: - Actions

    private func setupActions() {
        insertButton.addTarget(self, action: #selector(insertTapped), for: .touchUpInside)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
    }

    @objc private func insertTapped() {
        guard !isErrorState else { return }
        let value = resultLabel.text ?? "0"
        let cleanValue = value.replacingOccurrences(of: ",", with: "")
        onInsert?(cleanValue)
        onClose?()
    }

    @objc private func closeTapped() {
        onClose?()
    }

    @objc private func calcButtonTapped(_ sender: UIButton) {
        hapticFeedback.impactOccurred()
        let tag = sender.tag

        switch tag {
        case 0...9:
            handleNumberInput(String(tag))
        case 10:
            handleDecimalPoint()
        case 103:
            handlePlusMinus()
        case 100:
            handleBackspace()
        case 101:
            handleAllClear()
        case 102:
            handlePercent()
        case 200:
            handleOperator(.add)
        case 201:
            handleOperator(.divide)
        case 202:
            handleOperator(.multiply)
        case 203:
            handleOperator(.subtract)
        case 300:
            handleEquals()
        default:
            break
        }

        updateDisplay()
    }

    // MARK: - Calculator Logic

    private func handleNumberInput(_ digit: String) {
        if isErrorState { handleAllClear() }

        if justPressedEquals {
            previousValue = 0
            currentOperator = nil
            expressionString = ""
            justPressedEquals = false
        }

        if shouldResetInput {
            currentInput = digit
            shouldResetInput = false
            hasDecimalPoint = false
        } else {
            if currentInput == "0" && digit != "0" {
                currentInput = digit
            } else if currentInput == "0" && digit == "0" {
                // keep single 0
            } else {
                currentInput += digit
            }
        }
    }

    private func handleDecimalPoint() {
        if isErrorState { handleAllClear() }

        if shouldResetInput {
            currentInput = "0."
            shouldResetInput = false
            hasDecimalPoint = true
            return
        }

        guard !hasDecimalPoint else { return }
        currentInput += "."
        hasDecimalPoint = true
    }

    private func handlePlusMinus() {
        if isErrorState { return }
        guard currentInput != "0" else { return }

        if currentInput.hasPrefix("-") {
            currentInput = String(currentInput.dropFirst())
        } else {
            currentInput = "-" + currentInput
        }
    }

    private func handleBackspace() {
        if isErrorState { handleAllClear(); return }

        guard currentInput.count > 1 else {
            currentInput = "0"
            hasDecimalPoint = false
            return
        }

        let removed = currentInput.removeLast()
        if removed == "." {
            hasDecimalPoint = false
        }
    }

    private func handleAllClear() {
        currentInput = "0"
        previousValue = 0
        currentOperator = nil
        shouldResetInput = false
        expressionString = ""
        lastResult = 0
        hasDecimalPoint = false
        justPressedEquals = false
        isErrorState = false
    }

    private func handlePercent() {
        if isErrorState { return }
        guard let value = Double(currentInput) else { return }
        let result = value * 0.01
        currentInput = formatForInput(result)
        hasDecimalPoint = currentInput.contains(".")
    }

    private func handleOperator(_ op: CalcOperator) {
        if isErrorState { handleAllClear() }
        justPressedEquals = false

        if let existingOp = currentOperator, !shouldResetInput {
            let currentValue = Double(currentInput) ?? 0
            let result = calculate(previousValue, existingOp, currentValue)

            if result.isNaN || result.isInfinite {
                showError()
                return
            }

            previousValue = result
            currentInput = formatForInput(result)
        } else {
            previousValue = Double(currentInput) ?? 0
        }

        currentOperator = op
        shouldResetInput = true
        hasDecimalPoint = false

        let formattedPrev = formatNumber(previousValue)
        let opSymbol = operatorSymbol(op)
        expressionString = "\(formattedPrev)\(opSymbol)"
    }

    private func handleEquals() {
        if isErrorState { return }
        guard let op = currentOperator else { return }

        let currentValue = Double(currentInput) ?? 0
        let result = calculate(previousValue, op, currentValue)

        if result.isNaN || result.isInfinite {
            showError()
            return
        }

        let formattedPrev = formatNumber(previousValue)
        let formattedCurr = formatNumber(currentValue)
        let opSymbol = operatorSymbol(op)
        expressionString = "\(formattedPrev)\(opSymbol)\(formattedCurr)"

        lastResult = result
        currentInput = formatForInput(result)
        hasDecimalPoint = currentInput.contains(".")
        previousValue = result
        currentOperator = nil
        shouldResetInput = true
        justPressedEquals = true

        let resultText = formatNumber(result)
        UIAccessibility.post(notification: .announcement, argument: resultText)
    }

    private func calculate(_ lhs: Double, _ op: CalcOperator, _ rhs: Double) -> Double {
        switch op {
        case .add:      return lhs + rhs
        case .subtract: return lhs - rhs
        case .multiply: return lhs * rhs
        case .divide:
            guard rhs != 0 else { return .nan }
            return lhs / rhs
        }
    }

    private func showError() {
        isErrorState = true
        currentInput = "0"
        previousValue = 0
        currentOperator = nil
        shouldResetInput = false
        expressionString = ""
        hasDecimalPoint = false
        justPressedEquals = false

        UIAccessibility.post(notification: .announcement, argument: "Error")
    }

    private func operatorSymbol(_ op: CalcOperator) -> String {
        switch op {
        case .add:      return "+"
        case .subtract: return "\u{2212}"
        case .multiply: return "\u{00D7}"
        case .divide:   return "\u{00F7}"
        }
    }

    // MARK: - Display

    private func updateDisplay() {
        if isErrorState {
            expressionLabel.text = ""
            resultLabel.text = "Error"
            return
        }

        expressionLabel.text = expressionString

        if let value = Double(currentInput) {
            resultLabel.text = formatNumber(value)
        } else {
            resultLabel.text = currentInput
        }
    }

    private func formatNumber(_ value: Double) -> String {
        return numberFormatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private func formatForInput(_ value: Double) -> String {
        let formatted = String(format: "%.8f", value)
        var result = formatted
        if result.contains(".") {
            while result.hasSuffix("0") {
                result = String(result.dropLast())
            }
            if result.hasSuffix(".") {
                result = String(result.dropLast())
            }
        }
        return result
    }

    // MARK: - Theme

    func applyTheme(_ theme: KeyboardTheme?) {
        customTheme = theme
    }

    func updateAppearance(isDark: Bool) {
        self.isDark = isDark

        if let theme = customTheme {
            backgroundColor = theme.keyboardBackground
            expressionLabel.textColor = theme.keyTextColor.withAlphaComponent(0.6)
            resultLabel.textColor = theme.keyTextColor
            insertButton.tintColor = theme.keyTextColor
            closeButton.tintColor = theme.keyTextColor
        } else {
            backgroundColor = isDark
                ? UIColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1.0)
                : UIColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1.0)

            expressionLabel.textColor = isDark
                ? UIColor(white: 0.6, alpha: 1.0)
                : UIColor(white: 0.4, alpha: 1.0)

            resultLabel.textColor = isDark ? .white : .black
            insertButton.tintColor = isDark ? .white : .black
            closeButton.tintColor = isDark ? .white : .black
        }

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
        case 200...203:
            btn.backgroundColor = Colors.operatorBg
            btn.setTitleColor(Colors.operatorText, for: .normal)
        case 300:
            btn.backgroundColor = Colors.equalsBg
            btn.setTitleColor(Colors.equalsText, for: .normal)
        case 100...103:
            btn.backgroundColor = isDark ? Colors.functionBgDark : Colors.functionBgLight
            btn.setTitleColor(Colors.functionText, for: .normal)
        default:
            if let theme = customTheme {
                btn.backgroundColor = theme.keyBackground
                btn.setTitleColor(theme.keyTextColor, for: .normal)
            } else {
                btn.backgroundColor = isDark ? Colors.numberBgDark : Colors.numberBgLight
                btn.setTitleColor(isDark ? Colors.numberTextDark : Colors.numberTextLight, for: .normal)
            }
        }
    }
}
