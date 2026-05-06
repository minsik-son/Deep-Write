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
    private var isFinishingCalibration = false

    /// Safe accessor — force-index 대신 bounds check
    private var currentWord: String? {
        guard englishWords.indices.contains(currentWordIndex) else { return nil }
        return englishWords[currentWordIndex]
    }

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
    private var mirrorHeightConstraint: NSLayoutConstraint?

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

        let heightConstraint = mirrorView.heightAnchor.constraint(equalToConstant: mirrorView.preferredMirrorHeight)
        self.mirrorHeightConstraint = heightConstraint

        NSLayoutConstraint.activate([
            mirrorView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mirrorView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mirrorView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            heightConstraint,

            progressLabel.bottomAnchor.constraint(equalTo: mirrorView.topAnchor, constant: -8),
            progressLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            wordLabel.bottomAnchor.constraint(equalTo: progressLabel.topAnchor, constant: -4),
            wordLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            instructionLabel.bottomAnchor.constraint(equalTo: wordLabel.topAnchor, constant: -16),
            instructionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            instructionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
        ])

        mirrorView.onPreferredHeightChanged = { [weak self] newHeight in
            guard let self = self else { return }
            self.mirrorHeightConstraint?.constant = newHeight
            self.view.layoutIfNeeded()
        }

        bindMirrorCallbacks()
    }

    private func bindMirrorCallbacks() {
        mirrorView.onRawTouch = { [weak self] raw in
            self?.handleRawTouch(raw)
        }
    }

    private func startCalibration() {
        isFinishingCalibration = false
        mirrorView.isUserInteractionEnabled = true
        bindMirrorCallbacks()

        currentWordIndex = 0
        currentCharIndex = 0
        collectedSamples = []
        consecutiveRejectCount = 0
        showNextWord()
    }

    // MARK: - Flow

    private func showNextWord() {
        guard !isFinishingCalibration else { return }
        guard currentWordIndex < englishWords.count else {
            finishCalibration()
            return
        }
        currentCharIndex = 0
        consecutiveRejectCount = 0
        updateDisplay()
    }

    private func updateDisplay() {
        guard !isFinishingCalibration,
              let word = currentWord else {
            return
        }

        let visibleIndex = min(currentWordIndex + 1, englishWords.count)
        progressLabel.text = "\(visibleIndex) / \(englishWords.count)"

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
        guard !isFinishingCalibration else { return }

        if raw.isBackspace {
            handleBackspace()
            return
        }

        guard let word = currentWord,
              currentCharIndex < word.count else { return }

        let intendedChar = String(word[word.index(word.startIndex, offsetBy: currentCharIndex)]).lowercased()
        let intendedCenter = findIntendedCenter(for: intendedChar)
        guard let center = intendedCenter else { return }

        let dx = Float(raw.pointInKeyboard.x - center.point.x)
        let dy = Float(raw.pointInKeyboard.y - center.point.y)

        let maxDist = center.keyWidth * 1.5
        if max(abs(CGFloat(dx)), abs(CGFloat(dy))) > maxDist {
            consecutiveRejectCount += 1
            if consecutiveRejectCount >= 3 {
                consecutiveRejectCount = 0
                currentCharIndex += 1
                if advanceIfWordComplete(completedWordLength: word.count) {
                    return
                }
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

        currentCharIndex += 1
        if advanceIfWordComplete(completedWordLength: word.count) {
            return
        }
        updateDisplay()
    }

    private func handleBackspace() {
        guard !isFinishingCalibration,
              currentWord != nil,
              currentCharIndex > 0 else { return }
        currentCharIndex -= 1
        if !collectedSamples.isEmpty {
            collectedSamples.removeLast()
        }
        consecutiveRejectCount = 0
        updateDisplay()
    }

    /// Returns true if calibration finished (caller must return immediately)
    @discardableResult
    private func advanceIfWordComplete(completedWordLength: Int) -> Bool {
        guard currentCharIndex >= completedWordLength else { return false }

        currentWordIndex += 1
        if currentWordIndex >= englishWords.count {
            finishCalibration()
            return true
        }

        currentCharIndex = 0
        consecutiveRejectCount = 0
        return false
    }

    // MARK: - Intended Key Lookup (delegated to mirror frame)

    private func findIntendedCenter(for char: String) -> CalibrationIntendedKeyInfo? {
        return mirrorView.intendedKeyInfo(for: char)
    }

    // MARK: - Finish

    private func finishCalibration() {
        guard !isFinishingCalibration else { return }
        isFinishingCalibration = true

        mirrorView.onRawTouch = nil
        mirrorView.isUserInteractionEnabled = false

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
        guard presentedViewController == nil else { return }
        present(alert, animated: true)
    }

    // MARK: - Seed Generation

    private func generateSeedModel() -> CalibrationSeedModel {
        let approxKeyWidth: Float = Float((mirrorView.bounds.width - 6 - 54) / 10)

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

        let allDx = collectedSamples.map(\.deltaX)
        let allDy = collectedSamples.map(\.deltaY)
        let globalX = max(-4, min(4, allDx.reduce(0, +) / max(1, Float(allDx.count))))
        let globalY = max(-4, min(4, allDy.reduce(0, +) / max(1, Float(allDy.count))))
        let globalConf = min(1.0, Float(collectedSamples.count) / 40.0)
        let globalSeed = CalibrationSeedModel.GlobalSeed(shiftX: globalX, shiftY: globalY, confidence: globalConf)

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
        isFinishingCalibration = true
        mirrorView.onRawTouch = nil
        mirrorView.isUserInteractionEnabled = false
        dismiss(animated: true)
    }
}
