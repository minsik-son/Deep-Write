import UIKit

// Keep these metrics in sync with KeyboardLayoutView.Layout.

/// Calibration raw touch — mirror에서 VC로 전달하는 최소 데이터
struct CalibrationRawTouch {
    let timestamp: TimeInterval
    let pointInKeyboard: CGPoint
    let actualKey: String?
    let actualRow: Int?
    let actualCol: Int?
    let actualSlotID: String?
    let actualCenterInKeyboard: CGPoint?
    let isBackspace: Bool
}

/// Calibration tap sample (VC가 intended char 매칭 후 생성)
struct CalibrationTapSample {
    let intendedSlotID: String
    let intendedRow: Int
    let intendedCol: Int
    let intendedKey: String
    let actualSlotID: String?
    let actualKey: String?
    let actualPointInKeyboard: CGPoint
    let intendedCenterInKeyboard: CGPoint
    let deltaX: Float
    let deltaY: Float
    let isExactKey: Bool
}

/// Intended key lookup result
struct CalibrationIntendedKeyInfo {
    let point: CGPoint
    let row: Int
    let col: Int
    let keyWidth: CGFloat
}

/// Real-size keyboard mirror for touch calibration (English QWERTY only).
final class CalibrationKeyboardMirrorView: UIView {

    // MARK: - Layout Constants (sync with KeyboardLayoutView.Layout)

    private struct K {
        static let keyHeight: CGFloat = 46
        static let numberRowHeight: CGFloat = 40
        static let keySpacingH: CGFloat = 6
        static let keySpacingV: CGFloat = 10
        static let numberRowSpacingV: CGFloat = 8
        static let sideInset: CGFloat = 3
        static let topInset: CGFloat = 4
        static let bottomInset: CGFloat = 4
        static let cornerRadius: CGFloat = 5
        static let toolbarHeight: CGFloat = 40
        static let topPadding: CGFloat = 8
        static let row1Indent: CGFloat = 18
        static let wideKeyWidth: CGFloat = 42
        static let globeKeyWidth: CGFloat = 50
        static let periodKeyWidth: CGFloat = 34
        static let returnKeyBaseWidth: CGFloat = 74
    }

    // MARK: - Callbacks

    /// Raw touch event → VC로 전달 (VC가 intended char 매칭)
    var onRawTouch: ((CalibrationRawTouch) -> Void)?

    // MARK: - Key Data

    private let row0Keys = ["q","w","e","r","t","y","u","i","o","p"]
    private let row1Keys = ["a","s","d","f","g","h","j","k","l"]
    private let row2Keys = ["z","x","c","v","b","n","m"]
    private let numberRowKeys = ["1","2","3","4","5","6","7","8","9","0"]

    private var letterButtons: [UIButton] = []
    private var allButtons: [UIButton] = []
    private var buttonMeta: [UIButton: (row: Int, col: Int, key: String)] = [:]
    private var backspaceButton: UIButton?
    private var lastLayoutWidth: CGFloat = 0

    // MARK: - Settings

    private var hasAdditionalLanguage: Bool {
        AppGroupManager.shared.bool(forKey: "additional_keyboard_language_enabled")
    }

    private var hasPeriodKey: Bool {
        let defaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier)
        if defaults?.object(forKey: AppConstants.UserDefaultsKeys.showPeriodKey) == nil {
            return true
        }
        return AppGroupManager.shared.bool(forKey: AppConstants.UserDefaultsKeys.showPeriodKey)
    }

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isUserInteractionEnabled = true
        backgroundColor = UIColor(white: 0.82, alpha: 1)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width
        guard w > 0, abs(w - lastLayoutWidth) > 0.5 else { return }
        lastLayoutWidth = w
        rebuildFrames(width: w)
    }

    private func rebuildFrames(width: CGFloat) {
        subviews.forEach { $0.removeFromSuperview() }
        letterButtons.removeAll()
        allButtons.removeAll()
        buttonMeta.removeAll()
        backspaceButton = nil

        let keyAreaTop = K.topPadding + K.toolbarHeight

        // Toolbar placeholder
        let toolbar = UIView(frame: CGRect(x: 0, y: K.topPadding, width: width, height: K.toolbarHeight))
        toolbar.backgroundColor = UIColor(white: 0.92, alpha: 1)
        addSubview(toolbar)

        // Number row
        let numRowY = keyAreaTop + K.topInset
        buildEqualRow(keys: numberRowKeys, y: numRowY, height: K.numberRowHeight, width: width, isCalibrationTarget: false, rowIndex: -1)

        // Row 0 (QWERTY)
        let row0Y = numRowY + K.numberRowHeight + K.numberRowSpacingV
        buildEqualRow(keys: row0Keys, y: row0Y, height: K.keyHeight, width: width, isCalibrationTarget: true, rowIndex: 0)

        // Row 1 (ASDF) — indented
        let row1Y = row0Y + K.keyHeight + K.keySpacingV
        buildEqualRow(keys: row1Keys, y: row1Y, height: K.keyHeight, width: width, isCalibrationTarget: true, rowIndex: 1, indent: K.row1Indent)

        // Row 2 (ZXCV) — with shift/backspace (real keyboard geometry)
        let row2Y = row1Y + K.keyHeight + K.keySpacingV
        buildMixedRow2(y: row2Y, width: width)

        // Bottom row — real keys matching KeyboardLayoutView
        let bottomY = row2Y + K.keyHeight + K.keySpacingV
        buildBottomRow(y: bottomY, width: width)
    }

    private func buildEqualRow(keys: [String], y: CGFloat, height: CGFloat, width: CGFloat, isCalibrationTarget: Bool, rowIndex: Int, indent: CGFloat = 0) {
        let count = CGFloat(keys.count)
        let totalSpacing = K.keySpacingH * (count - 1)
        let availableWidth = width - 2 * K.sideInset - 2 * indent - totalSpacing
        let keyWidth = availableWidth / count

        for (col, key) in keys.enumerated() {
            let x = K.sideInset + indent + CGFloat(col) * (keyWidth + K.keySpacingH)
            let btn = makeKeyButton(title: key, frame: CGRect(x: x, y: y, width: keyWidth, height: height))
            addSubview(btn)
            allButtons.append(btn)
            if isCalibrationTarget {
                letterButtons.append(btn)
                buttonMeta[btn] = (rowIndex, col, key)
            }
        }
    }

    private func buildMixedRow2(y: CGFloat, width: CGFloat) {
        // Match real KeyboardLayoutView.buildMixedRow logic:
        // Letter key width = reference 10-key row key width
        // Spacer distributes leftover evenly between shift and backspace
        let refKeyCount: CGFloat = 10
        let refSpacing = K.keySpacingH * (refKeyCount - 1)
        let refKeyWidth = (width - 2 * K.sideInset - refSpacing) / refKeyCount
        let letterKeyWidth = refKeyWidth

        let letterCount = CGFloat(row2Keys.count)
        let totalLetterWidth = letterCount * letterKeyWidth + (letterCount - 1) * K.keySpacingH

        // Leftover = total row width - sideInsets - letters - 2 spacing gaps (shift-letters, letters-backspace)
        let rowWidth = width - 2 * K.sideInset
        let leftover = rowWidth - totalLetterWidth - 2 * K.keySpacingH
        // Each spacer gets half of (leftover - 2 * wideKeyWidth)
        let spacerWidth = max(0, (leftover - 2 * K.wideKeyWidth) / 2)
        let shiftWidth = K.wideKeyWidth + spacerWidth
        let backspaceWidth = K.wideKeyWidth + spacerWidth

        // Shift
        let shiftBtn = makeKeyButton(title: "⇧", frame: CGRect(x: K.sideInset, y: y, width: shiftWidth, height: K.keyHeight))
        shiftBtn.backgroundColor = UIColor(white: 0.75, alpha: 1)
        addSubview(shiftBtn)
        allButtons.append(shiftBtn)

        // Letter keys
        let lettersStartX = K.sideInset + shiftWidth + K.keySpacingH
        for (col, key) in row2Keys.enumerated() {
            let x = lettersStartX + CGFloat(col) * (letterKeyWidth + K.keySpacingH)
            let btn = makeKeyButton(title: key, frame: CGRect(x: x, y: y, width: letterKeyWidth, height: K.keyHeight))
            addSubview(btn)
            allButtons.append(btn)
            letterButtons.append(btn)
            buttonMeta[btn] = (2, col, key)
        }

        // Backspace
        let bsX = width - K.sideInset - backspaceWidth
        let bsBtn = makeKeyButton(title: "⌫", frame: CGRect(x: bsX, y: y, width: backspaceWidth, height: K.keyHeight))
        bsBtn.backgroundColor = UIColor(white: 0.75, alpha: 1)
        addSubview(bsBtn)
        allButtons.append(bsBtn)
        backspaceButton = bsBtn
    }

    private func buildBottomRow(y: CGFloat, width: CGFloat) {
        let hasGlobe = hasAdditionalLanguage
        let hasPeriod = hasPeriodKey

        let funcKeyWidth: CGFloat = hasGlobe ? 50 : 50 + K.globeKeyWidth + K.keySpacingH
        let returnKeyWidth: CGFloat = hasPeriod ? K.returnKeyBaseWidth : (K.returnKeyBaseWidth + K.periodKeyWidth + K.keySpacingH)

        var x = K.sideInset

        // Function key (+=♥)
        let funcBtn = makeKeyButton(title: "+=♥", frame: CGRect(x: x, y: y, width: funcKeyWidth, height: K.keyHeight))
        funcBtn.backgroundColor = UIColor(white: 0.75, alpha: 1)
        funcBtn.titleLabel?.font = .systemFont(ofSize: 14)
        addSubview(funcBtn)
        allButtons.append(funcBtn)
        x += funcKeyWidth + K.keySpacingH

        // Globe key (if additional language enabled)
        if hasGlobe {
            let globeBtn = makeKeyButton(title: "🌐", frame: CGRect(x: x, y: y, width: K.globeKeyWidth, height: K.keyHeight))
            globeBtn.backgroundColor = UIColor(white: 0.75, alpha: 1)
            globeBtn.titleLabel?.font = .systemFont(ofSize: 16)
            addSubview(globeBtn)
            allButtons.append(globeBtn)
            x += K.globeKeyWidth + K.keySpacingH
        }

        // Calculate spacebar width (flexible)
        let rightSideWidth: CGFloat = {
            var w: CGFloat = returnKeyWidth
            if hasPeriod {
                w += K.periodKeyWidth + K.keySpacingH
            }
            return w
        }()
        let spacebarWidth = width - K.sideInset - x - K.keySpacingH - rightSideWidth - K.keySpacingH * (hasPeriod ? 1 : 0)

        // Spacebar
        let spaceBtn = makeKeyButton(title: "space", frame: CGRect(x: x, y: y, width: max(spacebarWidth, 40), height: K.keyHeight))
        spaceBtn.backgroundColor = .white
        spaceBtn.titleLabel?.font = .systemFont(ofSize: 14)
        spaceBtn.setTitleColor(UIColor(white: 0.5, alpha: 1), for: .normal)
        addSubview(spaceBtn)
        allButtons.append(spaceBtn)
        x += max(spacebarWidth, 40) + K.keySpacingH

        // Period key
        if hasPeriod {
            let periodBtn = makeKeyButton(title: ".", frame: CGRect(x: x, y: y, width: K.periodKeyWidth, height: K.keyHeight))
            periodBtn.backgroundColor = UIColor(white: 0.75, alpha: 1)
            addSubview(periodBtn)
            allButtons.append(periodBtn)
            x += K.periodKeyWidth + K.keySpacingH
        }

        // Return key
        let returnBtn = makeKeyButton(title: "⏎", frame: CGRect(x: x, y: y, width: returnKeyWidth, height: K.keyHeight))
        returnBtn.backgroundColor = UIColor.systemBlue
        returnBtn.setTitleColor(.white, for: .normal)
        returnBtn.titleLabel?.font = .systemFont(ofSize: 16)
        addSubview(returnBtn)
        allButtons.append(returnBtn)
    }

    private func makeKeyButton(title: String, frame: CGRect) -> UIButton {
        let btn = UIButton(frame: frame)
        btn.setTitle(title, for: .normal)
        btn.setTitleColor(.black, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: title.count == 1 && title.first?.isLetter == true ? 22 : 16)
        btn.backgroundColor = .white
        btn.layer.cornerRadius = K.cornerRadius
        btn.layer.shadowColor = UIColor.black.cgColor
        btn.layer.shadowOffset = CGSize(width: 0, height: 1)
        btn.layer.shadowOpacity = 0.15
        btn.layer.shadowRadius = 0.5
        btn.isUserInteractionEnabled = false
        return btn
    }

    // MARK: - Intended Key Lookup (frame-based)

    func intendedKeyInfo(for key: String) -> CalibrationIntendedKeyInfo? {
        let lowered = key.lowercased()
        for (btn, meta) in buttonMeta {
            if meta.key == lowered {
                return CalibrationIntendedKeyInfo(
                    point: CGPoint(x: btn.frame.midX, y: btn.frame.midY),
                    row: meta.row,
                    col: meta.col,
                    keyWidth: btn.frame.width
                )
            }
        }
        return nil
    }

    // MARK: - Touch Collection (all touches, no blocking)

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches.sorted(by: { $0.timestamp < $1.timestamp }) {
            processTouch(touch)
        }
    }

    private func processTouch(_ touch: UITouch) {
        let point = touch.location(in: self)

        // Backspace check
        if let bs = backspaceButton, bs.frame.contains(point) {
            onRawTouch?(CalibrationRawTouch(
                timestamp: touch.timestamp,
                pointInKeyboard: point,
                actualKey: nil, actualRow: nil, actualCol: nil, actualSlotID: nil, actualCenterInKeyboard: nil,
                isBackspace: true
            ))
            flashButton(bs)
            return
        }

        // Find actual key
        let actualBtn = findNearestLetterButton(at: point)
        let meta = actualBtn.flatMap { buttonMeta[$0] }

        // Reject if too far from any letter key
        if let nearest = actualBtn {
            let center = CGPoint(x: nearest.frame.midX, y: nearest.frame.midY)
            let dist = max(abs(point.x - center.x), abs(point.y - center.y))
            let maxDist = max(nearest.frame.width, nearest.frame.height) * 1.5
            guard dist <= maxDist else {
                let gen = UIImpactFeedbackGenerator(style: .light)
                gen.impactOccurred()
                return
            }
        }

        let raw = CalibrationRawTouch(
            timestamp: touch.timestamp,
            pointInKeyboard: point,
            actualKey: meta?.key,
            actualRow: meta?.row,
            actualCol: meta?.col,
            actualSlotID: meta.map { TouchCalibrationSlotID.make(row: $0.row, col: $0.col) },
            actualCenterInKeyboard: actualBtn.map { CGPoint(x: $0.frame.midX, y: $0.frame.midY) },
            isBackspace: false
        )
        onRawTouch?(raw)

        if let btn = actualBtn {
            flashButton(btn)
        }
    }

    private func flashButton(_ btn: UIButton) {
        let original = btn.backgroundColor ?? .white
        btn.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.15)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            btn.backgroundColor = original
        }
    }

    private func findNearestLetterButton(at point: CGPoint) -> UIButton? {
        for btn in letterButtons {
            if btn.frame.contains(point) { return btn }
        }
        var closest: UIButton?
        var minDist: CGFloat = .greatestFiniteMagnitude
        for btn in letterButtons {
            let dist = hypot(point.x - btn.frame.midX, point.y - btn.frame.midY)
            if dist < minDist { minDist = dist; closest = btn }
        }
        return closest
    }

    // MARK: - Intrinsic Size

    override var intrinsicContentSize: CGSize {
        let keyAreaHeight = K.topInset + K.numberRowHeight + K.numberRowSpacingV + K.keyHeight * 4 + K.keySpacingV * 3 + K.bottomInset
        return CGSize(width: UIView.noIntrinsicMetric, height: K.topPadding + K.toolbarHeight + keyAreaHeight)
    }
}
