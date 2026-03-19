import UIKit

enum KeyboardLanguage: String, CaseIterable {
    case english = "en"
    case korean = "ko"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case italian = "it"
    case russian = "ru"

    var displayName: String {
        switch self {
        case .english: return "English"
        case .korean: return "한국어"
        case .spanish: return "Español"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .italian: return "Italiano"
        case .russian: return "Русский"
        }
    }

    var shortLabel: String {
        switch self {
        case .english: return "A"
        case .korean: return "한"
        case .spanish: return "ES"
        case .french: return "FR"
        case .german: return "DE"
        case .italian: return "IT"
        case .russian: return "RU"
        }
    }

    var isLatinBased: Bool {
        return self != .korean && self != .russian
    }
}

enum KeyboardPage {
    case letters
    case symbols1
    case symbols2
}

// MARK: - KeyboardLayoutView

class KeyboardLayoutView: UIView {

    var onKeyTap: ((String) -> Void)?
    var onLanguageChanged: ((KeyboardLanguage) -> Void)?
    var onCursorMove: ((Int, Int) -> Void)?  // (horizontal, vertical)
    var onTrackpadModeChanged: ((Bool) -> Void)?

    // Return key appearance — set by controller
    var returnKeyDisplayName: String = L("keyboard.return.go") {
        didSet { if oldValue != returnKeyDisplayName { buildKeyboard() } }
    }
    var returnKeyIsBlue: Bool = true {
        didSet { if oldValue != returnKeyIsBlue { buildKeyboard() } }
    }

    // Mode-aware return key override (Proposal 03)
    private var returnKeyModeOverride: KeyboardMode?
    private var returnKeyHasText: Bool = true

    var showNumberRow: Bool = true {
        didSet { if oldValue != showNumberRow { buildKeyboard() } }
    }

    var pairedLanguage: KeyboardLanguage = .korean {
        didSet { if oldValue != pairedLanguage { buildKeyboard() } }
    }

    private var currentLanguage: KeyboardLanguage = .english
    private var currentPage: KeyboardPage = .letters
    private var isShifted = false
    private var isDark = false
    private var pendingBuildWork: DispatchWorkItem?
    private var customTheme: KeyboardTheme?
    private var gradientLayer: CAGradientLayer?
    private var patternImageView: UIImageView?
    private var woodTileImageView: UIImageView?
    private var matrixRainView: MatrixRainView?
    private var mercuryRippleView: MercuryRippleView?
    private var stardustView: StardustView?
    private var snowfallView: SnowfallView?
    private var cherryBlossomView: CherryBlossomView?
    private var isMemoryConstrained = false

    // Mercury Ripple 렌즈 굴절 애니메이션
    private var lensDisplayLink: CADisplayLink?
    private var isLensAnimationActive = false
    private var cachedButtonCentersInRippleView: [(button: UIButton, center: CGPoint)] = []

    // Matrix Pulse 웨이브 애니메이션
    private var waveDisplayLink: CADisplayLink?
    private var waveStartTime: CFTimeInterval = 0
    private var cachedKeyProjections: [(button: UIButton, projection: CGFloat)] = []
    private var isWaveAnimationActive = false

    // MARK: - Edge Glow Animation State
    private var edgeGlowDisplayLink: CADisplayLink?
    private var edgeGlowStartTime: CFTimeInterval = 0
    private var isEdgeGlowAnimationActive = false
    private var edgeGlowState: EdgeGlowState = .idle
    private var edgeGlowLastKeypressTime: CFTimeInterval = 0
    private var edgeGlowIdleTransition: CGFloat = 1.0  // 0.0=typing, 1.0=idle (부드러운 전환용)
    private var edgeGlowFlashedButtons: [(button: UIButton, flashTime: CFTimeInterval)] = []

    private enum EdgeGlowState {
        case idle       // 웨이브 흐름
        case typing     // dim + 키 번쩍
    }

    // Backspace long-press repeat
    private var backspaceTimer: Timer?
    private var backspaceRepeatTimer: Timer?

    // Space bar trackpad cursor mode
    private var isTrackpadMode = false
    private var trackpadLastX: CGFloat = 0
    private var trackpadLastY: CGFloat = 0
    private var trackpadAccumulator: CGFloat = 0
    private var trackpadAccumulatorY: CGFloat = 0
    private let trackpadSensitivity: CGFloat = 8   // points per character move
    private let trackpadSensitivityY: CGFloat = 20  // points per line move (higher = slower)
    private let hapticGenerator = UIImpactFeedbackGenerator(style: .light)

    // Axis locking for trackpad
    private enum TrackpadAxis { case none, horizontal, vertical }
    private var lockedAxis: TrackpadAxis = .none
    private var trackpadStartX: CGFloat = 0
    private var trackpadStartY: CGFloat = 0
    private let axisLockThreshold: CGFloat = 10
    private let axisUnlockThreshold: CGFloat = 20

    // CADisplayLink for smooth cursor movement
    private var displayLink: CADisplayLink?

    // Trackpad haptic (lighter than key tap)
    private let selectionHaptic = UISelectionFeedbackGenerator()

    // MARK: - Layout Constants

    // Total = 310pt (toolbar 40 + key area 270).
    // Key area 270pt: topInset(4) + numRow(40) + gap(8) + 3×keyH(46) + 3×rowGap(10) + bottomRow(46) + bottomInset(4)
    private struct Layout {
        static let keyHeight: CGFloat = 46
        static let numberRowHeight: CGFloat = 40
        static let keySpacingH: CGFloat = 6
        static let keySpacingV: CGFloat = 10
        static let numberRowSpacingV: CGFloat = 8
        static let sideInset: CGFloat = 3
        static let topInset: CGFloat = 4
        static let bottomInset: CGFloat = 4
        static let cornerRadius: CGFloat = 5
        static let letterFontSize: CGFloat = 22
        static let specialFontSize: CGFloat = 15
        static let returnFontSize: CGFloat = 15
        static let spaceFontSize: CGFloat = 14
        static let symbolFontSize: CGFloat = 20
    }

    // MARK: - Key Identifiers

    static let shiftKey       = "\u{21E7}"    // ⇧
    static let backKey        = "\u{232B}"    // ⌫
    static let returnKey      = "\u{23CE}"    // ⏎
    static let langKR         = "\u{D55C}"    // 한
    static let langEN         = "EN"
    static let symbolKey      = "123"         // Switch to symbols
    static let moreSymKey     = "#+="         // Switch to more symbols
    static let abcKey         = "ABC"         // Switch back to letters
    static let symbolToggleKey = "+=♥"       // Switch to symbols (bottom row)
    static let globeLangKey   = "__GLOBE_A__" // Globe + language switch

    // MARK: - Key Layouts

    // ── Letter layouts ──

    private static let numberRow: [String] = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]

    private static let englishRows: [[String]] = [
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
        ["\u{21E7}", "z", "x", "c", "v", "b", "n", "m", "\u{232B}"],
        ["+=♥", "__GLOBE_A__", " ", ".", "\u{23CE}"]
    ]

    private static let englishShiftRows: [[String]] = [
        ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"],
        ["A", "S", "D", "F", "G", "H", "J", "K", "L"],
        ["\u{21E7}", "Z", "X", "C", "V", "B", "N", "M", "\u{232B}"],
        ["+=♥", "__GLOBE_A__", " ", ".", "\u{23CE}"]
    ]

    private static let koreanRows: [[String]] = [
        ["\u{3142}", "\u{3148}", "\u{3137}", "\u{3131}", "\u{3145}",
         "\u{315B}", "\u{3155}", "\u{3151}", "\u{3150}", "\u{3154}"],
        ["\u{3141}", "\u{3134}", "\u{3147}", "\u{3139}", "\u{314E}",
         "\u{3157}", "\u{3153}", "\u{314F}", "\u{3163}"],
        ["\u{21E7}", "\u{314B}", "\u{314C}", "\u{314A}", "\u{314D}",
         "\u{3160}", "\u{315C}", "\u{3161}", "\u{232B}"],
        ["+=♥", "__GLOBE_A__", " ", ".", "\u{23CE}"]
    ]

    private static let koreanShiftRows: [[String]] = [
        ["\u{3143}", "\u{3149}", "\u{3138}", "\u{3132}", "\u{3146}",
         "\u{315B}", "\u{3155}", "\u{3151}", "\u{3152}", "\u{3156}"],
        ["\u{3141}", "\u{3134}", "\u{3147}", "\u{3139}", "\u{314E}",
         "\u{3157}", "\u{3153}", "\u{314F}", "\u{3163}"],
        ["\u{21E7}", "\u{314B}", "\u{314C}", "\u{314A}", "\u{314D}",
         "\u{3160}", "\u{315C}", "\u{3161}", "\u{232B}"],
        ["+=♥", "__GLOBE_A__", " ", ".", "\u{23CE}"]
    ]

    // ── Russian ЙЦУКЕН layouts ──

    private static let russianRows: [[String]] = [
        ["й", "ц", "у", "к", "е", "н", "г", "ш", "щ", "з", "х"],
        ["ф", "ы", "в", "а", "п", "р", "о", "л", "д", "ж", "э"],
        ["\u{21E7}", "я", "ч", "с", "м", "и", "т", "ь", "б", "ю", "\u{232B}"],
        ["+=♥", "__GLOBE_A__", " ", ".", "\u{23CE}"]
    ]

    private static let russianShiftRows: [[String]] = [
        ["Й", "Ц", "У", "К", "Е", "Н", "Г", "Ш", "Щ", "З", "Х"],
        ["Ф", "Ы", "В", "А", "П", "Р", "О", "Л", "Д", "Ж", "Э"],
        ["\u{21E7}", "Я", "Ч", "С", "М", "И", "Т", "Ь", "Б", "Ю", "\u{232B}"],
        ["+=♥", "__GLOBE_A__", " ", ".", "\u{23CE}"]
    ]

    // ── Symbol layouts ──

    private static let symbolRows1: [[String]] = [
        ["$", "€", "£", "¥", "¢", "~", "…", "°", "※", "•"],
        ["-", "/", ":", ";", "(", ")", "₩", "&", "@", "\""],
        ["#+=", ".", ",", "?", "!", "'", "\u{232B}"],
        ["ABC", "__GLOBE_A__", " ", ".", "\u{23CE}"]
    ]

    private static let symbolRows2: [[String]] = [
        ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
        ["_", "\\", "|", "<", ">", "«", "»", "§", "©", "®"],
        ["123", ".", ",", "?", "!", "'", "\u{232B}"],
        ["ABC", "__GLOBE_A__", " ", ".", "\u{23CE}"]
    ]

    // ── Special keys set ──

    // Space " " and period "." are NOT special — they render WHITE like letter keys.
    private static let specialKeys: Set<String> = [
        "\u{21E7}", "\u{232B}", "\u{23CE}",
        "\u{D55C}", "EN",
        "123", "#+=", "ABC",
        "+=♥", "__GLOBE_A__"
    ]

    // MARK: - Container

    private let keyboardContainer: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private var allKeyButtons: [UIButton] = []
    private var isRebuilding = false

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupContainer()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupContainer() {
        // Enable multi-touch so rapid taps with alternating fingers are never dropped
        isMultipleTouchEnabled = true
        keyboardContainer.isUserInteractionEnabled = false  // touches pass through to self

        addSubview(keyboardContainer)
        NSLayoutConstraint.activate([
            keyboardContainer.topAnchor.constraint(equalTo: topAnchor),
            keyboardContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            keyboardContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            keyboardContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        buildKeyboard()
    }

    // MARK: - Current Layout

    private func currentRows() -> [[String]] {
        switch currentPage {
        case .letters:
            let letterRows: [[String]]
            switch currentLanguage {
            case .korean:
                letterRows = isShifted ? Self.koreanShiftRows : Self.koreanRows
            case .russian:
                letterRows = isShifted ? Self.russianShiftRows : Self.russianRows
            default:
                // English, Spanish, French, German, Italian all use QWERTY
                letterRows = isShifted ? Self.englishShiftRows : Self.englishRows
            }
            return showNumberRow ? [Self.numberRow] + letterRows : letterRows
        case .symbols1:
            return showNumberRow ? [Self.numberRow] + Self.symbolRows1 : Self.symbolRows1
        case .symbols2:
            return showNumberRow ? [Self.numberRow] + Self.symbolRows2 : Self.symbolRows2
        }
    }

    /// Number of keys in the first letter row — used as reference width for mixed row keys.
    /// English/Korean = 10, Russian = 11.
    private var referenceKeyCount: CGFloat {
        let rows = currentRows()
        let letterRowIndex = showNumberRow ? 1 : 0
        guard letterRowIndex < rows.count else { return 10 }
        return CGFloat(rows[letterRowIndex].count)
    }

    // MARK: - Build Keyboard

    private func scheduleBuildKeyboard(delay: TimeInterval = KeyboardLayoutView.buildDelayAfterFlash) {
        pendingBuildWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.buildKeyboard()
            self?.pendingBuildWork = nil
        }
        pendingBuildWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func buildKeyboard() {
        guard !isTrackpadMode else { return }  // 트랙패드 중 재빌드 방지

        // Rain 애니메이션 일시정지 — 뷰 계층 재구성 동안 draw() 방지
        let wasRainAnimating = matrixRainView?.isActive ?? false
        if wasRainAnimating {
            matrixRainView?.pauseAnimation()
        }
        let wasRippleAnimating = mercuryRippleView?.isActive ?? false
        if wasRippleAnimating {
            mercuryRippleView?.pauseAnimation()
        }
        let wasLensAnimating = isLensAnimationActive
        if wasLensAnimating { pauseLensAnimation() }
        let wasStardustAnimating = stardustView?.isActive ?? false
        if wasStardustAnimating { stardustView?.pauseAnimation() }
        let wasSnowfallAnimating = snowfallView?.isActive ?? false
        if wasSnowfallAnimating { snowfallView?.pauseAnimation() }
        let wasCherryBlossomAnimating = cherryBlossomView?.isActive ?? false
        if wasCherryBlossomAnimating { cherryBlossomView?.pauseAnimation() }

        // 예약된 build가 있으면 취소 (직접 호출 시 중복 방지)
        pendingBuildWork?.cancel()
        pendingBuildWork = nil
        isRebuilding = true

        // 웨이브 projection 캐시 즉시 정리 — 버튼 제거 전에 stale 참조 방지
        cachedKeyProjections.removeAll()
        cachedButtonCentersInRippleView.removeAll()

        keyboardContainer.subviews.forEach { $0.removeFromSuperview() }
        allKeyButtons.removeAll()

        let rows = currentRows()
        let totalRows = rows.count
        let isNumberRow = showNumberRow
        var previousRowView: UIView?

        for (rowIndex, rowKeys) in rows.enumerated() {
            let rowView = buildRow(keys: rowKeys, rowIndex: rowIndex, totalRows: totalRows)
            rowView.translatesAutoresizingMaskIntoConstraints = false
            keyboardContainer.addSubview(rowView)

            let topAnchorRef: NSLayoutYAxisAnchor
            let topConstant: CGFloat

            if let prev = previousRowView {
                topAnchorRef = prev.bottomAnchor
                // Smaller gap after number row
                topConstant = (rowIndex == 1 && isNumberRow) ? Layout.numberRowSpacingV : Layout.keySpacingV
            } else {
                topAnchorRef = keyboardContainer.topAnchor
                topConstant = Layout.topInset
            }

            // Number row (rowIndex 0 in letters page) uses shorter height
            let rowHeight: CGFloat = (rowIndex == 0 && isNumberRow) ? Layout.numberRowHeight : Layout.keyHeight

            NSLayoutConstraint.activate([
                rowView.topAnchor.constraint(equalTo: topAnchorRef, constant: topConstant),
                rowView.leadingAnchor.constraint(equalTo: keyboardContainer.leadingAnchor, constant: Layout.sideInset),
                rowView.trailingAnchor.constraint(equalTo: keyboardContainer.trailingAnchor, constant: -Layout.sideInset),
                rowView.heightAnchor.constraint(equalToConstant: rowHeight),
            ])

            previousRowView = rowView
        }

        if let lastRow = previousRowView {
            lastRow.bottomAnchor.constraint(equalTo: keyboardContainer.bottomAnchor, constant: -Layout.bottomInset).isActive = true
        }

        keyboardContainer.layoutIfNeeded()
        isRebuilding = false

        // Wave animation: 빌드 완료 후 웨이브 재시작/정지
        if let theme = customTheme, theme.needsWaveAnimation {
            restartWaveAnimationAfterBuild()
        } else if isWaveAnimationActive {
            stopWaveAnimation()
        }

        #if DEBUG
        NSLog("🔬 [BUILD-ANIM] rain: wasAnimating=\(wasRainAnimating), matrixRainView=\(matrixRainView != nil), isMemoryConstrained=\(isMemoryConstrained), needsRain=\(customTheme?.needsRainAnimation ?? false), isActive=\(matrixRainView?.isActive ?? false), lowPower=\(ProcessInfo.processInfo.isLowPowerModeEnabled)")
        NSLog("🔬 [BUILD-ANIM] snow: wasAnimating=\(wasSnowfallAnimating), snowfallView=\(snowfallView != nil), needsSnow=\(customTheme?.needsSnowfallAnimation ?? false), isActive=\(snowfallView?.isActive ?? false)")
        NSLog("🔬 [BUILD-ANIM] cherry: wasAnimating=\(wasCherryBlossomAnimating), cherryBlossomView=\(cherryBlossomView != nil), needsCherry=\(customTheme?.needsCherryBlossomAnimation ?? false), isActive=\(cherryBlossomView?.isActive ?? false)")
        #endif

        // Rain animation: 빌드 완료 후 레인 재개
        if wasRainAnimating {
            matrixRainView?.resumeAnimation()
        } else if let theme = customTheme, theme.needsRainAnimation,
                  !isMemoryConstrained,
                  let rv = matrixRainView, !rv.isActive,
                  !ProcessInfo.processInfo.isLowPowerModeEnabled {
            rv.startAnimation()
            #if DEBUG
            NSLog("🔬 [BUILD-ANIM] ✅ Rain startAnimation() CALLED")
            #endif
        }

        // Resume ripple animation
        if wasRippleAnimating {
            mercuryRippleView?.resumeAnimation()
        } else if let theme = customTheme, theme.needsRippleAnimation,
                  !isMemoryConstrained, let rv = mercuryRippleView, !rv.isActive,
                  !ProcessInfo.processInfo.isLowPowerModeEnabled {
            rv.startAnimation()
        }

        // Lens animation: 빌드 후 캐시 갱신/재개
        if wasLensAnimating {
            resumeLensAnimation()
        } else if let theme = customTheme, theme.needsRippleAnimation,
                  !isMemoryConstrained, !ProcessInfo.processInfo.isLowPowerModeEnabled {
            startLensAnimation()
        }

        // Edge Glow animation
        if let theme = customTheme, theme.needsEdgeGlowAnimation {
            restartEdgeGlowAfterBuild()
        } else if isEdgeGlowAnimationActive {
            stopEdgeGlowAnimation()
        }

        // Resume stardust animation
        if wasStardustAnimating {
            stardustView?.resumeAnimation()
        } else if let theme = customTheme, theme.needsStardustAnimation,
                  !isMemoryConstrained, let sv = stardustView, !sv.isActive,
                  !ProcessInfo.processInfo.isLowPowerModeEnabled {
            sv.startAnimation()
        }

        // Resume snowfall animation + keyFrames 업데이트
        if let sv = snowfallView {
            sv.keyFrames = allKeyButtons.map { btn in
                btn.superview?.convert(btn.frame, to: sv) ?? btn.frame
            }
        }
        if wasSnowfallAnimating {
            snowfallView?.resumeAnimation()
        } else if let theme = customTheme, theme.needsSnowfallAnimation,
                  !isMemoryConstrained, let sv = snowfallView, !sv.isActive,
                  !ProcessInfo.processInfo.isLowPowerModeEnabled {
            sv.startAnimation()
            #if DEBUG
            NSLog("🔬 [BUILD-ANIM] ✅ Snowfall startAnimation() CALLED")
            #endif
        }

        // Resume cherry blossom animation + keyFrames 업데이트
        if let cv = cherryBlossomView {
            cv.keyFrames = allKeyButtons.map { btn in
                btn.superview?.convert(btn.frame, to: cv) ?? btn.frame
            }
        }
        if wasCherryBlossomAnimating {
            cherryBlossomView?.resumeAnimation()
        } else if let theme = customTheme, theme.needsCherryBlossomAnimation,
                  !isMemoryConstrained, let cv = cherryBlossomView, !cv.isActive,
                  !ProcessInfo.processInfo.isLowPowerModeEnabled {
            cv.startAnimation()
            #if DEBUG
            NSLog("🔬 [BUILD-ANIM] ✅ Cherry startAnimation() CALLED")
            #endif
        }
    }

    private func buildRow(keys: [String], rowIndex: Int, totalRows: Int) -> UIView {
        let container = UIView()

        if rowIndex == totalRows - 1 {
            buildBottomRow(container: container, keys: keys, rowIndex: rowIndex)
        } else if rowIndex == totalRows - 2 {
            buildMixedRow(container: container, keys: keys, rowIndex: rowIndex)
        } else {
            buildEqualRow(container: container, keys: keys, rowIndex: rowIndex)
        }

        return container
    }

    // MARK: - Row 0 & 1: Equal width keys

    private func buildEqualRow(container: UIView, keys: [String], rowIndex: Int) {
        // In letters page: indent rows with fewer keys than the reference row (first letter row).
        // English/Korean: row 2 has 9 keys vs 10 → indent. Russian: rows 1,2 both 11 → no indent.
        let refCount = Int(referenceKeyCount)
        let needsIndent = (keys.count < refCount && currentPage == .letters && rowIndex > (showNumberRow ? 0 : -1))

        var previousButton: UIButton?
        let firstButton = createKeyButton(keys[0], rowIndex: rowIndex)

        for (i, key) in keys.enumerated() {
            let btn = (i == 0) ? firstButton : createKeyButton(key, rowIndex: rowIndex)
            container.addSubview(btn)

            btn.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                btn.topAnchor.constraint(equalTo: container.topAnchor),
                btn.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])

            if let prev = previousButton {
                btn.leadingAnchor.constraint(equalTo: prev.trailingAnchor, constant: Layout.keySpacingH).isActive = true
                btn.widthAnchor.constraint(equalTo: firstButton.widthAnchor).isActive = true
            } else {
                let indent: CGFloat = needsIndent ? 18 : 0
                btn.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: indent).isActive = true
            }

            previousButton = btn
        }

        if let last = previousButton {
            let indent: CGFloat = needsIndent ? 18 : 0
            last.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -indent).isActive = true
        }
    }

    // MARK: - Row 2: Mixed row (shift/mode + letters + backspace)

    private func buildMixedRow(container: UIView, keys: [String], rowIndex: Int) {
        let wideKeyWidth: CGFloat = 42  // Shift/backspace base width

        // Letters page: match letter key widths to 10-key row using multiplier
        if currentPage == .letters {
            var leftWideBtn: UIButton?
            var rightWideBtn: UIButton?
            var letterButtons: [UIButton] = []

            for key in keys {
                let btn = createKeyButton(key, rowIndex: rowIndex)
                btn.translatesAutoresizingMaskIntoConstraints = false
                container.addSubview(btn)

                NSLayoutConstraint.activate([
                    btn.topAnchor.constraint(equalTo: container.topAnchor),
                    btn.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                ])

                if key == Self.shiftKey || key == Self.moreSymKey || key == Self.symbolKey {
                    leftWideBtn = btn
                } else if key == Self.backKey {
                    rightWideBtn = btn
                } else {
                    letterButtons.append(btn)
                }
            }

            guard let shiftBtn = leftWideBtn, let backspaceBtn = rightWideBtn else { return }

            // Each letter key width matches keys in the reference row above
            let keySpacing = Layout.keySpacingH
            let n = referenceKeyCount
            for btn in letterButtons {
                btn.widthAnchor.constraint(
                    equalTo: container.widthAnchor,
                    multiplier: 1.0 / n,
                    constant: -(n - 1) * keySpacing / n
                ).isActive = true
            }

            // Invisible spacer views to distribute leftover space evenly
            let spacerLeft = UIView()
            spacerLeft.translatesAutoresizingMaskIntoConstraints = false
            spacerLeft.isUserInteractionEnabled = false
            container.addSubview(spacerLeft)

            let spacerRight = UIView()
            spacerRight.translatesAutoresizingMaskIntoConstraints = false
            spacerRight.isUserInteractionEnabled = false
            container.addSubview(spacerRight)

            // Spacers are zero-height, just used for width calculation
            NSLayoutConstraint.activate([
                spacerLeft.topAnchor.constraint(equalTo: container.topAnchor),
                spacerLeft.heightAnchor.constraint(equalToConstant: 0),
                spacerRight.topAnchor.constraint(equalTo: container.topAnchor),
                spacerRight.heightAnchor.constraint(equalToConstant: 0),
            ])

            // Layout: shift | spacerLeft | letterKeys | spacerRight | backspace
            shiftBtn.leadingAnchor.constraint(equalTo: container.leadingAnchor).isActive = true
            spacerLeft.leadingAnchor.constraint(equalTo: shiftBtn.trailingAnchor).isActive = true

            // First letter key after left spacer
            if let firstLetter = letterButtons.first {
                firstLetter.leadingAnchor.constraint(equalTo: spacerLeft.trailingAnchor, constant: Layout.keySpacingH).isActive = true
            }

            // Chain letter keys
            for i in 1..<letterButtons.count {
                letterButtons[i].leadingAnchor.constraint(equalTo: letterButtons[i-1].trailingAnchor, constant: Layout.keySpacingH).isActive = true
            }

            // Last letter key to right spacer
            if let lastLetter = letterButtons.last {
                spacerRight.leadingAnchor.constraint(equalTo: lastLetter.trailingAnchor, constant: Layout.keySpacingH).isActive = true
            }

            backspaceBtn.leadingAnchor.constraint(equalTo: spacerRight.trailingAnchor).isActive = true
            backspaceBtn.trailingAnchor.constraint(equalTo: container.trailingAnchor).isActive = true

            // shift.width = wideKeyWidth + spacerLeft.width, backspace.width = wideKeyWidth + spacerRight.width
            shiftBtn.widthAnchor.constraint(equalTo: spacerLeft.widthAnchor, constant: wideKeyWidth).isActive = true
            backspaceBtn.widthAnchor.constraint(equalTo: spacerRight.widthAnchor, constant: wideKeyWidth).isActive = true

            // Equal spacers → even distribution of leftover space
            spacerLeft.widthAnchor.constraint(equalTo: spacerRight.widthAnchor).isActive = true

            return
        }

        // Fallback: symbol pages — original fixed-width behavior
        var letterButtons: [UIButton] = []
        var firstLetter: UIButton?

        for key in keys {
            let btn = createKeyButton(key, rowIndex: rowIndex)
            btn.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(btn)

            NSLayoutConstraint.activate([
                btn.topAnchor.constraint(equalTo: container.topAnchor),
                btn.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])

            if key == Self.shiftKey || key == Self.moreSymKey || key == Self.symbolKey {
                btn.leadingAnchor.constraint(equalTo: container.leadingAnchor).isActive = true
                btn.widthAnchor.constraint(equalToConstant: wideKeyWidth).isActive = true
            } else if key == Self.backKey {
                btn.trailingAnchor.constraint(equalTo: container.trailingAnchor).isActive = true
                btn.widthAnchor.constraint(equalToConstant: wideKeyWidth).isActive = true
            } else {
                if let prev = letterButtons.last ?? container.subviews.first {
                    btn.leadingAnchor.constraint(equalTo: prev.trailingAnchor, constant: Layout.keySpacingH).isActive = true
                }
                if firstLetter == nil {
                    firstLetter = btn
                } else {
                    btn.widthAnchor.constraint(equalTo: firstLetter!.widthAnchor).isActive = true
                }
                letterButtons.append(btn)
            }
        }

        if let lastLetter = letterButtons.last {
            let backspaceBtn = container.subviews.last!
            lastLetter.trailingAnchor.constraint(equalTo: backspaceBtn.leadingAnchor, constant: -Layout.keySpacingH).isActive = true
        }
    }

    // MARK: - Bottom row (+=♥, 🌐A, space, period, return)

    private func buildBottomRow(container: UIView, keys: [String], rowIndex: Int) {
        // 5 keys: +=♥(50), 🌐A(50), space(flexible), .(50), return(74)
        let funcKeyWidth: CGFloat = 50    // +=♥, 🌐A
        let periodKeyWidth: CGFloat = 34  // "."
        let returnKeyWidth: CGFloat = 74  // return

        var previousView: UIButton?

        for key in keys {
            let btn = createKeyButton(key, rowIndex: rowIndex)
            btn.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(btn)

            NSLayoutConstraint.activate([
                btn.topAnchor.constraint(equalTo: container.topAnchor),
                btn.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])

            if key == " " {
                // Space bar: flexible width
                if let prev = previousView {
                    btn.leadingAnchor.constraint(equalTo: prev.trailingAnchor, constant: Layout.keySpacingH).isActive = true
                }
            } else if key == Self.returnKey {
                btn.widthAnchor.constraint(equalToConstant: returnKeyWidth).isActive = true
                btn.trailingAnchor.constraint(equalTo: container.trailingAnchor).isActive = true
                if let prev = previousView {
                    btn.leadingAnchor.constraint(equalTo: prev.trailingAnchor, constant: Layout.keySpacingH).isActive = true
                }
            } else if key == "." {
                btn.widthAnchor.constraint(equalToConstant: periodKeyWidth).isActive = true
                if let prev = previousView {
                    btn.leadingAnchor.constraint(equalTo: prev.trailingAnchor, constant: Layout.keySpacingH).isActive = true
                }
            } else if key == Self.symbolToggleKey || key == Self.globeLangKey || key == Self.abcKey {
                btn.widthAnchor.constraint(equalToConstant: funcKeyWidth).isActive = true
                if let prev = previousView {
                    btn.leadingAnchor.constraint(equalTo: prev.trailingAnchor, constant: Layout.keySpacingH).isActive = true
                } else {
                    btn.leadingAnchor.constraint(equalTo: container.leadingAnchor).isActive = true
                }
            } else {
                // Fallback for any other key
                btn.widthAnchor.constraint(equalToConstant: funcKeyWidth).isActive = true
                if let prev = previousView {
                    btn.leadingAnchor.constraint(equalTo: prev.trailingAnchor, constant: Layout.keySpacingH).isActive = true
                } else {
                    btn.leadingAnchor.constraint(equalTo: container.leadingAnchor).isActive = true
                }
            }

            previousView = btn
        }
    }

    // MARK: - Create Key Button

    private func createKeyButton(_ key: String, rowIndex: Int) -> UIButton {
        let button = UIButton(type: .custom)
        button.accessibilityLabel = key
        // ALL touch handling is done at the VIEW level via touchesBegan/Moved/Ended.
        // Buttons are purely visual — disabling their interaction prevents UIButton's
        // internal touch tracking from stealing/dropping rapid taps.
        button.isUserInteractionEnabled = false

        configureButtonAppearance(button, key: key)

        button.layer.cornerRadius = Layout.cornerRadius

        if let theme = customTheme, (theme.hasWoodTexture || theme.needsEdgeGlowAnimation) {
            button.clipsToBounds = false
            button.layer.masksToBounds = false
        } else {
            button.clipsToBounds = true
        }

        allKeyButtons.append(button)
        return button
    }

    private func configureButtonAppearance(_ button: UIButton, key: String) {
        let isSpecial = Self.specialKeys.contains(key)

        // Colors
        if let theme = customTheme {

            // ========================================
            // Return 키 처리
            // ========================================
            if key == Self.returnKey {
                if theme.hasWoodTexture {
                    if case .woodBlock(let borderColor, let shadowColor, let highlightAlpha) = theme.specialKeyVisualStyle {
                        button.backgroundColor = theme.specialKeyBackground
                        applyWoodTextureTile(to: button, theme: theme)
                        button.layer.borderWidth = 1
                        button.layer.borderColor = borderColor.cgColor
                        button.layer.shadowColor = shadowColor.cgColor
                        button.layer.shadowOffset = CGSize(width: 0, height: 3)
                        button.layer.shadowRadius = 1.5
                        button.layer.shadowOpacity = 1.0
                        // 기존 tag 9902 UIView 정리 (v1 마이그레이션 안전 처리)
                        if let oldHv = button.viewWithTag(9902) { oldHv.removeFromSuperview() }
                        applyWoodHighlightGradient(to: button, highlightAlpha: highlightAlpha)
                    }
                    button.setTitleColor(theme.keyTextColor, for: .normal)
                } else if case .edgeGlow(let borderColor, let glowColor) = theme.specialKeyVisualStyle {
                    button.backgroundColor = .clear
                    button.layer.borderWidth = 1.0
                    button.layer.borderColor = borderColor.withAlphaComponent(0.4).cgColor
                    button.layer.shadowColor = glowColor.cgColor
                    button.layer.shadowOffset = .zero
                    button.layer.shadowRadius = 3.0
                    button.layer.shadowOpacity = 0.2
                    button.layer.shadowPath = UIBezierPath(roundedRect: button.bounds, cornerRadius: button.layer.cornerRadius).cgPath
                    button.setTitleColor(theme.returnKeyAccentTextColor, for: .normal)
                } else if case .frostedGlass(_, let borderColor, _) = theme.specialKeyVisualStyle {
                    button.backgroundColor = theme.returnKeyAccentColor
                    button.layer.borderWidth = 1.0
                    button.layer.borderColor = borderColor.cgColor
                    button.layer.shadowColor = UIColor(red: 180/255, green: 200/255, blue: 240/255, alpha: 1).cgColor
                    button.layer.shadowOffset = .zero
                    button.layer.shadowRadius = 2.0
                    button.layer.shadowOpacity = 0.05
                    button.layer.shadowPath = UIBezierPath(roundedRect: button.bounds, cornerRadius: button.layer.cornerRadius).cgPath
                    button.setTitleColor(theme.returnKeyAccentTextColor, for: .normal)
                    addSnowCap(to: button)
                } else {
                    button.backgroundColor = returnKeyIsBlue ? theme.returnKeyAccentColor : theme.specialKeyBackground
                    button.setTitleColor(returnKeyIsBlue ? theme.returnKeyAccentTextColor : theme.keyTextColor, for: .normal)
                }

            // ========================================
            // 일반 키 처리
            // ========================================
            } else if !isSpecial {
                switch theme.keyVisualStyle {
                case .solid:
                    button.backgroundColor = theme.keyBackground
                case .translucent(let alpha, let tint):
                    button.backgroundColor = tint.withAlphaComponent(alpha)
                case .woodBlock(let borderColor, let shadowColor, let highlightAlpha):
                    button.backgroundColor = theme.keyBackground
                    applyWoodTextureTile(to: button, theme: theme)
                    button.layer.borderWidth = 1
                    button.layer.borderColor = borderColor.cgColor
                    button.layer.shadowColor = shadowColor.cgColor
                    button.layer.shadowOffset = CGSize(width: 0, height: 3)
                    button.layer.shadowRadius = 1.5
                    button.layer.shadowOpacity = 1.0
                    button.layer.shadowPath = UIBezierPath(roundedRect: button.bounds, cornerRadius: button.layer.cornerRadius).cgPath
                    // 기존 tag 9902 UIView 정리 (v1 마이그레이션 안전 처리)
                    if let oldHv = button.viewWithTag(9902) { oldHv.removeFromSuperview() }
                    applyWoodHighlightGradient(to: button, highlightAlpha: highlightAlpha)
                case .edgeGlow(let borderColor, let glowColor):
                    button.backgroundColor = .clear
                    button.layer.borderWidth = 1.0
                    button.layer.borderColor = borderColor.withAlphaComponent(0.4).cgColor
                    button.layer.shadowColor = glowColor.cgColor
                    button.layer.shadowOffset = .zero
                    button.layer.shadowRadius = 3.0
                    button.layer.shadowOpacity = 0.2
                    button.layer.shadowPath = UIBezierPath(roundedRect: button.bounds, cornerRadius: button.layer.cornerRadius).cgPath
                case .frostedGlass(let bgAlpha, let borderColor, _):
                    button.backgroundColor = UIColor(hex: "#192846").withAlphaComponent(bgAlpha)
                    button.layer.borderWidth = 1.0
                    button.layer.borderColor = borderColor.cgColor
                    button.layer.shadowColor = UIColor(red: 180/255, green: 200/255, blue: 240/255, alpha: 1).cgColor
                    button.layer.shadowOffset = .zero
                    button.layer.shadowRadius = 2.0
                    button.layer.shadowOpacity = 0.05
                    button.layer.shadowPath = UIBezierPath(roundedRect: button.bounds, cornerRadius: button.layer.cornerRadius).cgPath
                    addSnowCap(to: button)
                }
                button.setTitleColor(theme.keyTextColor, for: .normal)

            // ========================================
            // 특수 키 처리
            // ========================================
            } else {
                switch theme.specialKeyVisualStyle {
                case .solid:
                    button.backgroundColor = theme.specialKeyBackground
                case .translucent(let alpha, let tint):
                    button.backgroundColor = tint.withAlphaComponent(alpha)
                case .woodBlock(let borderColor, let shadowColor, let highlightAlpha):
                    button.backgroundColor = theme.specialKeyBackground
                    applyWoodTextureTile(to: button, theme: theme)
                    button.layer.borderWidth = 1
                    button.layer.borderColor = borderColor.cgColor
                    button.layer.shadowColor = shadowColor.cgColor
                    button.layer.shadowOffset = CGSize(width: 0, height: 3)
                    button.layer.shadowRadius = 1.5
                    button.layer.shadowOpacity = 1.0
                    button.layer.shadowPath = UIBezierPath(roundedRect: button.bounds, cornerRadius: button.layer.cornerRadius).cgPath
                    // 기존 tag 9902 UIView 정리 (v1 마이그레이션 안전 처리)
                    if let oldHv = button.viewWithTag(9902) { oldHv.removeFromSuperview() }
                    applyWoodHighlightGradient(to: button, highlightAlpha: highlightAlpha)
                case .edgeGlow(let borderColor, let glowColor):
                    button.backgroundColor = .clear
                    button.layer.borderWidth = 1.0
                    button.layer.borderColor = borderColor.withAlphaComponent(0.4).cgColor
                    button.layer.shadowColor = glowColor.cgColor
                    button.layer.shadowOffset = .zero
                    button.layer.shadowRadius = 3.0
                    button.layer.shadowOpacity = 0.2
                    button.layer.shadowPath = UIBezierPath(roundedRect: button.bounds, cornerRadius: button.layer.cornerRadius).cgPath
                case .frostedGlass(let bgAlpha, let borderColor, _):
                    button.backgroundColor = UIColor(hex: "#192846").withAlphaComponent(bgAlpha)
                    button.layer.borderWidth = 1.0
                    button.layer.borderColor = borderColor.cgColor
                    button.layer.shadowColor = UIColor(red: 180/255, green: 200/255, blue: 240/255, alpha: 1).cgColor
                    button.layer.shadowOffset = .zero
                    button.layer.shadowRadius = 2.0
                    button.layer.shadowOpacity = 0.05
                    button.layer.shadowPath = UIBezierPath(roundedRect: button.bounds, cornerRadius: button.layer.cornerRadius).cgPath
                    addSnowCap(to: button)
                }
                button.setTitleColor(theme.keyTextColor, for: .normal)
            }

            // === 음각(Intaglio) 텍스트 이펙트 ===
            if theme.textShadowColor != .clear {
                applyEngravedTextEffect(to: button, theme: theme, key: key)
            }
        } else if key == Self.returnKey {
            button.backgroundColor = returnKeyIsBlue ? UIColor.systemBlue : (isDark ? UIColor(white: 0.37, alpha: 1) : UIColor(red: 0.76, green: 0.78, blue: 0.81, alpha: 1))
            button.setTitleColor(returnKeyIsBlue ? .white : (isDark ? .white : .black), for: .normal)
        } else if isSpecial {
            button.backgroundColor = isDark ? UIColor(white: 0.37, alpha: 1) : UIColor(red: 0.76, green: 0.78, blue: 0.81, alpha: 1)
            button.setTitleColor(isDark ? .white : .black, for: .normal)
        } else {
            button.backgroundColor = isDark ? UIColor(white: 0.42, alpha: 1) : .white
            button.setTitleColor(isDark ? .white : .black, for: .normal)
        }

        // Title / Image
        switch key {
        case Self.shiftKey:
            let config = UIImage.SymbolConfiguration(pointSize: 16, weight: isShifted ? .bold : .regular)
            let imgName = isShifted ? "shift.fill" : "shift"
            button.setImage(UIImage(systemName: imgName, withConfiguration: config), for: .normal)
            button.tintColor = customTheme?.keyTextColor ?? (isDark ? .white : .black)
            if isShifted {
                if customTheme != nil {
                    button.backgroundColor = customTheme!.keyBackground
                } else {
                    button.backgroundColor = isDark ? UIColor(white: 0.55, alpha: 1) : UIColor(white: 0.95, alpha: 1)
                }
            }
            button.setTitle(nil, for: .normal)

        case Self.backKey:
            let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            button.setImage(UIImage(systemName: "delete.left", withConfiguration: config), for: .normal)
            button.tintColor = customTheme?.keyTextColor ?? (isDark ? .white : .black)
            button.setTitle(nil, for: .normal)

        case Self.returnKey:
            if returnKeyIsBlue {
                // Action modes (send, search, go, etc.): show text
                button.setTitle(returnKeyDisplayName, for: .normal)
                button.titleLabel?.font = .systemFont(ofSize: Layout.returnFontSize, weight: .medium)
                button.setImage(nil, for: .normal)
            } else {
                // Default/newline mode: show return arrow icon like stock keyboard
                let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
                button.setImage(UIImage(systemName: "return.left", withConfiguration: config), for: .normal)
                button.tintColor = customTheme?.keyTextColor ?? (isDark ? .white : .black)
                button.setTitle(nil, for: .normal)
            }

        case Self.symbolToggleKey:
            button.setTitle("+=♥", for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)

        case Self.globeLangKey:
            // Globe icon with language label overlay
            let globeConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            button.setImage(UIImage(systemName: "globe", withConfiguration: globeConfig), for: .normal)
            button.tintColor = customTheme?.keyTextColor ?? (isDark ? .white : .black)
            button.setTitle(nil, for: .normal)
            // Dynamic language label: show the "other" language's short label
            let langLabel = UILabel()
            langLabel.text = (currentLanguage == .english) ? pairedLanguage.shortLabel : "A"
            langLabel.font = .systemFont(ofSize: 9, weight: .bold)
            langLabel.textColor = customTheme?.keyTextColor ?? (isDark ? .white : .black)
            langLabel.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(langLabel)
            NSLayoutConstraint.activate([
                langLabel.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -4),
                langLabel.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -8),
            ])

        case Self.langKR, Self.langEN:
            button.setTitle(key == Self.langKR ? "한" : "EN", for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: Layout.specialFontSize, weight: .medium)

        case Self.symbolKey:
            button.setTitle("123", for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: Layout.specialFontSize, weight: .medium)

        case Self.moreSymKey:
            button.setTitle("#+=", for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: Layout.specialFontSize, weight: .medium)

        case Self.abcKey:
            button.setTitle("ABC", for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: Layout.specialFontSize, weight: .medium)

        case " ":
            let spaceTitle: String
            if currentPage == .letters {
                spaceTitle = currentLanguage.displayName
            } else {
                spaceTitle = ""
            }
            button.setTitle(spaceTitle, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: Layout.spaceFontSize)

        case ".":
            button.setTitle(".", for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 20, weight: .medium)

        default:
            button.setTitle(key, for: .normal)
            let fontSize: CGFloat = (currentPage == .letters) ? Layout.letterFontSize : Layout.symbolFontSize
            button.titleLabel?.font = .systemFont(ofSize: fontSize)
        }
    }

    // MARK: - View-Level Touch Handling
    //
    // ALL key input is detected here — NOT through UIButton control events.
    // This guarantees every single touch is captured regardless of how fast
    // the user taps, because UIButton's internal touch tracking (which drops
    // rapid sequential taps when isMultipleTouchEnabled=false) is bypassed.

    /// Tracking state for backspace long-press
    private var backspaceTrackingTouch: UITouch?

    /// Tracking state for space bar long-press trackpad
    private var spaceTrackingTouch: UITouch?
    private var spaceLongPressTimer: Timer?
    private var spaceDidEnterTrackpad = false

    /// Tracking state for accent long-press popup
    private var accentTrackingTouch: UITouch?
    private var accentLongPressTimer: Timer?
    private var accentPopupView: AccentPopupView?
    private var accentBaseKey: String?
    private var accentSourceButton: UIButton?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let loc = touch.location(in: self)
            guard let button = findButtonAt(loc) else { continue }
            guard let key = button.accessibilityLabel else { continue }
            triggerHaptic()

            // ── Space bar: track for potential trackpad mode ──
            if key == " " && !isTrackpadMode {
                spaceTrackingTouch = touch
                spaceDidEnterTrackpad = false
                trackpadLastX = loc.x
                trackpadLastY = loc.y
                trackpadAccumulator = 0
                trackpadAccumulatorY = 0

                spaceLongPressTimer?.invalidate()
                spaceLongPressTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
                    guard let self = self, self.spaceTrackingTouch != nil else { return }
                    self.spaceDidEnterTrackpad = true
                    self.trackpadStartX = self.trackpadLastX
                    self.trackpadStartY = self.trackpadLastY
                    self.lockedAxis = .none
                    self.enterTrackpadMode()
                }
                flashButton(button)
                if isEdgeGlowAnimationActive { edgeGlowKeyPressed(button) }
                if let rv = mercuryRippleView, rv.isActive {
                    let rippleLoc = button.superview?.convert(button.center, to: rv) ?? loc
                    rv.addRipple(at: rippleLoc, intensity: 1.0)
                }
                if let sv = stardustView, sv.isActive {
                    let burstLoc = button.superview?.convert(button.center, to: sv) ?? loc
                    sv.addBurst(at: burstLoc, isSupernova: true)
                }
                continue
            }

            // ── Backspace: fire once + start long-press repeat ──
            if key == Self.backKey {
                backspaceTrackingTouch = touch
                onKeyTap?(Self.backKey)
                flashButton(button)
                if isEdgeGlowAnimationActive { edgeGlowKeyPressed(button) }
                if let rv = mercuryRippleView, rv.isActive {
                    let rippleLoc = button.superview?.convert(button.center, to: rv) ?? loc
                    rv.addRipple(at: rippleLoc, intensity: 0.7)
                }
                if let sv = stardustView, sv.isActive {
                    let burstLoc = button.superview?.convert(button.center, to: sv) ?? loc
                    sv.addBurst(at: burstLoc, isSupernova: false)
                }

                backspaceTimer?.invalidate()
                backspaceRepeatTimer?.invalidate()
                backspaceTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
                    self?.backspaceRepeatTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
                        self?.onKeyTap?(Self.backKey)
                    }
                }
                continue
            }

            // ── Accent-capable keys: track for potential long-press ──
            let accentAlternatives = AccentMap.accents(for: currentLanguage)[key] ?? []
            if !accentAlternatives.isEmpty {
                accentTrackingTouch = touch
                accentBaseKey = key
                accentSourceButton = button
                flashButton(button)
                if isEdgeGlowAnimationActive { edgeGlowKeyPressed(button) }
                if let rv = mercuryRippleView, rv.isActive {
                    let rippleLoc = button.superview?.convert(button.center, to: rv) ?? loc
                    rv.addRipple(at: rippleLoc, intensity: 0.7)
                }
                if let sv = stardustView, sv.isActive {
                    let burstLoc = button.superview?.convert(button.center, to: sv) ?? loc
                    sv.addBurst(at: burstLoc, isSupernova: false)
                }
                handleKeyAction(key)  // Immediately type the base character

                accentLongPressTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
                    self?.showAccentPopup(accents: accentAlternatives, sourceButton: button)
                }
                continue
            }

            // ── All other keys: handle immediately ──
            flashButton(button)
            if isEdgeGlowAnimationActive { edgeGlowKeyPressed(button) }
            if let rv = mercuryRippleView, rv.isActive {
                let rippleLoc = button.superview?.convert(button.center, to: rv) ?? loc
                rv.addRipple(at: rippleLoc, intensity: 0.7)
            }
            if let sv = stardustView, sv.isActive {
                let burstLoc = button.superview?.convert(button.center, to: sv) ?? loc
                sv.addBurst(at: burstLoc, isSupernova: false)
            }
            handleKeyAction(key)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Accent popup selection tracking
        if let tracked = accentTrackingTouch, touches.contains(tracked), accentPopupView != nil {
            let loc = tracked.location(in: self)
            accentPopupView?.updateSelection(at: loc)
        }

        // Space bar trackpad cursor movement — accumulate only; CADisplayLink fires moves
        if let tracked = spaceTrackingTouch, touches.contains(tracked) {
            if isTrackpadMode {
                let loc = tracked.location(in: self)

                // Axis locking: determine dominant axis after threshold distance
                if lockedAxis == .none {
                    let dx = abs(loc.x - trackpadStartX)
                    let dy = abs(loc.y - trackpadStartY)
                    if dx >= axisLockThreshold || dy >= axisLockThreshold {
                        lockedAxis = (dx >= dy) ? .horizontal : .vertical
                    }
                } else {
                    // Allow axis switch if cross-axis movement exceeds unlock threshold
                    let crossAxisDelta: CGFloat
                    switch lockedAxis {
                    case .horizontal:
                        crossAxisDelta = abs(loc.y - trackpadStartY)
                    case .vertical:
                        crossAxisDelta = abs(loc.x - trackpadStartX)
                    case .none:
                        crossAxisDelta = 0
                    }
                    if crossAxisDelta >= axisUnlockThreshold {
                        trackpadStartX = loc.x
                        trackpadStartY = loc.y
                        trackpadAccumulator = 0
                        trackpadAccumulatorY = 0
                        lockedAxis = .none
                    }
                }

                // Accumulate deltas based on locked axis
                let deltaX = loc.x - trackpadLastX
                let deltaY = loc.y - trackpadLastY
                trackpadLastX = loc.x
                trackpadLastY = loc.y

                if lockedAxis != .vertical {
                    trackpadAccumulator += deltaX
                }
                if lockedAxis != .horizontal {
                    trackpadAccumulatorY += deltaY
                }
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            // Accent popup
            if touch === accentTrackingTouch {
                accentLongPressTimer?.invalidate()
                accentLongPressTimer = nil
                if let popup = accentPopupView, let selected = popup.selectedCharacter {
                    onKeyTap?(Self.backKey)
                    onKeyTap?(selected)
                }
                hideAccentPopup()
                accentTrackingTouch = nil
                accentBaseKey = nil
                accentSourceButton = nil
            }
            // Space bar
            if touch === spaceTrackingTouch {
                spaceLongPressTimer?.invalidate()
                spaceLongPressTimer = nil
                if isTrackpadMode {
                    exitTrackpadMode()
                } else if !spaceDidEnterTrackpad {
                    onKeyTap?(" ")
                }
                spaceTrackingTouch = nil
                spaceDidEnterTrackpad = false
            }
            // Backspace
            if touch === backspaceTrackingTouch {
                backspaceTimer?.invalidate()
                backspaceTimer = nil
                backspaceRepeatTimer?.invalidate()
                backspaceRepeatTimer = nil
                backspaceTrackingTouch = nil
            }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if touch === accentTrackingTouch {
                accentLongPressTimer?.invalidate()
                accentLongPressTimer = nil
                hideAccentPopup()
                accentTrackingTouch = nil
                accentBaseKey = nil
                accentSourceButton = nil
            }
            if touch === spaceTrackingTouch {
                spaceLongPressTimer?.invalidate()
                spaceLongPressTimer = nil
                if isTrackpadMode { exitTrackpadMode() }
                spaceTrackingTouch = nil
                spaceDidEnterTrackpad = false
            }
            if touch === backspaceTrackingTouch {
                backspaceTimer?.invalidate()
                backspaceTimer = nil
                backspaceRepeatTimer?.invalidate()
                backspaceRepeatTimer = nil
                backspaceTrackingTouch = nil
            }
        }
    }

    // MARK: - Key Action Dispatch

    private func handleKeyAction(_ key: String) {
        switch key {
        case Self.shiftKey:
            isShifted.toggle()
            updateKeyLabelsForShift()

        case Self.langKR:
            let oldLang = currentLanguage
            let oldPage = currentPage
            let wasShifted = isShifted
            currentLanguage = .korean
            isShifted = false
            currentPage = .letters
            if oldPage != .letters {
                buildKeyboard()
            } else {
                updateKeyLabelsForLanguage(from: oldLang, to: .korean, wasShifted: wasShifted)
            }
            onLanguageChanged?(.korean)

        case Self.langEN:
            let oldLang = currentLanguage
            let oldPage = currentPage
            let wasShifted = isShifted
            currentLanguage = .english
            isShifted = false
            currentPage = .letters
            if oldPage != .letters {
                buildKeyboard()
            } else {
                updateKeyLabelsForLanguage(from: oldLang, to: .english, wasShifted: wasShifted)
            }
            onLanguageChanged?(.english)

        case Self.globeLangKey:
            // Toggle between paired language and English
            let oldLang = currentLanguage
            let oldPage = currentPage
            if currentLanguage == .english {
                currentLanguage = pairedLanguage
                onLanguageChanged?(pairedLanguage)
            } else {
                currentLanguage = .english
                onLanguageChanged?(.english)
            }
            let wasShifted = isShifted
            isShifted = false
            currentPage = .letters
            // 심볼 페이지에서 전환했으면 버튼이 심볼 레이아웃 → 풀 rebuild 필수
            if oldPage != .letters {
                buildKeyboard()
            } else {
                updateKeyLabelsForLanguage(from: oldLang, to: currentLanguage, wasShifted: wasShifted)
            }

        case Self.symbolToggleKey:
            currentPage = .symbols1
            buildKeyboard()  // letters → symbols1: 행 구조 다름 → 풀 rebuild (0.18s 딜레이 제거)

        case Self.symbolKey:
            let oldPage = currentPage
            currentPage = .symbols1
            updateKeyLabelsForSymbolPage(from: oldPage, to: .symbols1)

        case Self.moreSymKey:
            let oldPage = currentPage
            currentPage = .symbols2
            updateKeyLabelsForSymbolPage(from: oldPage, to: .symbols2)

        case Self.abcKey:
            currentPage = .letters
            isShifted = false
            buildKeyboard()  // symbols → letters: 행 구조 다름 → 풀 rebuild (0.18s 딜레이 제거)

        default:
            onKeyTap?(key)
            if isShifted && !Self.specialKeys.contains(key) && currentPage == .letters {
                isShifted = false
                updateKeyLabelsForShift()
            }
            // ' 키 입력 후 자동으로 문자 키보드로 복귀
            if key == "'" && (currentPage == .symbols1 || currentPage == .symbols2) {
                currentPage = .letters
                scheduleBuildKeyboard()
            }
        }
    }

    // MARK: - Button Lookup

    /// Find the button at a given point (or nearest button for gap touches)
    private func findButtonAt(_ point: CGPoint) -> UIButton? {
        guard !isRebuilding else { return nil }

        // Direct hit — check each button's frame
        for button in allKeyButtons {
            guard let sv = button.superview else { continue }
            let frame = sv.convert(button.frame, to: self)
            guard frame.width > 0 && frame.height > 0 else { continue }
            if frame.contains(point) {
                return button
            }
        }
        // Gap hit — find nearest button
        guard bounds.contains(point), !allKeyButtons.isEmpty else { return nil }
        var closestButton: UIButton?
        var minDistSq: CGFloat = .greatestFiniteMagnitude
        for button in allKeyButtons {
            guard let sv = button.superview else { continue }
            let frame = sv.convert(button.frame, to: self)
            guard frame.width > 0 && frame.height > 0 else { continue }
            let center = CGPoint(x: frame.midX, y: frame.midY)
            let dx = point.x - center.x
            let dy = point.y - center.y
            let distSq = dx * dx + dy * dy
            if distSq < minDistSq {
                minDistSq = distSq
                closestButton = button
            }
        }
        return closestButton
    }

    // MARK: - Visual Feedback

    /// Haptic 설정 캐시 — 외부에서 주입 (KeyboardViewController가 관리)
    var cachedHapticEnabled: Bool = true

    private func triggerHaptic() {
        guard cachedHapticEnabled else { return }
        hapticGenerator.impactOccurred()
    }

    /// Brief background color flash — no transform, no animation delay, no coordinate disruption
    private func flashButton(_ button: UIButton) {
        let flashColor: UIColor

        if let theme = customTheme {
            if theme.hasWoodTexture {
                flashColor = UIColor(white: 1.0, alpha: 0.15)
            } else if theme.needsWaveAnimation {
                flashColor = UIColor(hex: "#00FF41").withAlphaComponent(0.35)
            } else if theme.needsRippleAnimation {
                flashColor = UIColor(hex: "#6090C0").withAlphaComponent(0.25)
            } else if theme.needsStardustAnimation {
                flashColor = UIColor(hex: "#8060D0").withAlphaComponent(0.30)
            } else {
                // 키 배경 밝기 기준으로 자동 판단
                var brightness: CGFloat = 0
                theme.keyBackground.getHue(nil, saturation: nil, brightness: &brightness, alpha: nil)
                if brightness > 0.5 {
                    flashColor = UIColor(white: 0.0, alpha: 0.12)  // 밝은 키 → 어두운 플래시
                } else {
                    flashColor = UIColor(white: 1.0, alpha: 0.25)  // 어두운 키 → 밝은 플래시
                }
            }
        } else {
            flashColor = isDark ? UIColor(white: 0.5, alpha: 1) : UIColor(white: 0.65, alpha: 1)
        }

        if customTheme != nil {
            // 프리미엄/나무 테마: 오버레이 UIView 방식 통일
            let flashView = UIView(frame: button.bounds)
            flashView.backgroundColor = flashColor
            flashView.layer.cornerRadius = Layout.cornerRadius
            flashView.clipsToBounds = true
            flashView.isUserInteractionEnabled = false
            flashView.tag = 9999
            flashView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            button.addSubview(flashView)

            DispatchQueue.main.asyncAfter(deadline: .now() + Self.keyFlashDuration) {
                flashView.removeFromSuperview()
            }
        } else {
            // 기본 테마 (customTheme == nil)
            let original = button.backgroundColor ?? .clear
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            button.backgroundColor = flashColor
            CATransaction.commit()

            DispatchQueue.main.asyncAfter(deadline: .now() + Self.keyFlashDuration) {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                button.backgroundColor = original
                CATransaction.commit()
            }
        }
    }

    // MARK: - Wood Block Helpers

    /// 키 버튼에 나무 텍스처 타일 패턴 적용
    private func applyWoodTextureTile(to button: UIButton, theme: KeyboardTheme) {
        guard let tileName = theme.woodTileImageName,
              let tileImg = UIImage(named: tileName) else { return }

        let tag = 9901
        if button.viewWithTag(tag) != nil { return }  // 이미 있으면 스킵

        let tv = UIView()
        tv.tag = tag
        tv.isUserInteractionEnabled = false
        tv.backgroundColor = UIColor(patternImage: tileImg)
        tv.alpha = 0.5
        tv.layer.cornerRadius = Layout.cornerRadius
        tv.clipsToBounds = true
        // translatesAutoresizingMaskIntoConstraints = true (기본값 유지)
        tv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tv.frame = button.bounds  // 초기 frame 설정
        button.insertSubview(tv, at: 0)
    }

    /// 키 상단 하이라이트 그라디언트 (CAGradientLayer)
    private func applyWoodHighlightGradient(to button: UIButton, highlightAlpha: CGFloat) {
        guard highlightAlpha > 0 else { return }

        let layerName = "woodHighlightGradient"
        if button.layer.sublayers?.contains(where: { $0.name == layerName }) == true { return }

        let gl = CAGradientLayer()
        gl.name = layerName
        gl.colors = [
            UIColor(white: 1, alpha: highlightAlpha).cgColor,
            UIColor.clear.cgColor,
            UIColor(white: 0, alpha: highlightAlpha * 1.5).cgColor,
        ]
        gl.locations = [0, 0.4, 1.0]
        gl.cornerRadius = Layout.cornerRadius
        gl.masksToBounds = true
        gl.frame = button.bounds  // 초기 frame 설정

        // UIView 래퍼 없이 CAGradientLayer를 직접 추가
        // insertSublayer(at: 0)으로 최하위에 배치하여 텍스트 뒤에 렌더링
        button.layer.insertSublayer(gl, at: 0)
    }

    /// 키 상단 눈 쌓임 효과 (frostedGlass 테마 전용)
    private func addSnowCap(to button: UIButton) {
        let layerName = "snowCapGradient"
        if button.layer.sublayers?.contains(where: { $0.name == layerName }) == true { return }

        let snowCap = CAGradientLayer()
        snowCap.name = layerName
        snowCap.frame = CGRect(x: button.bounds.width * 0.12, y: 0,
                                width: button.bounds.width * 0.76, height: 2)
        snowCap.colors = [
            UIColor.clear.cgColor,
            UIColor(white: 1.0, alpha: 0.15).cgColor,
            UIColor(white: 1.0, alpha: 0.28).cgColor,
            UIColor(white: 1.0, alpha: 0.15).cgColor,
            UIColor.clear.cgColor
        ]
        snowCap.locations = [0, 0.2, 0.5, 0.8, 1.0]
        snowCap.startPoint = CGPoint(x: 0, y: 0.5)
        snowCap.endPoint = CGPoint(x: 1, y: 0.5)
        snowCap.cornerRadius = 1
        button.layer.addSublayer(snowCap)
    }

    /// 음각(Intaglio) 텍스트 이펙트 — 나무에 파낸 듯한 글자
    private func applyEngravedTextEffect(to button: UIButton, theme: KeyboardTheme, key: String) {
        guard !Self.specialKeys.contains(key) || key == Self.returnKey else {
            button.tintColor = theme.keyTextColor
            return
        }

        if let title = button.title(for: .normal), !title.isEmpty {
            let fontSize: CGFloat
            switch key {
            case Self.returnKey: fontSize = Layout.returnFontSize
            case " ": fontSize = Layout.spaceFontSize
            default: fontSize = Layout.letterFontSize
            }

            // === 음각 효과: 3레이어 구조 ===
            // Layer 1 (최하단): 밝은 하이라이트 (파인 바닥의 빛 반사)
            // Layer 2 (중간): 어두운 그림자 (파인 위쪽 엣지)
            // Layer 3 (최상단): 실제 텍스트

            // 기존 하이라이트 라벨 제거 (재적용 방지)
            button.viewWithTag(9903)?.removeFromSuperview()

            // --- Layer 1: 하이라이트 라벨 (UILabel로 직접 추가) ---
            if theme.textHighlightColor != .clear {
                let highlightLabel = UILabel()
                highlightLabel.tag = 9903
                highlightLabel.text = title
                highlightLabel.font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
                highlightLabel.textColor = theme.textHighlightColor
                highlightLabel.textAlignment = .center
                highlightLabel.isUserInteractionEnabled = false
                highlightLabel.translatesAutoresizingMaskIntoConstraints = false

                button.addSubview(highlightLabel)
                NSLayoutConstraint.activate([
                    highlightLabel.centerXAnchor.constraint(equalTo: button.centerXAnchor,
                        constant: theme.textHighlightOffset.width),
                    highlightLabel.centerYAnchor.constraint(equalTo: button.centerYAnchor,
                        constant: theme.textHighlightOffset.height),
                ])

                // titleLabel 아래에 배치
                if let titleLabel = button.titleLabel {
                    button.bringSubviewToFront(titleLabel)
                }
            }

            // --- Layer 2+3: 그림자 + 텍스트 (NSAttributedString) ---
            let shadow = NSShadow()
            shadow.shadowColor = theme.textShadowColor
            shadow.shadowOffset = theme.textShadowOffset
            shadow.shadowBlurRadius = 1.5

            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
                .foregroundColor: theme.keyTextColor,
                .shadow: shadow,
            ]

            button.setAttributedTitle(NSAttributedString(string: title, attributes: attrs), for: .normal)
        }

        // 아이콘(이미지)에도 음각 효과 강화
        if button.image(for: .normal) != nil {
            button.tintColor = theme.keyTextColor
            button.imageView?.layer.shadowColor = theme.textShadowColor.cgColor
            button.imageView?.layer.shadowOffset = theme.textShadowOffset
            button.imageView?.layer.shadowRadius = 1.5
            button.imageView?.layer.shadowOpacity = 1.0
        }
    }

    // MARK: - Accent Popup

    private func showAccentPopup(accents: [String], sourceButton: UIButton) {
        hideAccentPopup()
        guard let sv = sourceButton.superview else { return }
        let sourceFrame = sv.convert(sourceButton.frame, to: self)
        let popup = AccentPopupView()
        popup.configure(accents: accents, sourceFrame: sourceFrame, in: self)
        addSubview(popup)
        accentPopupView = popup
    }

    private func hideAccentPopup() {
        accentPopupView?.removeFromSuperview()
        accentPopupView = nil
    }

    private func enterTrackpadMode() {
        guard !isTrackpadMode else { return }
        // 트랙패드 중에는 웨이브 애니메이션 불필요 — CPU 절약
        if isWaveAnimationActive {
            stopWaveAnimation()
        }
        matrixRainView?.stopAnimation()
        mercuryRippleView?.stopAnimation()
        stopLensAnimation()
        stardustView?.stopAnimation()
        snowfallView?.stopAnimation()
        cherryBlossomView?.stopAnimation()
        stopEdgeGlowAnimation()
        isTrackpadMode = true
        selectionHaptic.prepare()

        // Start CADisplayLink for smooth cursor movement
        displayLink = CADisplayLink(target: self, selector: #selector(trackpadDisplayLinkFired))
        displayLink?.add(to: .main, forMode: .common)

        // Hide all key labels/icons — keep blank key shapes only
        for button in allKeyButtons {
            button.setTitle(nil, for: .normal)
            button.setImage(nil, for: .normal)
            // Hide globe key's langLabel subview
            for sub in button.subviews where sub is UILabel {
                sub.isHidden = true
            }
            // Uniform blank key color
            if let theme = customTheme {
                button.backgroundColor = theme.specialKeyBackground
            } else {
                button.backgroundColor = isDark ? UIColor(white: 0.30, alpha: 1) : UIColor(white: 0.88, alpha: 1)
            }
        }

        onTrackpadModeChanged?(true)
    }

    private func exitTrackpadMode() {
        guard isTrackpadMode else { return }
        isTrackpadMode = false
        lockedAxis = .none

        // Stop CADisplayLink
        displayLink?.invalidate()
        displayLink = nil

        buildKeyboard()  // Full rebuild to restore all key appearances
        // Rain 재시작은 buildKeyboard() 내부 훅에서 자동 처리됨

        onTrackpadModeChanged?(false)
    }

    @objc private func trackpadDisplayLinkFired() {
        var moved = false

        // X-axis
        while trackpadAccumulator > trackpadSensitivity {
            trackpadAccumulator -= trackpadSensitivity
            onCursorMove?(1, 0)
            moved = true
        }
        while trackpadAccumulator < -trackpadSensitivity {
            trackpadAccumulator += trackpadSensitivity
            onCursorMove?(-1, 0)
            moved = true
        }

        // Y-axis — max 1 line per threshold crossing, reset accumulator to prevent multi-line jumps
        if trackpadAccumulatorY > trackpadSensitivityY {
            trackpadAccumulatorY = 0
            onCursorMove?(0, 1)
            moved = true
        } else if trackpadAccumulatorY < -trackpadSensitivityY {
            trackpadAccumulatorY = 0
            onCursorMove?(0, -1)
            moved = true
        }

        if moved {
            triggerTrackpadHaptic()
        }
    }

    private func triggerTrackpadHaptic() {
        guard cachedHapticEnabled else { return }
        selectionHaptic.selectionChanged()
    }

    // MARK: - Hit Test
    // Return self for ALL touches within bounds so that touchesBegan always fires.
    // Button lookup is done in touchesBegan via findButtonAt().
    // This also enables seamless touch (no dead zones) and trackpad mode.

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard bounds.contains(point) else { return nil }
        return self
    }

    // MARK: - Public Methods

    func applyTheme(_ theme: KeyboardTheme?) {
        customTheme = theme
    }

    func updateAppearance(isDark: Bool) {
        self.isDark = isDark

        // Phase 7: 메모리 경고 후 영구 차단 방지
        // handleMemoryWarning()의 asyncAfter 복구가 키보드 확장에서 실행되지 않으므로
        // updateAppearance 진입 시 강제 리셋하여 애니메이션 재생성을 보장한다.
        // 진짜 메모리 위기 시에는 SafetyNet(22MB soft cleanup) / Graceful Restart(40MB exit(0))가 처리.
        isMemoryConstrained = false

        if let theme = customTheme {
            // 그라데이션 배경 처리
            if theme.hasGradient, let colors = theme.gradientColors {
                backgroundColor = .clear

                if gradientLayer == nil {
                    let gl = CAGradientLayer()
                    layer.insertSublayer(gl, at: 0)
                    gradientLayer = gl
                }
                gradientLayer?.colors = colors.map { $0.cgColor }
                gradientLayer?.locations = theme.gradientLocations
                gradientLayer?.startPoint = theme.gradientDirection.startPoint
                gradientLayer?.endPoint = theme.gradientDirection.endPoint
                gradientLayer?.frame = bounds
            } else {
                gradientLayer?.removeFromSuperlayer()
                gradientLayer = nil
                backgroundColor = theme.keyboardBackground
            }

            // 패턴 오버레이 처리
            if theme.hasPattern {
                if patternImageView == nil {
                    let iv = UIImageView()
                    iv.contentMode = .scaleToFill
                    iv.isUserInteractionEnabled = false
                    iv.translatesAutoresizingMaskIntoConstraints = false
                    insertSubview(iv, belowSubview: keyboardContainer)
                    NSLayoutConstraint.activate([
                        iv.topAnchor.constraint(equalTo: topAnchor),
                        iv.leadingAnchor.constraint(equalTo: leadingAnchor),
                        iv.trailingAnchor.constraint(equalTo: trailingAnchor),
                        iv.bottomAnchor.constraint(equalTo: bottomAnchor),
                    ])
                    patternImageView = iv
                }
                if let patternImg = ThemePatternRenderer.patternImage(
                    style: theme.patternStyle,
                    tint: theme.patternTint,
                    opacity: theme.patternOpacity,
                    size: CGSize(width: 128, height: 128)
                ) {
                    patternImageView?.backgroundColor = UIColor(patternImage: patternImg)
                    patternImageView?.isHidden = false
                }
            } else {
                patternImageView?.isHidden = true
            }
        } else {
            gradientLayer?.removeFromSuperlayer()
            gradientLayer = nil
            patternImageView?.isHidden = true
            backgroundColor = isDark ? UIColor(white: 0.08, alpha: 1) : UIColor(red: 0.82, green: 0.84, blue: 0.86, alpha: 1)
        }

        // Wood texture tile rendering
        if let theme = customTheme, theme.hasWoodTexture,
           let tileName = theme.woodTileImageName,
           let tileImg = UIImage(named: tileName) {

            if woodTileImageView == nil {
                let iv = UIImageView()
                iv.contentMode = .scaleToFill
                iv.isUserInteractionEnabled = false
                iv.translatesAutoresizingMaskIntoConstraints = false
                insertSubview(iv, belowSubview: keyboardContainer)
                NSLayoutConstraint.activate([
                    iv.topAnchor.constraint(equalTo: topAnchor),
                    iv.bottomAnchor.constraint(equalTo: bottomAnchor),
                    iv.leadingAnchor.constraint(equalTo: leadingAnchor),
                    iv.trailingAnchor.constraint(equalTo: trailingAnchor),
                ])
                woodTileImageView = iv
            }
            woodTileImageView?.backgroundColor = UIColor(patternImage: tileImg)
            woodTileImageView?.alpha = 0.6
            woodTileImageView?.isHidden = false
        } else {
            woodTileImageView?.isHidden = true
        }

        // Digital Rain 애니메이션 배경
        if let theme = customTheme, theme.needsRainAnimation {
            if !isMemoryConstrained {
                if matrixRainView == nil {
                    let rv = MatrixRainView()
                    rv.translatesAutoresizingMaskIntoConstraints = false
                    rv.isUserInteractionEnabled = false
                    insertSubview(rv, belowSubview: keyboardContainer)
                    NSLayoutConstraint.activate([
                        rv.topAnchor.constraint(equalTo: topAnchor),
                        rv.bottomAnchor.constraint(equalTo: bottomAnchor),
                        rv.leadingAnchor.constraint(equalTo: leadingAnchor),
                        rv.trailingAnchor.constraint(equalTo: trailingAnchor),
                    ])
                    matrixRainView = rv
                }
                matrixRainView?.isHidden = false
                // startAnimation() 여기서 호출하지 않음
                // → buildKeyboard() 내부의 pause/resume 또는 시작 훅에서 처리
            }
        } else {
            if let rv = matrixRainView {
                rv.stopAnimation()
                rv.removeFromSuperview()
                matrixRainView = nil
            }
        }

        // ── Mercury Ripple ──
        if let theme = customTheme, theme.needsRippleAnimation {
            if !isMemoryConstrained {
                if mercuryRippleView == nil {
                    let rv = MercuryRippleView()
                    rv.translatesAutoresizingMaskIntoConstraints = false
                    rv.isUserInteractionEnabled = false
                    insertSubview(rv, belowSubview: keyboardContainer)
                    NSLayoutConstraint.activate([
                        rv.topAnchor.constraint(equalTo: topAnchor),
                        rv.bottomAnchor.constraint(equalTo: bottomAnchor),
                        rv.leadingAnchor.constraint(equalTo: leadingAnchor),
                        rv.trailingAnchor.constraint(equalTo: trailingAnchor),
                    ])
                    mercuryRippleView = rv
                }
                mercuryRippleView?.isHidden = false
            }
        } else {
            mercuryRippleView?.stopAnimation()
            stopLensAnimation()
            mercuryRippleView?.isHidden = true
        }

        // ── Stardust Drift ──
        if let theme = customTheme, theme.needsStardustAnimation {
            if !isMemoryConstrained {
                if stardustView == nil {
                    let sv = StardustView()
                    sv.translatesAutoresizingMaskIntoConstraints = false
                    sv.isUserInteractionEnabled = false
                    insertSubview(sv, belowSubview: keyboardContainer)
                    NSLayoutConstraint.activate([
                        sv.topAnchor.constraint(equalTo: topAnchor),
                        sv.bottomAnchor.constraint(equalTo: bottomAnchor),
                        sv.leadingAnchor.constraint(equalTo: leadingAnchor),
                        sv.trailingAnchor.constraint(equalTo: trailingAnchor),
                    ])
                    stardustView = sv
                }
                stardustView?.isHidden = false
            }
        } else {
            stardustView?.stopAnimation()
            stardustView?.isHidden = true
        }

        // ── Midnight Snowfall ──
        if let theme = customTheme, theme.needsSnowfallAnimation {
            if !isMemoryConstrained {
                if snowfallView == nil {
                    let sv = SnowfallView()
                    sv.translatesAutoresizingMaskIntoConstraints = false
                    sv.isUserInteractionEnabled = false
                    insertSubview(sv, belowSubview: keyboardContainer)
                    NSLayoutConstraint.activate([
                        sv.topAnchor.constraint(equalTo: topAnchor),
                        sv.bottomAnchor.constraint(equalTo: bottomAnchor),
                        sv.leadingAnchor.constraint(equalTo: leadingAnchor),
                        sv.trailingAnchor.constraint(equalTo: trailingAnchor),
                    ])
                    snowfallView = sv
                }
                snowfallView?.isHidden = false
            }
        } else {
            snowfallView?.stopAnimation()
            snowfallView?.isHidden = true
        }

        // ── Cherry Blossom ──
        if let theme = customTheme, theme.needsCherryBlossomAnimation {
            if !isMemoryConstrained {
                if cherryBlossomView == nil {
                    let cv = CherryBlossomView()
                    cv.translatesAutoresizingMaskIntoConstraints = false
                    cv.isUserInteractionEnabled = false
                    insertSubview(cv, belowSubview: keyboardContainer)
                    NSLayoutConstraint.activate([
                        cv.topAnchor.constraint(equalTo: topAnchor),
                        cv.bottomAnchor.constraint(equalTo: bottomAnchor),
                        cv.leadingAnchor.constraint(equalTo: leadingAnchor),
                        cv.trailingAnchor.constraint(equalTo: trailingAnchor),
                    ])
                    cherryBlossomView = cv
                }
                cherryBlossomView?.isHidden = false
            }
        } else {
            cherryBlossomView?.stopAnimation()
            cherryBlossomView?.isHidden = true
        }

        buildKeyboard()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer?.frame = bounds

        // Wood block key texture + gradient frame update
        for button in allKeyButtons {
            let bounds = button.bounds

            // 텍스처 타일 UIView frame 업데이트 (tag 9901)
            if let tv = button.viewWithTag(9901) {
                tv.frame = bounds
            }

            // 하이라이트 그래디언트 CALayer frame 업데이트
            button.layer.sublayers?.forEach { sublayer in
                if sublayer.name == "woodHighlightGradient" {
                    sublayer.frame = bounds
                }
            }

            // shadowPath 갱신 — bounds 확정 후에만 유효한 path 설정
            if button.layer.shadowOpacity > 0 && bounds.width > 0 {
                button.layer.shadowPath = UIBezierPath(
                    roundedRect: bounds,
                    cornerRadius: button.layer.cornerRadius
                ).cgPath
            }
        }

        // Wave animation projection 재계산
        if isWaveAnimationActive {
            rebuildKeyProjections()
        }
        if isEdgeGlowAnimationActive {
            rebuildKeyProjections()
        }
    }

    // MARK: - Wave Animation (Matrix Pulse)

    // 웨이브 색상 캐싱 — 매 프레임 UIColor 할당 방지
    private static let waveBaseColor = UIColor(hex: "#00AA20")
    private static let wavePeakColor = UIColor(hex: "#00FF41")
    private static let waveGlowColor = UIColor(hex: "#66FF88")

    /// buildKeyboard() 완료 후 호출 — 새 버튼 목록에 맞춰 웨이브 갱신
    private func restartWaveAnimationAfterBuild() {
        guard let theme = customTheme, theme.needsWaveAnimation else {
            stopWaveAnimation()
            return
        }
        guard !ProcessInfo.processInfo.isLowPowerModeEnabled else {
            stopWaveAnimation()
            return
        }

        if isWaveAnimationActive {
            // 이미 실행 중이면 projection만 재계산 (DisplayLink 유지)
            rebuildKeyProjections()
        } else {
            // 아직 시작 안 됐으면 새로 시작
            startWaveAnimationIfNeeded()
        }
    }

    private func startWaveAnimationIfNeeded() {
        guard let theme = customTheme, theme.needsWaveAnimation else {
            stopWaveAnimation()
            return
        }
        guard !ProcessInfo.processInfo.isLowPowerModeEnabled else { return }
        guard !isWaveAnimationActive else { return }

        // 안전장치: 이전 displayLink가 남아있으면 정리
        waveDisplayLink?.invalidate()
        waveDisplayLink = nil

        isWaveAnimationActive = true
        waveStartTime = CACurrentMediaTime()
        rebuildKeyProjections()

        let dl = CADisplayLink(target: self, selector: #selector(waveAnimationTick))
        if #available(iOS 15.0, *) {
            dl.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 24)
        } else {
            dl.preferredFramesPerSecond = 24
        }
        dl.add(to: .main, forMode: .common)
        waveDisplayLink = dl
    }

    private func stopWaveAnimation() {
        guard isWaveAnimationActive else { return }
        isWaveAnimationActive = false
        waveDisplayLink?.invalidate()
        waveDisplayLink = nil
        cachedKeyProjections = []

        if let theme = customTheme {
            for button in allKeyButtons {
                button.setTitleColor(theme.keyTextColor, for: .normal)
            }
        }
    }

    private func rebuildKeyProjections() {
        cachedKeyProjections.removeAll(keepingCapacity: true)
        guard !allKeyButtons.isEmpty else { return }

        let dirX: CGFloat = 0.5
        let dirY: CGFloat = 0.866

        let kbBounds = bounds
        guard kbBounds.width > 0, kbBounds.height > 0 else { return }

        let maxDist = kbBounds.width * dirX + kbBounds.height * dirY

        for button in allKeyButtons {
            let center = button.superview?.convert(button.center, to: self) ?? button.center
            let proj = (center.x * dirX + center.y * dirY) / maxDist
            cachedKeyProjections.append((button: button, projection: proj))
        }
    }

    @objc private func waveAnimationTick() {
        guard isWaveAnimationActive, let _ = customTheme else { return }

        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            stopWaveAnimation()
            return
        }

        let elapsed = CACurrentMediaTime() - waveStartTime
        let wavePeriod: Double = 3.5
        let waveWidth: CGFloat = 0.25

        let phase = CGFloat(elapsed.truncatingRemainder(dividingBy: wavePeriod) / wavePeriod)
        let waveFront = phase * (1.0 + waveWidth * 2) - waveWidth

        let baseColor = Self.waveBaseColor
        let peakColor = Self.wavePeakColor
        let glowColor = Self.waveGlowColor

        for (button, proj) in cachedKeyProjections {
            let dist = abs(proj - waveFront)

            let intensity: CGFloat
            if dist < waveWidth {
                intensity = (cos(dist / waveWidth * .pi) + 1.0) / 2.0
            } else {
                intensity = 0
            }

            let titleColor: UIColor
            if intensity > 0.8 {
                let t = (intensity - 0.8) / 0.2
                titleColor = interpolateColor(from: peakColor, to: glowColor, t: t)
            } else if intensity > 0 {
                let t = intensity / 0.8
                titleColor = interpolateColor(from: baseColor, to: peakColor, t: t)
            } else {
                titleColor = baseColor
            }

            if button.titleColor(for: .normal) != titleColor {
                button.setTitleColor(titleColor, for: .normal)
            }
        }
    }

    private func interpolateColor(from: UIColor, to: UIColor, t: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        from.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        to.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)

        let clampedT = min(max(t, 0), 1)
        return UIColor(
            red: r1 + (r2 - r1) * clampedT,
            green: g1 + (g2 - g1) * clampedT,
            blue: b1 + (b2 - b1) * clampedT,
            alpha: a1 + (a2 - a1) * clampedT
        )
    }

    // MARK: - Edge Glow Animation

    // Edge Glow 색상 캐싱
    private var cachedEdgeGlowColor: UIColor = UIColor(hex: "#00FF55")

    // Edge Glow 공유 ColorSpace (매 프레임 생성 방지)
    private static let deviceRGBColorSpace = CGColorSpaceCreateDeviceRGB()

    // Edge Glow 밝기 파라미터
    private static let edgeGlowWavePeriod: Double = 3.5
    private static let edgeGlowWaveWidth: CGFloat = 0.25
    private static let edgeGlowIdleTimeout: CFTimeInterval = 4.0

    // Idle 웨이브 밝기 범위
    private static let edgeGlowIdleBorderAlphaBase: CGFloat = 0.35
    private static let edgeGlowIdleBorderAlphaPeak: CGFloat = 0.70
    private static let edgeGlowIdleTextAlphaBase: CGFloat = 0.45
    private static let edgeGlowIdleTextAlphaPeak: CGFloat = 0.85
    private static let edgeGlowIdleShadowBase: Float = 0.25
    private static let edgeGlowIdleShadowPeak: Float = 0.35

    // Typing dim 밝기
    private static let edgeGlowTypingBorderAlpha: CGFloat = 0.45
    private static let edgeGlowTypingTextAlpha: CGFloat = 0.55
    private static let edgeGlowTypingShadow: Float = 0.15

    // Typing flash 밝기 (눌린 키)
    private static let edgeGlowFlashBorderAlpha: CGFloat = 0.95
    private static let edgeGlowFlashTextAlpha: CGFloat = 1.0
    private static let edgeGlowFlashShadow: Float = 0.6
    private static let edgeGlowFlashShadowRadius: CGFloat = 8.0
    private static let edgeGlowFlashDuration: CFTimeInterval = 0.15

    /// 키 누름 flash 애니메이션 표시 시간
    private static let keyFlashDuration: TimeInterval = 0.15

    /// flash 완료 후 keyboard rebuild까지 여유 시간
    private static let buildDelayAfterFlash: TimeInterval = keyFlashDuration + 0.03

    private func restartEdgeGlowAfterBuild() {
        guard let theme = customTheme, theme.needsEdgeGlowAnimation else {
            stopEdgeGlowAnimation()
            return
        }
        guard !ProcessInfo.processInfo.isLowPowerModeEnabled else {
            stopEdgeGlowAnimation()
            return
        }

        // 테마 색상 캐시 업데이트
        if case .edgeGlow(let borderColor, _) = theme.keyVisualStyle {
            cachedEdgeGlowColor = borderColor
        }

        if isEdgeGlowAnimationActive {
            rebuildKeyProjections()
        } else {
            startEdgeGlowAnimation()
        }
    }

    private func startEdgeGlowAnimation() {
        guard let theme = customTheme, theme.needsEdgeGlowAnimation else { return }
        guard !ProcessInfo.processInfo.isLowPowerModeEnabled else { return }
        guard !isEdgeGlowAnimationActive else { return }

        edgeGlowDisplayLink?.invalidate()
        edgeGlowDisplayLink = nil

        isEdgeGlowAnimationActive = true
        edgeGlowStartTime = CACurrentMediaTime()
        edgeGlowState = .idle
        edgeGlowIdleTransition = 1.0
        rebuildKeyProjections()

        let dl = CADisplayLink(target: self, selector: #selector(edgeGlowAnimationTick))
        if #available(iOS 15.0, *) {
            dl.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 24)
        } else {
            dl.preferredFramesPerSecond = 24
        }
        dl.add(to: .main, forMode: .common)
        edgeGlowDisplayLink = dl
    }

    private func stopEdgeGlowAnimation() {
        guard isEdgeGlowAnimationActive else { return }
        isEdgeGlowAnimationActive = false
        edgeGlowDisplayLink?.invalidate()
        edgeGlowDisplayLink = nil
        edgeGlowState = .idle

        // 모든 키를 기본 상태로 복원
        if let theme = customTheme {
            for button in allKeyButtons {
                button.setTitleColor(theme.keyTextColor, for: .normal)
                if case .edgeGlow(let bc, _) = theme.keyVisualStyle {
                    button.layer.borderColor = bc.withAlphaComponent(0.4).cgColor
                    button.layer.shadowOpacity = 0.2
                    button.layer.shadowRadius = 3.0
                }
            }
        }
    }

    @objc private func edgeGlowAnimationTick() {
        guard isEdgeGlowAnimationActive, let theme = customTheme else { return }

        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            stopEdgeGlowAnimation()
            return
        }

        let now = CACurrentMediaTime()

        // ── 상태 전환 감지 ──
        let timeSinceLastKey = now - edgeGlowLastKeypressTime
        if edgeGlowState == .typing && timeSinceLastKey > Self.edgeGlowIdleTimeout {
            edgeGlowState = .idle
            edgeGlowStartTime = now
        }

        // ── 부드러운 idle ↔ typing 전환 (lerp) ──
        let targetTransition: CGFloat = (edgeGlowState == .idle) ? 1.0 : 0.0
        let lerpSpeed: CGFloat = 0.08
        edgeGlowIdleTransition += (targetTransition - edgeGlowIdleTransition) * lerpSpeed

        // ── 만료된 flash 정리 ──
        edgeGlowFlashedButtons.removeAll { now - $0.flashTime > Self.edgeGlowFlashDuration }

        // ── 현재 flash 중인 버튼 Set 구축 (O(1) lookup) ──
        let flashedSet = Set(edgeGlowFlashedButtons.map { ObjectIdentifier($0.button) })

        // ── 웨이브 계산 (idle일 때만 유효) ──
        let elapsed = now - edgeGlowStartTime
        let phase = CGFloat(elapsed.truncatingRemainder(dividingBy: Self.edgeGlowWavePeriod) / Self.edgeGlowWavePeriod)
        let waveFront = phase * (1.0 + Self.edgeGlowWaveWidth * 2) - Self.edgeGlowWaveWidth

        // ── 색상 컴포넌트 1회 추출 ──
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        cachedEdgeGlowColor.getRed(&r, green: &g, blue: &b, alpha: &a)

        for (button, proj) in cachedKeyProjections {

            // ── flash 중인 키는 건너뜀 ──
            if flashedSet.contains(ObjectIdentifier(button)) {
                continue
            }

            // ── 교정/번역 모드 활성 시 return 키 건너뜀 ──
            if returnKeyModeOverride != nil && button.accessibilityLabel == Self.returnKey {
                continue
            }

            // ── Idle 웨이브 밝기 ──
            let dist = abs(proj - waveFront)
            let waveIntensity: CGFloat
            if dist < Self.edgeGlowWaveWidth {
                waveIntensity = (cos(dist / Self.edgeGlowWaveWidth * .pi) + 1.0) / 2.0
            } else {
                waveIntensity = 0
            }

            let idleBorderAlpha = Self.edgeGlowIdleBorderAlphaBase + waveIntensity * (Self.edgeGlowIdleBorderAlphaPeak - Self.edgeGlowIdleBorderAlphaBase)
            let idleTextAlpha = Self.edgeGlowIdleTextAlphaBase + waveIntensity * (Self.edgeGlowIdleTextAlphaPeak - Self.edgeGlowIdleTextAlphaBase)
            let idleShadow = Self.edgeGlowIdleShadowBase + Float(waveIntensity) * (Self.edgeGlowIdleShadowPeak - Self.edgeGlowIdleShadowBase)
            let idleShadowRadius: CGFloat = 3.0 + waveIntensity * 5.0

            let typingBorderAlpha = Self.edgeGlowTypingBorderAlpha
            let typingTextAlpha = Self.edgeGlowTypingTextAlpha
            let typingShadow = Self.edgeGlowTypingShadow

            // ── idle ↔ typing 블렌딩 ──
            let t = edgeGlowIdleTransition
            let finalBorderAlpha = idleBorderAlpha * t + typingBorderAlpha * (1.0 - t)
            let finalTextAlpha = idleTextAlpha * t + typingTextAlpha * (1.0 - t)
            let finalShadow = idleShadow * Float(t) + typingShadow * Float(1.0 - t)
            let finalShadowRadius = idleShadowRadius * t + 3.0 * (1.0 - t)

            // ── 적용 ──
            let colorSpace = Self.deviceRGBColorSpace
            var borderComponents: [CGFloat] = [r, g, b, finalBorderAlpha]
            if let borderCG = CGColor(colorSpace: colorSpace, components: &borderComponents) {
                button.layer.borderColor = borderCG
            }
            var textComponents: [CGFloat] = [r, g, b, finalTextAlpha]
            if let textCG = CGColor(colorSpace: colorSpace, components: &textComponents) {
                button.setTitleColor(UIColor(cgColor: textCG), for: .normal)
            }
            button.layer.shadowOpacity = finalShadow
            button.layer.shadowRadius = finalShadowRadius
        }
    }

    private func edgeGlowKeyPressed(_ button: UIButton) {
        guard isEdgeGlowAnimationActive else { return }

        let now = CACurrentMediaTime()

        // 상태 전환: idle → typing
        edgeGlowState = .typing
        edgeGlowLastKeypressTime = now

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        cachedEdgeGlowColor.getRed(&r, green: &g, blue: &b, alpha: &a)

        // 눌린 키 즉시 번쩍
        let colorSpace = Self.deviceRGBColorSpace
        var flashComponents: [CGFloat] = [r, g, b, Self.edgeGlowFlashBorderAlpha]
        if let flashCG = CGColor(colorSpace: colorSpace, components: &flashComponents) {
            button.layer.borderColor = flashCG
        }
        var textComponents: [CGFloat] = [r, g, b, Self.edgeGlowFlashTextAlpha]
        if let textCG = CGColor(colorSpace: colorSpace, components: &textComponents) {
            button.setTitleColor(UIColor(cgColor: textCG), for: .normal)
        }
        button.layer.shadowOpacity = Self.edgeGlowFlashShadow
        button.layer.shadowRadius = Self.edgeGlowFlashShadowRadius

        // flash 목록에 등록
        edgeGlowFlashedButtons.append((button: button, flashTime: now))
    }

    // MARK: - Mercury Ripple Lens Animation

    private func startLensAnimation() {
        guard !isLensAnimationActive else { return }
        guard let _ = mercuryRippleView, mercuryRippleView?.isActive == true else { return }
        guard !ProcessInfo.processInfo.isLowPowerModeEnabled else { return }

        isLensAnimationActive = true
        rebuildLensButtonCache()

        // button.transform 스케일 방식 → lineBreakMode, clipsToBounds 조작 불필요

        lensDisplayLink?.invalidate()
        lensDisplayLink = nil

        let dl = CADisplayLink(target: self, selector: #selector(lensAnimationTick))
        if #available(iOS 15.0, *) {
            dl.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 24)
        } else {
            dl.preferredFramesPerSecond = 24
        }
        dl.add(to: .main, forMode: .common)
        lensDisplayLink = dl
    }

    private func stopLensAnimation() {
        guard isLensAnimationActive else { return }
        isLensAnimationActive = false
        lensDisplayLink?.invalidate()
        lensDisplayLink = nil
        cachedButtonCentersInRippleView.removeAll()

        // 모든 버튼 트랜스폼 리셋 (button.transform 방식이므로 별도 복원 불필요)
        for button in allKeyButtons {
            button.transform = .identity
        }
    }

    private func pauseLensAnimation() {
        guard isLensAnimationActive else { return }
        isLensAnimationActive = false
        lensDisplayLink?.invalidate()
        lensDisplayLink = nil

        // button.transform 방식이므로 별도 clipsToBounds 복원 불필요
        // pause 후 resume 시 다시 캐시 재구축됨
    }

    private func resumeLensAnimation() {
        guard !isLensAnimationActive else { return }
        guard let rv = mercuryRippleView, rv.isActive else { return }
        guard !ProcessInfo.processInfo.isLowPowerModeEnabled else { return }

        isLensAnimationActive = true
        rebuildLensButtonCache()

        let dl = CADisplayLink(target: self, selector: #selector(lensAnimationTick))
        if #available(iOS 15.0, *) {
            dl.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 24)
        } else {
            dl.preferredFramesPerSecond = 24
        }
        dl.add(to: .main, forMode: .common)
        lensDisplayLink = dl
    }

    private func rebuildLensButtonCache() {
        cachedButtonCentersInRippleView.removeAll(keepingCapacity: true)
        guard let rv = mercuryRippleView, !allKeyButtons.isEmpty else { return }

        for button in allKeyButtons {
            let center = button.superview?.convert(button.center, to: rv) ?? button.center
            cachedButtonCentersInRippleView.append((button: button, center: center))
        }
    }

    @objc private func lensAnimationTick() {
        guard isLensAnimationActive, let rv = mercuryRippleView else { return }

        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            stopLensAnimation()
            return
        }

        let snapshots = rv.activeRippleSnapshots()

        // 리플이 없으면 모든 버튼 리셋 후 idle
        if snapshots.isEmpty {
            for (button, _) in cachedButtonCentersInRippleView {
                if button.transform != .identity {
                    button.transform = .identity
                }
            }
            return
        }

        let perspY = MercuryRippleView.perspectiveY

        for (button, btnCenter) in cachedButtonCentersInRippleView {
            var totalContribution: CGFloat = 0

            for snap in snapshots {
                // 리플 중심으로부터 거리 (Y축 perspectiveY 압축 적용)
                let dx = btnCenter.x - snap.centerX
                let dy = (btnCenter.y - snap.centerY) / perspY
                let dist = sqrt(dx * dx + dy * dy)

                // 파면(radius)으로부터의 거리
                let distFromWavefront = abs(dist - snap.radius)

                // ringWidth 이내일 때만 기여
                guard distFromWavefront < snap.ringWidth else { continue }

                // cosine bell curve: 파면 위에서 최대, 멀어질수록 0
                let t = distFromWavefront / snap.ringWidth
                let bell = (cos(t * .pi) + 1.0) * 0.5

                // 수명에 따른 fade (ease-out: 1 - progress²)
                let fade = 1.0 - snap.progress * snap.progress

                totalContribution += bell * fade * snap.intensity
            }

            // scale = 1.0 + total * 0.15, max 1.12 (인접 키 겹침 방지 + 효과 유지)
            let scale = min(1.0 + totalContribution * 0.15, 1.12)

            if scale > 1.001 {
                button.transform = CGAffineTransform(scaleX: scale, y: scale)
            } else if button.transform != .identity {
                button.transform = .identity
            }
        }
    }

    func handlePowerStateChange() {
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            stopWaveAnimation()
            matrixRainView?.stopAnimation()
            mercuryRippleView?.stopAnimation()
            stopLensAnimation()
            stardustView?.stopAnimation()
            snowfallView?.stopAnimation()
            cherryBlossomView?.stopAnimation()
            stopEdgeGlowAnimation()
        } else {
            if let theme = customTheme, theme.needsWaveAnimation {
                startWaveAnimationIfNeeded()
            }
            if let theme = customTheme, theme.needsRainAnimation,
               !isMemoryConstrained {
                matrixRainView?.startAnimation()
            }
            if let theme = customTheme, theme.needsRippleAnimation,
               !isMemoryConstrained {
                mercuryRippleView?.startAnimation()
                startLensAnimation()
            }
            if let theme = customTheme, theme.needsStardustAnimation,
               !isMemoryConstrained {
                stardustView?.startAnimation()
            }
            if let theme = customTheme, theme.needsEdgeGlowAnimation {
                startEdgeGlowAnimation()
            }
            if let theme = customTheme, theme.needsSnowfallAnimation,
               !isMemoryConstrained {
                snowfallView?.startAnimation()
            }
            if let theme = customTheme, theme.needsCherryBlossomAnimation,
               !isMemoryConstrained {
                cherryBlossomView?.startAnimation()
            }
        }
    }

    @objc private func handleMemoryWarning() {
        isMemoryConstrained = true

        if let rv = matrixRainView {
            rv.stopAnimation()
            rv.removeFromSuperview()
            matrixRainView = nil
        }

        // 리플 + 렌즈 애니메이션 정리
        stopLensAnimation()
        if let rv = mercuryRippleView {
            rv.stopAnimation()
            rv.removeFromSuperview()
            mercuryRippleView = nil
        }

        if let sv = stardustView {
            sv.stopAnimation()
            sv.removeFromSuperview()
            stardustView = nil
        }

        if let sv = snowfallView {
            sv.stopAnimation()
            sv.removeFromSuperview()
            snowfallView = nil
        }

        if let cv = cherryBlossomView {
            cv.stopAnimation()
            cv.removeFromSuperview()
            cherryBlossomView = nil
        }

        if isWaveAnimationActive {
            stopWaveAnimation()
        }
        if isEdgeGlowAnimationActive {
            stopEdgeGlowAnimation()
        }

        // Phase 7: asyncAfter 복구 제거
        // 키보드 확장은 dismiss 후 RunLoop가 정지되어 asyncAfter가 실행되지 않음.
        // isMemoryConstrained 리셋은 updateAppearance() 진입 시 처리됨 (변경 2 참조).
    }

    // MARK: - Early Teardown (키보드 dismiss 시 호출)

    #if DEBUG
    /// 진단 전용 메모리 측정 — phys_footprint (Jetsam이 사용하는 실제 기준)
    private func diagnosticMemoryMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            return Double(info.phys_footprint) / (1024 * 1024)
        }
        return 0
    }
    #endif

    /// KeyboardViewController.viewWillDisappear에서 호출.
    /// 무거운 애니메이션 뷰와 CADisplayLink를 즉시 정리하여 오버랩 구간 메모리 피크 억제.
    /// 멱등성(Idempotent) 보장 — 여러 번 호출해도 안전.
    func prepareForDismiss() {
        #if DEBUG
        let mem0 = diagnosticMemoryMB()
        NSLog("🔬 prepareForDismiss START — Memory: \(String(format: "%.2f", mem0)) MB")
        NSLog("🔬 DisplayLinks — wave:\(waveDisplayLink != nil) lens:\(lensDisplayLink != nil) edgeGlow:\(edgeGlowDisplayLink != nil) trackpad:\(displayLink != nil)")
        NSLog("🔬 AnimViews — matrix:\(matrixRainView != nil) mercury:\(mercuryRippleView != nil) stardust:\(stardustView != nil) snowfall:\(snowfallView != nil) cherry:\(cherryBlossomView != nil)")
        #endif

        // CADisplayLink 전부 정지 + 해제
        stopWaveAnimation()
        waveDisplayLink?.invalidate()
        waveDisplayLink = nil

        stopLensAnimation()
        lensDisplayLink?.invalidate()
        lensDisplayLink = nil

        stopEdgeGlowAnimation()
        edgeGlowDisplayLink?.invalidate()
        edgeGlowDisplayLink = nil

        displayLink?.invalidate()
        displayLink = nil

        #if DEBUG
        let mem1 = diagnosticMemoryMB()
        NSLog("🔬 [A] CADisplayLink 해제 후 — Memory: \(String(format: "%.2f", mem1)) MB (delta: \(String(format: "%.2f", mem1 - mem0)) MB)")
        #endif

        // 애니메이션 뷰 정지 + 제거 + nil
        if let rv = matrixRainView {
            rv.stopAnimation()
            rv.removeFromSuperview()
            matrixRainView = nil
            #if DEBUG
            let m = diagnosticMemoryMB()
            NSLog("🔬 [B1] matrixRainView 해제 — Memory: \(String(format: "%.2f", m)) MB")
            #endif
        }
        if let rv = mercuryRippleView {
            rv.stopAnimation()
            rv.removeFromSuperview()
            mercuryRippleView = nil
            #if DEBUG
            let m = diagnosticMemoryMB()
            NSLog("🔬 [B2] mercuryRippleView 해제 — Memory: \(String(format: "%.2f", m)) MB")
            #endif
        }
        if let sv = stardustView {
            sv.stopAnimation()
            sv.removeFromSuperview()
            stardustView = nil
            #if DEBUG
            let m = diagnosticMemoryMB()
            NSLog("🔬 [B3] stardustView 해제 — Memory: \(String(format: "%.2f", m)) MB")
            #endif
        }
        if let sv = snowfallView {
            sv.stopAnimation()
            sv.removeFromSuperview()
            snowfallView = nil
            #if DEBUG
            let m = diagnosticMemoryMB()
            NSLog("🔬 [B4] snowfallView 해제 — Memory: \(String(format: "%.2f", m)) MB")
            #endif
        }
        if let cv = cherryBlossomView {
            cv.stopAnimation()
            cv.removeFromSuperview()
            cherryBlossomView = nil
            #if DEBUG
            let m = diagnosticMemoryMB()
            NSLog("🔬 [B5] cherryBlossomView 해제 — Memory: \(String(format: "%.2f", m)) MB")
            #endif
        }

        // Phase 9: patternImageView backing store 해제
        if let pv = patternImageView {
            pv.backgroundColor = nil  // UIColor(patternImage:) 해제 — CGImage backing 즉시 free
            pv.removeFromSuperview()
            patternImageView = nil
            #if DEBUG
            let m = diagnosticMemoryMB()
            NSLog("🔬 [C1] patternImageView 해제 — Memory: \(String(format: "%.2f", m)) MB")
            #endif
        }

        // Phase 9: woodTileImageView backing store 해제
        if let wv = woodTileImageView {
            wv.backgroundColor = nil  // UIColor(patternImage: tileImg) 해제
            wv.removeFromSuperview()
            woodTileImageView = nil
            #if DEBUG
            let m = diagnosticMemoryMB()
            NSLog("🔬 [C2] woodTileImageView 해제 — Memory: \(String(format: "%.2f", m)) MB")
            #endif
        }

        // Phase 9: gradientLayer backing store 해제
        if let gl = gradientLayer {
            gl.removeFromSuperlayer()
            gradientLayer = nil
            #if DEBUG
            let m = diagnosticMemoryMB()
            NSLog("🔬 [C3] gradientLayer 해제 — Memory: \(String(format: "%.2f", m)) MB")
            #endif
        }

        #if DEBUG
        let memEnd = diagnosticMemoryMB()
        NSLog("🔬 prepareForDismiss END — Memory: \(String(format: "%.2f", memEnd)) MB (총 delta: \(String(format: "%.2f", memEnd - mem0)) MB)")
        #endif
    }

    deinit {
        stopWaveAnimation()
        waveDisplayLink?.invalidate()
        waveDisplayLink = nil
        stopLensAnimation()
        lensDisplayLink?.invalidate()
        lensDisplayLink = nil
        matrixRainView?.stopAnimation()
        mercuryRippleView?.stopAnimation()
        stardustView?.stopAnimation()
        snowfallView?.stopAnimation()
        cherryBlossomView?.stopAnimation()
        stopEdgeGlowAnimation()
        edgeGlowDisplayLink?.invalidate()
        edgeGlowDisplayLink = nil
        NotificationCenter.default.removeObserver(self, name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
    }

    func getCurrentLanguage() -> KeyboardLanguage {
        return currentLanguage
    }

    func setLanguage(_ language: KeyboardLanguage) {
        let oldLang = currentLanguage
        let oldPage = currentPage
        let wasShifted = isShifted
        currentLanguage = language
        isShifted = false
        currentPage = .letters
        // 초기 로딩, 심볼 페이지, 또는 버튼 미생성 시 풀 build
        if allKeyButtons.isEmpty || oldPage != .letters {
            buildKeyboard()
        } else {
            updateKeyLabelsForLanguage(from: oldLang, to: language, wasShifted: wasShifted)
        }
    }

    /// Shift 상태 변경 시 키 라벨만 업데이트 (전체 rebuild 없이)
    /// UI/UX 시각적 결과는 buildKeyboard()와 100% 동일
    ///
    /// ⚠️ 딕셔너리 매핑 방식 사용:
    ///   - zip(normalRows, shiftedRows)로 1:1 매핑 테이블 구축
    ///   - 한국어 ㅂ↔ㅃ, 영어 q↔Q 등 모든 언어에서 동작
    ///   - row 구조/인덱스에 의존하지 않으므로 하단 행 오염 불가
    ///   - specialKeys는 매핑에서 제외되어 자동 보호
    private func updateKeyLabelsForShift() {
        // 심볼/숫자 페이지에서는 Shift 개념 없음
        guard currentPage == .letters else { return }
        // buildKeyboard() 진행 중이면 스킵 (rebuild가 완료되면 올바른 상태가 됨)
        guard !isRebuilding else { return }
        // buildKeyboard() 완료 전 (초기화 전)에는 스킵
        guard !allKeyButtons.isEmpty else { return }

        // 현재 언어의 normal/shifted 배열 가져오기
        let normalRows: [[String]]
        let shiftedRows: [[String]]
        switch currentLanguage {
        case .korean:
            normalRows = Self.koreanRows
            shiftedRows = Self.koreanShiftRows
        case .russian:
            normalRows = Self.russianRows
            shiftedRows = Self.russianShiftRows
        default:
            normalRows = Self.englishRows
            shiftedRows = Self.englishShiftRows
        }

        // 딕셔너리 매핑 구축: 현재 버튼 라벨 → 목표 라벨
        // isShifted=true  → 버튼은 현재 normal 상태, 목표는 shifted
        // isShifted=false → 버튼은 현재 shifted 상태, 목표는 normal
        var labelMapping: [String: String] = [:]
        for (normalRow, shiftedRow) in zip(normalRows, shiftedRows) {
            for (normal, shifted) in zip(normalRow, shiftedRow) {
                // special key(\u{21E7}, \u{232B} 등)는 매핑에서 제외
                guard !Self.specialKeys.contains(normal) else { continue }
                if isShifted {
                    labelMapping[normal] = shifted   // ㅂ → ㅃ, q → Q
                } else {
                    labelMapping[shifted] = normal   // ㅃ → ㅂ, Q → q
                }
            }
        }

        // 모든 키 버튼 순회하며 라벨 교체
        for button in allKeyButtons {
            guard let currentLabel = button.accessibilityLabel else { continue }

            // Shift 키 자체 — 아이콘/배경 업데이트
            if currentLabel == Self.shiftKey {
                let config = UIImage.SymbolConfiguration(
                    pointSize: 16, weight: isShifted ? .bold : .regular)
                button.setImage(
                    UIImage(systemName: isShifted ? "shift.fill" : "shift",
                            withConfiguration: config),
                    for: .normal)
                if isShifted {
                    button.backgroundColor = customTheme?.keyBackground
                        ?? (isDark ? UIColor(white: 0.55, alpha: 1)
                                   : UIColor(white: 0.95, alpha: 1))
                } else {
                    button.backgroundColor = customTheme?.specialKeyBackground
                        ?? (isDark ? UIColor(white: 0.35, alpha: 1)
                                   : UIColor(white: 0.78, alpha: 1))
                }
                continue
            }

            // 딕셔너리에서 새 라벨 조회
            // - 매핑 있음 → 라벨 교체 (문자 키)
            // - 매핑 없음 → skip (special key, 숫자, 또는 변경 불필요한 키)
            if let newLabel = labelMapping[currentLabel] {
                button.setTitle(newLabel, for: .normal)
                button.accessibilityLabel = newLabel
            }
        }
    }

    /// symbols1 ↔ symbols2 전환 시 라벨만 즉시 교체 (전체 rebuild 없이)
    /// UI/UX 시각적 결과는 buildKeyboard()와 100% 동일
    ///
    /// ⚠️ 사용 조건: symbols1 → symbols2, 또는 symbols2 → symbols1 에서만 호출
    /// ⚠️ letters → symbols, symbols → letters 전환에는 사용 금지 → buildKeyboard() 사용
    private func updateKeyLabelsForSymbolPage(from oldPage: KeyboardPage, to newPage: KeyboardPage) {
        guard !isRebuilding else { return }
        guard !allKeyButtons.isEmpty else {
            buildKeyboard()
            return
        }

        // 전환 전/후 심볼 배열 결정
        let oldRows: [[String]]
        let newRows: [[String]]
        switch oldPage {
        case .symbols1:
            oldRows = Self.symbolRows1
        case .symbols2:
            oldRows = Self.symbolRows2
        default:
            buildKeyboard()
            return
        }
        switch newPage {
        case .symbols1:
            newRows = Self.symbolRows1
        case .symbols2:
            newRows = Self.symbolRows2
        default:
            buildKeyboard()
            return
        }

        // 행 구조 호환성 검증
        if oldRows.count != newRows.count {
            buildKeyboard()
            return
        }
        for (oldRow, newRow) in zip(oldRows, newRows) {
            if oldRow.count != newRow.count {
                buildKeyboard()
                return
            }
        }

        // 딕셔너리 매핑 구축: 현재 버튼 라벨 → 목표 라벨
        var labelMapping: [String: String] = [:]
        for (oldRow, newRow) in zip(oldRows, newRows) {
            for (oldKey, newKey) in zip(oldRow, newRow) {
                guard !Self.specialKeys.contains(oldKey) else { continue }
                guard !Self.specialKeys.contains(newKey) else { continue }
                if oldKey != newKey {
                    labelMapping[oldKey] = newKey
                }
            }
        }

        // 토글 키 매핑: "#+=", "123"은 specialKeys에 포함 → 명시적 처리
        let toggleKeyMapping: [String: String]
        if oldPage == .symbols1 && newPage == .symbols2 {
            toggleKeyMapping = [Self.moreSymKey: Self.symbolKey]
        } else if oldPage == .symbols2 && newPage == .symbols1 {
            toggleKeyMapping = [Self.symbolKey: Self.moreSymKey]
        } else {
            toggleKeyMapping = [:]
        }

        // 모든 키 버튼 순회하며 라벨 교체
        for button in allKeyButtons {
            guard let currentLabel = button.accessibilityLabel else { continue }

            // 토글 키 ("#+=" ↔ "123")
            if let newToggleLabel = toggleKeyMapping[currentLabel] {
                button.setTitle(newToggleLabel, for: .normal)
                button.accessibilityLabel = newToggleLabel
                continue
            }

            // 심볼 키 — 딕셔너리에서 새 라벨 조회
            if let newLabel = labelMapping[currentLabel] {
                button.setTitle(newLabel, for: .normal)
                button.accessibilityLabel = newLabel
            }
        }
    }

    /// 행 구조가 동일한 언어 간 전환 시 라벨만 즉시 교체 (전체 rebuild 없이)
    /// UI/UX 시각적 결과는 buildKeyboard()와 100% 동일
    ///
    /// ⚠️ 사용 조건: 전환 전후 언어의 행별 키 개수가 동일할 때만 호출
    /// ⚠️ 러시아어(11,11,11) ↔ 영어/한국어(10,9,9) 전환에는 사용 금지 → buildKeyboard() 사용
    private func updateKeyLabelsForLanguage(from oldLanguage: KeyboardLanguage, to newLanguage: KeyboardLanguage, wasShifted: Bool) {
        guard !isRebuilding else { return }
        guard !allKeyButtons.isEmpty else {
            buildKeyboard()
            return
        }

        // 전환 전 언어의 배열 (현재 버튼에 표시된 라벨 기준)
        // ⚠️ wasShifted 파라미터 사용 — 호출 시점에서 isShifted는 이미 false로 리셋됨
        let oldRows: [[String]]
        switch oldLanguage {
        case .korean:
            oldRows = wasShifted ? Self.koreanShiftRows : Self.koreanRows
        case .russian:
            oldRows = wasShifted ? Self.russianShiftRows : Self.russianRows
        default:
            oldRows = wasShifted ? Self.englishShiftRows : Self.englishRows
        }

        // 전환 후 언어의 배열 (목표 라벨)
        // ⚠️ 언어 전환 시 isShifted는 false로 리셋되므로 항상 normal rows
        let newRows: [[String]]
        switch newLanguage {
        case .korean:
            newRows = Self.koreanRows
        case .russian:
            newRows = Self.russianRows
        default:
            newRows = Self.englishRows
        }

        // 행 구조 호환성 검증 — 만약 키 수가 다르면 안전하게 풀 rebuild
        let oldLetterRows = oldRows.dropLast()
        let newLetterRows = newRows.dropLast()
        if oldLetterRows.count != newLetterRows.count {
            buildKeyboard()
            return
        }
        for (oldRow, newRow) in zip(oldLetterRows, newLetterRows) {
            if oldRow.count != newRow.count {
                buildKeyboard()
                return
            }
        }

        // 딕셔너리 매핑 구축: 현재 버튼 라벨 → 목표 라벨
        var labelMapping: [String: String] = [:]
        for (oldRow, newRow) in zip(oldRows, newRows) {
            for (oldKey, newKey) in zip(oldRow, newRow) {
                guard !Self.specialKeys.contains(oldKey) else { continue }
                guard !Self.specialKeys.contains(newKey) else { continue }
                if oldKey != newKey {
                    labelMapping[oldKey] = newKey
                }
            }
        }

        // 모든 키 버튼 순회하며 라벨 교체
        for button in allKeyButtons {
            guard let currentLabel = button.accessibilityLabel else { continue }

            // Shift 키 — isShifted가 false로 리셋되었으므로 normal 상태로 업데이트
            if currentLabel == Self.shiftKey {
                let config = UIImage.SymbolConfiguration(
                    pointSize: 16, weight: .regular)
                button.setImage(
                    UIImage(systemName: "shift", withConfiguration: config),
                    for: .normal)
                button.backgroundColor = customTheme?.specialKeyBackground
                    ?? (isDark ? UIColor(white: 0.35, alpha: 1)
                               : UIColor(white: 0.78, alpha: 1))
                continue
            }

            // 🌐 Globe 키 — 전환 후 "다른 언어" 라벨 업데이트
            if currentLabel == Self.globeLangKey {
                for subview in button.subviews {
                    if let langLabel = subview as? UILabel {
                        langLabel.text = (newLanguage == .english)
                            ? pairedLanguage.shortLabel
                            : "A"
                        break
                    }
                }
                continue
            }

            // 스페이스 바 — 언어 표시명 업데이트
            if currentLabel == " " {
                button.setTitle(newLanguage.displayName, for: .normal)
                continue
            }

            // 문자 키 — 딕셔너리에서 새 라벨 조회
            if let newLabel = labelMapping[currentLabel] {
                button.setTitle(newLabel, for: .normal)
                button.accessibilityLabel = newLabel
            }
        }
    }

    func setShifted(_ shifted: Bool) {
        guard currentPage == .letters else { return }
        guard isShifted != shifted else { return }
        isShifted = shifted
        updateKeyLabelsForShift()
    }

    // MARK: - Mode-Aware Return Key (Proposal 03)

    func updateReturnKey(mode: KeyboardMode, hasText: Bool) {
        returnKeyModeOverride = mode
        returnKeyHasText = hasText

        // Find the return key button and update it in-place (no full rebuild)
        guard let returnButton = allKeyButtons.first(where: { $0.accessibilityLabel == Self.returnKey }) else { return }

        switch mode {
        case .defaultMode, .phraseInputMode, .quickNoteMode:
            // Don't override — use the standard returnKeyDisplayName/returnKeyIsBlue logic
            returnButton.alpha = 1.0
            returnButton.isUserInteractionEnabled = false // touch handled at view level
            return
        case .translationMode, .correctionMode:
            break
        }

        // ── 모드 레이블 설정 ──
        let label = (mode == .translationMode) ? L("keyboard.return.translate") : L("keyboard.return.correct")
        returnButton.setTitle(label, for: .normal)
        returnButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        returnButton.setImage(nil, for: .normal)

        // ── 테마 기반 스타일링 ──
        if let theme = customTheme {
            switch theme.specialKeyVisualStyle {

            // Edge Glow: 배경 투명 + 밝은 border/glow
            case .edgeGlow(let borderColor, let glowColor):
                returnButton.backgroundColor = .clear
                returnButton.layer.borderWidth = 1.0
                returnButton.layer.borderColor = borderColor.cgColor
                returnButton.layer.shadowColor = glowColor.cgColor
                returnButton.layer.shadowOffset = .zero
                returnButton.layer.shadowRadius = 5.0
                returnButton.layer.shadowOpacity = 0.5
                returnButton.setTitleColor(theme.returnKeyAccentTextColor, for: .normal)

            // Wood Block: 나무 스타일 유지 + 테마 엑센트 배경
            case .woodBlock(let borderColor, let shadowColor, _):
                returnButton.backgroundColor = theme.returnKeyAccentColor
                returnButton.layer.borderWidth = 1
                returnButton.layer.borderColor = borderColor.cgColor
                returnButton.layer.shadowColor = shadowColor.cgColor
                returnButton.layer.shadowOffset = CGSize(width: 0, height: 3)
                returnButton.layer.shadowRadius = 1.5
                returnButton.layer.shadowOpacity = 1.0
                returnButton.setTitleColor(theme.returnKeyAccentTextColor, for: .normal)

            // Solid / Translucent: 테마 엑센트 색상 사용
            default:
                // alpha가 너무 낮은 테마 대응 (Digital Rain 0.08 등)
                let accentColor = theme.returnKeyAccentColor
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                accentColor.getRed(&r, green: &g, blue: &b, alpha: &a)
                returnButton.backgroundColor = (a < 0.25)
                    ? UIColor(red: r, green: g, blue: b, alpha: 0.25)
                    : accentColor
                returnButton.setTitleColor(theme.returnKeyAccentTextColor, for: .normal)

                // 기존 border/shadow 초기화 (다른 테마에서 전환 시 잔여값 방지)
                returnButton.layer.borderWidth = 0
                returnButton.layer.shadowOpacity = 0
            }
        } else {
            // ── 기본 테마: 기존 하드코딩 색상 유지 ──
            let defaultColor: UIColor = (mode == .translationMode)
                ? UIColor(red: 0.192, green: 0.510, blue: 0.965, alpha: 1)
                : UIColor(red: 1, green: 0.624, blue: 0.263, alpha: 1)
            returnButton.backgroundColor = defaultColor
            returnButton.setTitleColor(.white, for: .normal)

            // border/shadow 초기화
            returnButton.layer.borderWidth = 0
            returnButton.layer.shadowOpacity = 0
        }

        returnButton.alpha = hasText ? 1.0 : 0.5
    }

    func clearReturnKeyOverride() {
        returnKeyModeOverride = nil
        returnKeyHasText = true
        buildKeyboard()
    }
}
