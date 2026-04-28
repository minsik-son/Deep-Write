import UIKit

/// Touch Calibration 화면 — 자연 타이핑 기반, 고속 입력/멀티터치 안전, v3 seed 생성
final class CalibrationViewController: UIViewController {

    // MARK: - Test Data (English only)

    private let englishWords = [
        "the", "quick", "brown", "fox", "jumps",
        "over", "lazy", "dog", "pack", "my",
        "box", "with", "five", "dozen", "jug"
    ]

    // MARK: - State

    private var currentWordIndex = 0
    private var currentCharIndex = 0
    private var collectedSamples: [CalibrationTapSample] = []
    private var consecutiveRejectCount = 0

    private var currentWord: String { englishWords[currentWordIndex] }

    // MARK: - UI

    private let instructionLabel: UILabel = {
        let l = UILabel()
        l.text = "Type naturally, like you're chatting.\nDon't try to correct your finger placement."
        l.textAlignment = .center
        l.font = .systemFont(ofSize: 15, weight: .medium)
        l.numberOfLines = 3
        l.textColor = .secondaryLabel
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let wordLabel: UILabel = {
        let l = UILabel()
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let progressLabel: UILabel = {
        let l = UILabel()
        l.textAlignment = .center
        l.font = .systemFont(ofSize: 13)
        l.textColor = .tertiaryLabel
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let mirrorView = CalibrationKeyboardMirrorView()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Touch Calibration"
        view.backgroundColor = .systemBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped))

        if CalibrationSeedModel.load() != nil || hasExistingOnlineLearning() {
            showRecalibrationAlert()
        } else {
            setupUI()
            startCalibration()
        }
    }

    // MARK: - Re-calibration

    private func hasExistingOnlineLearning() -> Bool {
        UserDefaults(suiteName: AppConstants.appGroupIdentifier)?.data(forKey: "touch_offset_learning_v2") != nil
    }

    private func showRecalibrationAlert() {
        let alert = UIAlertController(
            title: "Existing Data Found",
            message: "You have existing typing data. Would you like to keep it or start fresh?",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Keep & Recalibrate", style: .default) { [weak self] _ in
            self?.setupUI()
            self?.startCalibration()
        })
        alert.addAction(UIAlertAction(title: "Reset & Recalibrate", style: .destructive) { [weak self] _ in
            UserDefaults(suiteName: AppConstants.appGroupIdentifier)?.removeObject(forKey: "touch_offset_learning_v2")
            CalibrationSeedModel.remove()
            self?.setupUI()
            self?.startCalibration()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.dismiss(animated: true)
        })
        present(alert, animated: true)
    }

    // MARK: - Setup

    private func setupUI() {
        mirrorView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mirrorView)
        view.addSubview(instructionLabel)
        view.addSubview(wordLabel)
        view.addSubview(progressLabel)

        NSLayoutConstraint.activate([
            mirrorView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mirrorView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mirrorView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            mirrorView.heightAnchor.constraint(equalToConstant: mirrorView.intrinsicContentSize.height),

            progressLabel.bottomAnchor.constraint(equalTo: mirrorView.topAnchor, constant: -8),
            progressLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            wordLabel.bottomAnchor.constraint(equalTo: progressLabel.topAnchor, constant: -4),
            wordLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            instructionLabel.bottomAnchor.constraint(equalTo: wordLabel.topAnchor, constant: -16),
            instructionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            instructionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
        ])

        // Raw touch callback — VC가 intended char 매칭 (race condition 방지)
        mirrorView.onRawTouch = { [weak self] raw in
            self?.handleRawTouch(raw)
        }
    }

    private func startCalibration() {
        currentWordIndex = 0
        currentCharIndex = 0
        collectedSamples = []
        consecutiveRejectCount = 0
        showNextWord()
    }

    // MARK: - Flow

    private func showNextWord() {
        guard currentWordIndex < englishWords.count else {
            finishCalibration()
            return
        }
        currentCharIndex = 0
        consecutiveRejectCount = 0
        updateDisplay()
    }

    private func updateDisplay() {
        let word = currentWord
        progressLabel.text = "\(currentWordIndex + 1) / \(englishWords.count)"

        // Subtle word display — bold+underline current char only
        let attributed = NSMutableAttributedString(string: word, attributes: [
            .font: UIFont.systemFont(ofSize: 32, weight: .regular),
            .foregroundColor: UIColor.label,
        ])
        if currentCharIndex < word.count {
            let range = NSRange(location: currentCharIndex, length: 1)
            attributed.addAttributes([
                .font: UIFont.systemFont(ofSize: 32, weight: .bold),
                .underlineStyle: NSUnderlineStyle.single.rawValue,
            ], range: range)
        }
        wordLabel.attributedText = attributed
    }

    // MARK: - Raw Touch → Sample Matching (race-free)

    private func handleRawTouch(_ raw: CalibrationRawTouch) {
        // Backspace
        if raw.isBackspace {
            handleBackspace()
            return
        }

        guard currentWordIndex < englishWords.count else { return }
        let word = currentWord
        guard currentCharIndex < word.count else { return }

        // Current intended char
        let intendedChar = String(word[word.index(word.startIndex, offsetBy: currentCharIndex)]).lowercased()

        // Find intended key button info from mirror letter buttons
        // (we need intended center — use approximation from actual key data)
        let intendedCenter = findIntendedCenter(for: intendedChar)
        guard let center = intendedCenter else { return }

        let dx = Float(raw.pointInKeyboard.x - center.point.x)
        let dy = Float(raw.pointInKeyboard.y - center.point.y)

        // Reject very far taps (but more lenient than before)
        let maxDist = center.keyWidth * 1.5
        if max(abs(CGFloat(dx)), abs(CGFloat(dy))) > maxDist {
            consecutiveRejectCount += 1
            // 3회 연속 reject → auto-skip this char
            if consecutiveRejectCount >= 3 {
                consecutiveRejectCount = 0
                currentCharIndex += 1
                advanceIfWordComplete()
                updateDisplay()
            }
            return
        }

        consecutiveRejectCount = 0

        let intendedSlotID = TouchCalibrationSlotID.make(row: center.row, col: center.col)
        let sample = CalibrationTapSample(
            intendedSlotID: intendedSlotID,
            intendedRow: center.row,
            intendedCol: center.col,
            intendedKey: intendedChar,
            actualSlotID: raw.actualSlotID,
            actualKey: raw.actualKey,
            actualPointInKeyboard: raw.pointInKeyboard,
            intendedCenterInKeyboard: center.point,
            deltaX: dx,
            deltaY: dy,
            isExactKey: raw.actualKey?.lowercased() == intendedChar
        )
        collectedSamples.append(sample)

        // Advance immediately (before any UI update — prevents race)
        currentCharIndex += 1
        advanceIfWordComplete()
        updateDisplay()
    }

    private func handleBackspace() {
        guard currentCharIndex > 0 else { return }
        currentCharIndex -= 1
        if !collectedSamples.isEmpty {
            collectedSamples.removeLast()
        }
        consecutiveRejectCount = 0
        updateDisplay()
    }

    private func advanceIfWordComplete() {
        if currentCharIndex >= currentWord.count {
            currentWordIndex += 1
            if currentWordIndex < englishWords.count {
                currentCharIndex = 0
                consecutiveRejectCount = 0
            }
        }
    }

    /// Mirror에서 intended key의 center 좌표/row/col 찾기
    private struct IntendedKeyInfo {
        let point: CGPoint
        let row: Int
        let col: Int
        let keyWidth: CGFloat
    }

    private func findIntendedCenter(for char: String) -> IntendedKeyInfo? {
        let rows: [[String]] = [
            ["q","w","e","r","t","y","u","i","o","p"],
            ["a","s","d","f","g","h","j","k","l"],
            ["z","x","c","v","b","n","m"]
        ]
        for (row, keys) in rows.enumerated() {
            if let col = keys.firstIndex(of: char.lowercased()) {
                // Approximate center from layout constants
                let w = mirrorView.bounds.width
                guard w > 0 else { return nil }
                let L = CalibrationKeyboardMirrorView.self  // can't access private L struct
                // Recalculate from known metrics
                let sideInset: CGFloat = 3
                let keySpacingH: CGFloat = 6
                let toolbarH: CGFloat = 40
                let topPad: CGFloat = 8
                let numRowH: CGFloat = 40
                let numRowSpV: CGFloat = 8
                let keyH: CGFloat = 46
                let keySpV: CGFloat = 10
                let topInset: CGFloat = 4
                let row1Indent: CGFloat = 18

                let indent: CGFloat = (row == 1) ? row1Indent : 0
                let keyCount = CGFloat(keys.count)
                let totalSpacing = keySpacingH * (keyCount - 1)
                let availW = w - 2 * sideInset - 2 * indent - totalSpacing
                let keyWidth = availW / keyCount
                let x = sideInset + indent + CGFloat(col) * (keyWidth + keySpacingH) + keyWidth / 2

                let keyAreaTop = topPad + toolbarH
                let numRowY = keyAreaTop + topInset
                let row0Y = numRowY + numRowH + numRowSpV
                let rowY: CGFloat
                switch row {
                case 0: rowY = row0Y
                case 1: rowY = row0Y + keyH + keySpV
                case 2: rowY = row0Y + keyH * 2 + keySpV * 2
                default: return nil
                }
                let y = rowY + keyH / 2

                return IntendedKeyInfo(point: CGPoint(x: x, y: y), row: row, col: col, keyWidth: keyWidth)
            }
        }
        return nil
    }

    // MARK: - Seed Generation

    private func finishCalibration() {
        guard !collectedSamples.isEmpty else {
            dismiss(animated: true)
            return
        }

        let model = generateSeedModel()
        model.save()

        let alert = UIAlertController(
            title: "Calibration Complete",
            message: "Your touch profile has been saved. It will be applied next time the keyboard appears.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Done", style: .default) { [weak self] _ in
            self?.dismiss(animated: true)
        })
        present(alert, animated: true)
    }

    private func generateSeedModel() -> CalibrationSeedModel {
        let approxKeyWidth: Float = Float((mirrorView.bounds.width - 6 - 54) / 10)

        // Row seeds — robust: winsorize large deltas
        var rowSamples: [Int: [(dx: Float, dy: Float)]] = [:]
        for s in collectedSamples {
            let clampX = max(-approxKeyWidth * 0.45, min(approxKeyWidth * 0.45, s.deltaX))
            let clampY = max(-46 * 0.45, min(46 * 0.45, s.deltaY))
            rowSamples[s.intendedRow, default: []].append((clampX, clampY))
        }

        var rowSeeds: [CalibrationSeedModel.RowSeed] = []
        var rowMeans: [Int: (x: Float, y: Float)] = [:]
        for rowID in 0..<3 {
            guard let samples = rowSamples[rowID], !samples.isEmpty else { continue }
            let meanX = samples.map(\.dx).reduce(0, +) / Float(samples.count)
            let meanY = samples.map(\.dy).reduce(0, +) / Float(samples.count)
            rowMeans[rowID] = (meanX, meanY)
            let confidence = min(1.0, Float(samples.count) / 20.0)
            rowSeeds.append(.init(rowID: rowID, meanOffsetX: meanX, meanOffsetY: meanY,
                                  confidence: confidence, recommendedPriorSampleCount: 32))
        }

        // Global seed
        let allDx = collectedSamples.map(\.deltaX)
        let allDy = collectedSamples.map(\.deltaY)
        let globalX = max(-4, min(4, allDx.reduce(0, +) / max(1, Float(allDx.count))))
        let globalY = max(-4, min(4, allDy.reduce(0, +) / max(1, Float(allDy.count))))
        let globalConf = min(1.0, Float(collectedSamples.count) / 40.0)
        let globalSeed = CalibrationSeedModel.GlobalSeed(shiftX: globalX, shiftY: globalY, confidence: globalConf)

        // Per-slot seeds — residual from row mean
        var slotSamples: [String: (row: Int, samples: [(dx: Float, dy: Float)])] = [:]
        for s in collectedSamples {
            var entry = slotSamples[s.intendedSlotID] ?? (s.intendedRow, [])
            entry.samples.append((s.deltaX, s.deltaY))
            slotSamples[s.intendedSlotID] = entry
        }

        var slotSeeds: [CalibrationSeedModel.SlotSeed] = []
        for (slotID, entry) in slotSamples {
            let slotMeanX = entry.samples.map(\.dx).reduce(0, +) / Float(entry.samples.count)
            let slotMeanY = entry.samples.map(\.dy).reduce(0, +) / Float(entry.samples.count)
            let rm = rowMeans[entry.row] ?? (0, 0)
            let residualX = max(-8, min(8, slotMeanX - rm.x))
            let residualY = max(-8, min(8, slotMeanY - rm.y))
            let conf = min(1.0, Float(entry.samples.count) / 5.0)
            slotSeeds.append(.init(physicalSlotID: slotID, shiftX: residualX, shiftY: residualY,
                                   confidence: conf, sampleCount: UInt16(entry.samples.count)))
        }

        return CalibrationSeedModel(
            rowSeeds: rowSeeds,
            globalSeed: globalSeed,
            slotSeeds: slotSeeds,
            metadata: .init(modelVersion: 3, createdAt: Date(), layoutID: "english_letters", orientationClass: "portrait")
        )
    }

    // MARK: - Actions

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }
}
