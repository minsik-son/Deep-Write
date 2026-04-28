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

/// Real-size keyboard mirror for touch calibration (English QWERTY only).
final class CalibrationKeyboardMirrorView: UIView {

    // MARK: - Layout Constants (sync with KeyboardLayoutView.Layout)

    private struct L {
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
        // Remove existing if any
        subviews.forEach { $0.removeFromSuperview() }
        letterButtons.removeAll()
        allButtons.removeAll()
        buttonMeta.removeAll()
        backspaceButton = nil

        let keyAreaTop = L.topPadding + L.toolbarHeight

        // Toolbar placeholder
        let toolbar = UIView(frame: CGRect(x: 0, y: L.topPadding, width: width, height: L.toolbarHeight))
        toolbar.backgroundColor = UIColor(white: 0.92, alpha: 1)
        addSubview(toolbar)

        // Number row
        let numRowY = keyAreaTop + L.topInset
        buildEqualRow(keys: numberRowKeys, y: numRowY, height: L.numberRowHeight, width: width, isCalibrationTarget: false, rowIndex: -1)

        // Row 0 (QWERTY)
        let row0Y = numRowY + L.numberRowHeight + L.numberRowSpacingV
        buildEqualRow(keys: row0Keys, y: row0Y, height: L.keyHeight, width: width, isCalibrationTarget: true, rowIndex: 0)

        // Row 1 (ASDF) — indented
        let row1Y = row0Y + L.keyHeight + L.keySpacingV
        buildEqualRow(keys: row1Keys, y: row1Y, height: L.keyHeight, width: width, isCalibrationTarget: true, rowIndex: 1, indent: L.row1Indent)

        // Row 2 (ZXCV) — with shift/backspace
        let row2Y = row1Y + L.keyHeight + L.keySpacingV
        buildMixedRow2(y: row2Y, width: width)

        // Bottom row placeholder
        let bottomY = row2Y + L.keyHeight + L.keySpacingV
        let bar = UIView(frame: CGRect(x: L.sideInset, y: bottomY, width: width - 2 * L.sideInset, height: L.keyHeight))
        bar.backgroundColor = UIColor(white: 0.88, alpha: 1)
        bar.layer.cornerRadius = L.cornerRadius
        addSubview(bar)
    }

    private func buildEqualRow(keys: [String], y: CGFloat, height: CGFloat, width: CGFloat, isCalibrationTarget: Bool, rowIndex: Int, indent: CGFloat = 0) {
        let count = CGFloat(keys.count)
        let totalSpacing = L.keySpacingH * (count - 1)
        let availableWidth = width - 2 * L.sideInset - 2 * indent - totalSpacing
        let keyWidth = availableWidth / count

        for (col, key) in keys.enumerated() {
            let x = L.sideInset + indent + CGFloat(col) * (keyWidth + L.keySpacingH)
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
        let row0KeyCount: CGFloat = 10
        let row0Spacing = L.keySpacingH * (row0KeyCount - 1)
        let row0KeyWidth = (width - 2 * L.sideInset - row0Spacing) / row0KeyCount
        let letterKeyWidth = row0KeyWidth

        let totalLetterWidth = CGFloat(row2Keys.count) * letterKeyWidth + CGFloat(row2Keys.count - 1) * L.keySpacingH
        let sideKeyWidth = (width - 2 * L.sideInset - totalLetterWidth - 2 * L.keySpacingH) / 2

        // Shift placeholder
        let shiftBtn = makeKeyButton(title: "⇧", frame: CGRect(x: L.sideInset, y: y, width: sideKeyWidth, height: L.keyHeight))
        shiftBtn.backgroundColor = UIColor(white: 0.75, alpha: 1)
        addSubview(shiftBtn)
        allButtons.append(shiftBtn)

        // Letter keys
        let lettersStartX = L.sideInset + sideKeyWidth + L.keySpacingH
        for (col, key) in row2Keys.enumerated() {
            let x = lettersStartX + CGFloat(col) * (letterKeyWidth + L.keySpacingH)
            let btn = makeKeyButton(title: key, frame: CGRect(x: x, y: y, width: letterKeyWidth, height: L.keyHeight))
            addSubview(btn)
            allButtons.append(btn)
            letterButtons.append(btn)
            buttonMeta[btn] = (2, col, key)
        }

        // Backspace
        let bsX = lettersStartX + CGFloat(row2Keys.count) * (letterKeyWidth + L.keySpacingH)
        let bsBtn = makeKeyButton(title: "⌫", frame: CGRect(x: bsX, y: y, width: sideKeyWidth, height: L.keyHeight))
        bsBtn.backgroundColor = UIColor(white: 0.75, alpha: 1)
        addSubview(bsBtn)
        allButtons.append(bsBtn)
        backspaceButton = bsBtn
    }

    private func makeKeyButton(title: String, frame: CGRect) -> UIButton {
        let btn = UIButton(frame: frame)
        btn.setTitle(title, for: .normal)
        btn.setTitleColor(.black, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: title.count == 1 && title.first?.isLetter == true ? 22 : 16)
        btn.backgroundColor = .white
        btn.layer.cornerRadius = L.cornerRadius
        btn.layer.shadowColor = UIColor.black.cgColor
        btn.layer.shadowOffset = CGSize(width: 0, height: 1)
        btn.layer.shadowOpacity = 0.15
        btn.layer.shadowRadius = 0.5
        btn.isUserInteractionEnabled = false
        return btn
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
            // Brief backspace visual feedback
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
                // Accidental tap — light haptic only
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

        // Brief actual key visual feedback (no blocking animation)
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
        let keyAreaHeight = L.topInset + L.numberRowHeight + L.numberRowSpacingV + L.keyHeight * 4 + L.keySpacingV * 3 + L.bottomInset
        return CGSize(width: UIView.noIntrinsicMetric, height: L.topPadding + L.toolbarHeight + keyAreaHeight)
    }
}
