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
/// Supports snapshot mode (actual keyboard geometry) and deterministic fallback.
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
        static let customInputHeight: CGFloat = 318  // 8 + 40 + 270
        static let defaultSystemAccessoryHeight: CGFloat = 76
    }

    // MARK: - Callbacks

    var onRawTouch: ((CalibrationRawTouch) -> Void)?
    var onPreferredHeightChanged: ((CGFloat) -> Void)?

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

    // MARK: - Geometry State

    private var snapshot: KeyboardGeometrySnapshot?
    private var isSnapshotMode = false
    private var customInputHeight: CGFloat = K.customInputHeight
    private var systemAccessoryHeight: CGFloat = 0
    private var systemAccessoryView: UIView?

    // MARK: - Settings

    private var hasAdditionalLanguage: Bool {
        if let snap = snapshot, isSnapshotMode, let val = snap.hasAdditionalLanguage { return val }
        return AppGroupManager.shared.bool(forKey: "additional_keyboard_language_enabled")
    }

    private var hasPeriodKey: Bool {
        if let snap = snapshot, isSnapshotMode, let val = snap.showPeriodKey { return val }
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
        loadSnapshot()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Snapshot Loading

    private func loadSnapshot() {
        let screen = UIScreen.main.bounds
        guard let snap = KeyboardGeometrySnapshot.load(),
              snap.isCompatible(screenWidth: screen.width, screenHeight: screen.height),
              snap.layoutID == "english_letters",
              snap.inputViewOriginYInScreen > 0,
              snap.inputViewHeight >= 300 else {
            isSnapshotMode = false
            #if DEBUG
            NSLog("[CALIBRATION_MIRROR_GEOMETRY] mode=fallback reason=noCompatibleSnapshot")
            #endif
            return
        }

        // Validate minimum letter keys
        let keySet = Set(snap.keyFrames.map { $0.key.lowercased() })
        let requiredKeys: Set<String> = ["q", "p", "a", "l", "z", "m", " "]
        guard requiredKeys.isSubset(of: keySet) else {
            isSnapshotMode = false
            #if DEBUG
            NSLog("[CALIBRATION_MIRROR_GEOMETRY] mode=fallback reason=missingRequiredKeys have=%@", keySet.description)
            #endif
            return
        }

        snapshot = snap
        isSnapshotMode = true
        customInputHeight = snap.inputViewHeight

        let fullSurfaceHeight = screen.height - snap.inputViewOriginYInScreen
        systemAccessoryHeight = max(0, fullSurfaceHeight - snap.inputViewHeight)
    }

    // MARK: - Preferred Height

    var preferredMirrorHeight: CGFloat {
        if isSnapshotMode, let snap = snapshot {
            return UIScreen.main.bounds.height - snap.inputViewOriginYInScreen
        }
        let bottomSafe = safeAreaInsets.bottom
        let sysHeight: CGFloat
        if bottomSafe > 0 {
            sysHeight = max(K.defaultSystemAccessoryHeight, bottomSafe + 42)
        } else {
            sysHeight = 0
        }
        return K.customInputHeight + sysHeight
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width
        guard w > 0, abs(w - lastLayoutWidth) > 0.5 else { return }
        lastLayoutWidth = w

        // Recalculate system accessory for fallback
        if !isSnapshotMode {
            let bottomSafe = safeAreaInsets.bottom
            if bottomSafe > 0 {
                systemAccessoryHeight = max(K.defaultSystemAccessoryHeight, bottomSafe + 42)
            } else {
                systemAccessoryHeight = 0
            }
        }

        rebuildFrames(width: w)
        onPreferredHeightChanged?(preferredMirrorHeight)
        logGeometry()
    }

    private func rebuildFrames(width: CGFloat) {
        subviews.forEach { $0.removeFromSuperview() }
        letterButtons.removeAll()
        allButtons.removeAll()
        buttonMeta.removeAll()
        backspaceButton = nil
        systemAccessoryView = nil

        if isSnapshotMode, let snap = snapshot {
            buildFromSnapshot(snap, width: width)
        } else {
            buildDeterministic(width: width)
        }

        // System accessory area
        if systemAccessoryHeight > 0 {
            buildSystemAccessoryArea(width: width)
        }
    }

    // MARK: - Snapshot Mode Build

    private func buildFromSnapshot(_ snap: KeyboardGeometrySnapshot, width: CGFloat) {
        let screenH = UIScreen.main.bounds.height
        let mirrorTopInScreen = screenH - (customInputHeight + systemAccessoryHeight)

        // Toolbar placeholder at top
        let toolbarY: CGFloat = 0
        let toolbarH = snap.topPadding ?? K.topPadding
        let toolbarActualH = snap.toolbarHeight ?? K.toolbarHeight
        let toolbar = UIView(frame: CGRect(x: 0, y: toolbarY, width: width, height: toolbarH + toolbarActualH))
        toolbar.backgroundColor = UIColor(white: 0.92, alpha: 1)
        addSubview(toolbar)

        // Build keys from snapshot frames
        let letterKeySet: Set<String> = Set(row0Keys + row1Keys + row2Keys)

        for kf in snap.keyFrames {
            let keyInMirrorY = kf.centerYInScreen - mirrorTopInScreen
            let keyInMirrorX = kf.centerXInScreen

            let frame = CGRect(
                x: keyInMirrorX - kf.width / 2,
                y: keyInMirrorY - kf.height / 2,
                width: kf.width,
                height: kf.height
            )

            let lowKey = kf.key.lowercased()
            let isLetter = letterKeySet.contains(lowKey)
            let isBackspaceKey = kf.key == "⌫" || kf.key == "__BACKSPACE__"

            let btn = makeKeyButton(title: kf.key, frame: frame)

            // Style non-letter keys
            if !isLetter && kf.key.count != 1 {
                btn.backgroundColor = UIColor(white: 0.75, alpha: 1)
            }
            if kf.key == " " {
                btn.setTitle("space", for: .normal)
                btn.titleLabel?.font = .systemFont(ofSize: 14)
                btn.setTitleColor(UIColor(white: 0.5, alpha: 1), for: .normal)
            }
            if kf.key == "⏎" || kf.key == "\u{23CE}" {
                btn.backgroundColor = UIColor.systemBlue
                btn.setTitleColor(.white, for: .normal)
                btn.titleLabel?.font = .systemFont(ofSize: 16)
            }

            addSubview(btn)
            allButtons.append(btn)

            if isLetter {
                letterButtons.append(btn)
                // Determine row/col from snapshot
                buttonMeta[btn] = (kf.row, kf.col, lowKey)
            }

            if isBackspaceKey {
                backspaceButton = btn
            }
        }
    }

    // MARK: - Deterministic Fallback Build

    private func buildDeterministic(width: CGFloat) {
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

        // Row 1 (ASDF)
        let row1Y = row0Y + K.keyHeight + K.keySpacingV
        buildEqualRow(keys: row1Keys, y: row1Y, height: K.keyHeight, width: width, isCalibrationTarget: true, rowIndex: 1, indent: K.row1Indent)

        // Row 2 (ZXCV)
        let row2Y = row1Y + K.keyHeight + K.keySpacingV
        buildMixedRow2(y: row2Y, width: width)

        // Bottom row
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
        let refKeyCount: CGFloat = 10
        let refSpacing = K.keySpacingH * (refKeyCount - 1)
        let refKeyWidth = (width - 2 * K.sideInset - refSpacing) / refKeyCount
        let letterKeyWidth = refKeyWidth

        let letterCount = CGFloat(row2Keys.count)
        let totalLetterWidth = letterCount * letterKeyWidth + (letterCount - 1) * K.keySpacingH
        let rowWidth = width - 2 * K.sideInset
        let leftover = rowWidth - totalLetterWidth - 2 * K.keySpacingH
        let spacerWidth = max(0, (leftover - 2 * K.wideKeyWidth) / 2)
        let shiftWidth = K.wideKeyWidth + spacerWidth
        let backspaceWidth = K.wideKeyWidth + spacerWidth

        let shiftBtn = makeKeyButton(title: "⇧", frame: CGRect(x: K.sideInset, y: y, width: shiftWidth, height: K.keyHeight))
        shiftBtn.backgroundColor = UIColor(white: 0.75, alpha: 1)
        addSubview(shiftBtn)
        allButtons.append(shiftBtn)

        let lettersStartX = K.sideInset + shiftWidth + K.keySpacingH
        for (col, key) in row2Keys.enumerated() {
            let x = lettersStartX + CGFloat(col) * (letterKeyWidth + K.keySpacingH)
            let btn = makeKeyButton(title: key, frame: CGRect(x: x, y: y, width: letterKeyWidth, height: K.keyHeight))
            addSubview(btn)
            allButtons.append(btn)
            letterButtons.append(btn)
            buttonMeta[btn] = (2, col, key)
        }

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

        let funcBtn = makeKeyButton(title: "+=♥", frame: CGRect(x: x, y: y, width: funcKeyWidth, height: K.keyHeight))
        funcBtn.backgroundColor = UIColor(white: 0.75, alpha: 1)
        funcBtn.titleLabel?.font = .systemFont(ofSize: 14)
        addSubview(funcBtn)
        allButtons.append(funcBtn)
        x += funcKeyWidth + K.keySpacingH

        if hasGlobe {
            let globeBtn = makeKeyButton(title: "🌐", frame: CGRect(x: x, y: y, width: K.globeKeyWidth, height: K.keyHeight))
            globeBtn.backgroundColor = UIColor(white: 0.75, alpha: 1)
            globeBtn.titleLabel?.font = .systemFont(ofSize: 16)
            addSubview(globeBtn)
            allButtons.append(globeBtn)
            x += K.globeKeyWidth + K.keySpacingH
        }

        let rightSideWidth: CGFloat = {
            var w: CGFloat = returnKeyWidth
            if hasPeriod { w += K.periodKeyWidth + K.keySpacingH }
            return w
        }()
        let spacebarWidth = width - K.sideInset - x - K.keySpacingH - rightSideWidth - (hasPeriod ? K.keySpacingH : 0)

        let spaceBtn = makeKeyButton(title: "space", frame: CGRect(x: x, y: y, width: max(spacebarWidth, 40), height: K.keyHeight))
        spaceBtn.backgroundColor = .white
        spaceBtn.titleLabel?.font = .systemFont(ofSize: 14)
        spaceBtn.setTitleColor(UIColor(white: 0.5, alpha: 1), for: .normal)
        addSubview(spaceBtn)
        allButtons.append(spaceBtn)
        x += max(spacebarWidth, 40) + K.keySpacingH

        if hasPeriod {
            let periodBtn = makeKeyButton(title: ".", frame: CGRect(x: x, y: y, width: K.periodKeyWidth, height: K.keyHeight))
            periodBtn.backgroundColor = UIColor(white: 0.75, alpha: 1)
            addSubview(periodBtn)
            allButtons.append(periodBtn)
            x += K.periodKeyWidth + K.keySpacingH
        }

        let returnBtn = makeKeyButton(title: "⏎", frame: CGRect(x: x, y: y, width: returnKeyWidth, height: K.keyHeight))
        returnBtn.backgroundColor = UIColor.systemBlue
        returnBtn.setTitleColor(.white, for: .normal)
        returnBtn.titleLabel?.font = .systemFont(ofSize: 16)
        addSubview(returnBtn)
        allButtons.append(returnBtn)
    }

    // MARK: - System Accessory Area

    private func buildSystemAccessoryArea(width: CGFloat) {
        let sysY = customInputHeight
        let sysView = UIView(frame: CGRect(x: 0, y: sysY, width: width, height: systemAccessoryHeight))
        sysView.backgroundColor = UIColor(white: 0.82, alpha: 1)
        sysView.isUserInteractionEnabled = false

        // Globe / input-mode icon (left side)
        let globeConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        if let globeImage = UIImage(systemName: "globe", withConfiguration: globeConfig) {
            let globeView = UIImageView(image: globeImage)
            globeView.tintColor = UIColor(white: 0.35, alpha: 1)
            globeView.contentMode = .scaleAspectFit
            globeView.frame = CGRect(x: 40, y: systemAccessoryHeight * 0.25, width: 24, height: 24)
            sysView.addSubview(globeView)
        }

        // Home indicator pill (center bottom)
        let pillWidth: CGFloat = 145
        let pillHeight: CGFloat = 5
        let pillBottomInset: CGFloat = max(8, safeAreaInsets.bottom * 0.25)
        let pill = UIView(frame: CGRect(
            x: (width - pillWidth) / 2,
            y: systemAccessoryHeight - pillHeight - pillBottomInset,
            width: pillWidth,
            height: pillHeight
        ))
        pill.backgroundColor = UIColor(white: 0.15, alpha: 0.35)
        pill.layer.cornerRadius = pillHeight / 2
        sysView.addSubview(pill)

        addSubview(sysView)
        systemAccessoryView = sysView
    }

    // MARK: - Key Button Factory

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

    // MARK: - Touch Collection

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches.sorted(by: { $0.timestamp < $1.timestamp }) {
            processTouch(touch)
        }
    }

    private func processTouch(_ touch: UITouch) {
        let point = touch.location(in: self)

        // Ignore touches in system accessory area
        if point.y >= customInputHeight {
            return
        }

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
        return CGSize(width: UIView.noIntrinsicMetric, height: preferredMirrorHeight)
    }

    // MARK: - Debug Geometry Log

    private func logGeometry() {
        #if DEBUG
        let mode = isSnapshotMode ? "snapshot" : "fallback"
        let screen = UIScreen.main.bounds
        let mirrorH = preferredMirrorHeight
        let mirrorTopY = screen.height - mirrorH

        var log = "[CALIBRATION_MIRROR_GEOMETRY]\n"
        log += "mode=\(mode)\n"
        log += "screen=\(Int(screen.width))x\(Int(screen.height))\n"
        log += "mirrorHeight=\(Int(mirrorH))\n"
        log += "customInputHeight=\(Int(customInputHeight))\n"
        log += "systemAccessoryHeight=\(Int(systemAccessoryHeight))\n"
        log += "mirrorTopYInScreen=\(Int(mirrorTopY))\n"

        for key in ["q", "a", "z", " "] {
            if let info = intendedKeyInfo(for: key) {
                log += "\(key == " " ? "space" : key)=(\(Int(info.point.x)),\(Int(info.point.y)),\(Int(info.keyWidth)))\n"
            }
        }
        NSLog("%@", log)
        #endif
    }
}
