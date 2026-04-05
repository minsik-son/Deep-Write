import UIKit

/// 지구본 키로 키보드를 전환하는 미니 애니메이션 가이드.
/// Stage 1: 미니 키보드 + globe key 표시 → Stage 2: 탭 펄스 → Stage 3: 키보드 리스트 패널 → Stage 4: 우리 키보드 선택 → 루프
final class VerificationKeyboardSwitchAnimationView: UIView {

    // MARK: - Stage

    private enum Stage: Int {
        case keyboard = 0    // 미니 키보드 표시
        case tapGlobe        // globe key 탭 펄스
        case showList        // 키보드 선택 리스트
        case selectOurs      // 우리 키보드 선택
    }

    // MARK: - Subviews

    private let containerView = UIView()

    // Mini keyboard
    private let keyboardBg = UIView()
    private let globeKey = UIView()
    private let globeIcon = UIImageView()

    // Keyboard rows — v7: keycap grid로 대체, 프로퍼티는 buildMiniKeyboard()에서 로컬 생성

    // Tap indicator
    private let tapDot = UIView()
    private let tapRing = UIView()

    // Keyboard list panel
    private let listPanel = UIView()
    private let listLabel1 = UILabel()
    private let listLabel2 = UILabel()
    private let listHighlight = UIView()

    // MARK: - State

    private var currentStage: Stage = .keyboard
    private var loopTimer: Timer?
    private var isAnimating = false

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        buildUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildUI()
    }

    // MARK: - Public

    func startLoop() {
        guard !isAnimating else { return }
        isAnimating = true
        resetToStage(.keyboard, animated: false)
        scheduleNext()
    }

    func stopLoop() {
        isAnimating = false
        loopTimer?.invalidate()
        loopTimer = nil
    }

    // MARK: - Build UI

    private func buildUI() {
        containerView.backgroundColor = UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1.0)
        containerView.layer.cornerRadius = 14
        containerView.clipsToBounds = true
        containerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(containerView)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        buildMiniKeyboard()
        buildTapIndicator()
        buildListPanel()
    }

    private func buildMiniKeyboard() {
        keyboardBg.backgroundColor = UIColor(red: 0.82, green: 0.83, blue: 0.85, alpha: 1.0)
        keyboardBg.layer.cornerRadius = 8
        keyboardBg.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(keyboardBg)

        // v7: keycap grid — 긴 막대 대신 작은 키 여러 개
        let topRow = makeKeycapRow(count: 7)
        let midRow = makeKeycapRow(count: 6)
        let botRow = makeKeycapRow(count: 5)

        keyboardBg.addSubview(topRow)
        keyboardBg.addSubview(midRow)
        keyboardBg.addSubview(botRow)

        // Globe key
        globeKey.backgroundColor = UIColor(white: 0.72, alpha: 1.0)
        globeKey.layer.cornerRadius = 5
        globeKey.translatesAutoresizingMaskIntoConstraints = false
        keyboardBg.addSubview(globeKey)

        globeIcon.image = UIImage(systemName: "globe")
        globeIcon.tintColor = .white
        globeIcon.contentMode = .scaleAspectFit
        globeIcon.translatesAutoresizingMaskIntoConstraints = false
        globeKey.addSubview(globeIcon)

        NSLayoutConstraint.activate([
            keyboardBg.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            keyboardBg.centerYAnchor.constraint(equalTo: containerView.centerYAnchor, constant: 16),
            keyboardBg.widthAnchor.constraint(equalTo: containerView.widthAnchor, multiplier: 0.8),
            keyboardBg.heightAnchor.constraint(equalToConstant: 80),

            topRow.topAnchor.constraint(equalTo: keyboardBg.topAnchor, constant: 6),
            topRow.leadingAnchor.constraint(equalTo: keyboardBg.leadingAnchor, constant: 6),
            topRow.trailingAnchor.constraint(equalTo: keyboardBg.trailingAnchor, constant: -6),
            topRow.heightAnchor.constraint(equalToConstant: 12),

            midRow.topAnchor.constraint(equalTo: topRow.bottomAnchor, constant: 4),
            midRow.leadingAnchor.constraint(equalTo: keyboardBg.leadingAnchor, constant: 12),
            midRow.trailingAnchor.constraint(equalTo: keyboardBg.trailingAnchor, constant: -12),
            midRow.heightAnchor.constraint(equalToConstant: 12),

            botRow.topAnchor.constraint(equalTo: midRow.bottomAnchor, constant: 4),
            botRow.leadingAnchor.constraint(equalTo: keyboardBg.leadingAnchor, constant: 18),
            botRow.trailingAnchor.constraint(equalTo: keyboardBg.trailingAnchor, constant: -18),
            botRow.heightAnchor.constraint(equalToConstant: 12),

            globeKey.bottomAnchor.constraint(equalTo: keyboardBg.bottomAnchor, constant: -6),
            globeKey.leadingAnchor.constraint(equalTo: keyboardBg.leadingAnchor, constant: 8),
            globeKey.widthAnchor.constraint(equalToConstant: 28),
            globeKey.heightAnchor.constraint(equalToConstant: 16),

            globeIcon.centerXAnchor.constraint(equalTo: globeKey.centerXAnchor),
            globeIcon.centerYAnchor.constraint(equalTo: globeKey.centerYAnchor),
            globeIcon.widthAnchor.constraint(equalToConstant: 12),
            globeIcon.heightAnchor.constraint(equalToConstant: 12),
        ])
    }

    private func makeKeycapRow(count: Int) -> UIStackView {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 3
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        for _ in 0..<count {
            let key = UIView()
            key.backgroundColor = .white
            key.layer.cornerRadius = 3
            stack.addArrangedSubview(key)
        }
        return stack
    }

    private func buildTapIndicator() {
        tapDot.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.85)
        tapDot.layer.cornerRadius = 5
        tapDot.alpha = 0
        tapDot.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(tapDot)

        tapRing.backgroundColor = .clear
        tapRing.layer.borderColor = UIColor.systemBlue.withAlphaComponent(0.4).cgColor
        tapRing.layer.borderWidth = 1.5
        tapRing.layer.cornerRadius = 13
        tapRing.alpha = 0
        tapRing.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(tapRing)

        NSLayoutConstraint.activate([
            tapDot.widthAnchor.constraint(equalToConstant: 10),
            tapDot.heightAnchor.constraint(equalToConstant: 10),
            tapRing.widthAnchor.constraint(equalToConstant: 26),
            tapRing.heightAnchor.constraint(equalToConstant: 26),
        ])
    }

    private func buildListPanel() {
        listPanel.backgroundColor = UIColor(white: 0.97, alpha: 1.0)
        listPanel.layer.cornerRadius = 8
        listPanel.layer.shadowColor = UIColor.black.cgColor
        listPanel.layer.shadowOpacity = 0.12
        listPanel.layer.shadowOffset = CGSize(width: 0, height: 2)
        listPanel.layer.shadowRadius = 6
        listPanel.alpha = 0
        listPanel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(listPanel)

        listLabel1.text = "English"
        listLabel1.font = .systemFont(ofSize: 11)
        listLabel1.textColor = .label
        listLabel1.translatesAutoresizingMaskIntoConstraints = false

        listLabel2.text = "Translator KB"
        listLabel2.font = .systemFont(ofSize: 11, weight: .medium)
        listLabel2.textColor = .systemBlue
        listLabel2.translatesAutoresizingMaskIntoConstraints = false

        listHighlight.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.1)
        listHighlight.layer.cornerRadius = 4
        listHighlight.alpha = 0
        listHighlight.translatesAutoresizingMaskIntoConstraints = false

        let sep = UIView()
        sep.backgroundColor = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false

        listPanel.addSubview(listHighlight)
        listPanel.addSubview(listLabel1)
        listPanel.addSubview(sep)
        listPanel.addSubview(listLabel2)

        NSLayoutConstraint.activate([
            // v3: globeKey 바로 위에서 뜨도록 재배치
            listPanel.bottomAnchor.constraint(equalTo: globeKey.topAnchor, constant: -8),
            listPanel.leadingAnchor.constraint(equalTo: globeKey.leadingAnchor, constant: -2),
            listPanel.widthAnchor.constraint(equalToConstant: 120),

            listLabel1.topAnchor.constraint(equalTo: listPanel.topAnchor, constant: 8),
            listLabel1.leadingAnchor.constraint(equalTo: listPanel.leadingAnchor, constant: 10),
            listLabel1.trailingAnchor.constraint(equalTo: listPanel.trailingAnchor, constant: -10),

            sep.topAnchor.constraint(equalTo: listLabel1.bottomAnchor, constant: 6),
            sep.leadingAnchor.constraint(equalTo: listPanel.leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: listPanel.trailingAnchor),
            sep.heightAnchor.constraint(equalToConstant: 0.5),

            listLabel2.topAnchor.constraint(equalTo: sep.bottomAnchor, constant: 6),
            listLabel2.leadingAnchor.constraint(equalTo: listPanel.leadingAnchor, constant: 10),
            listLabel2.trailingAnchor.constraint(equalTo: listPanel.trailingAnchor, constant: -10),
            listLabel2.bottomAnchor.constraint(equalTo: listPanel.bottomAnchor, constant: -8),

            listHighlight.topAnchor.constraint(equalTo: sep.bottomAnchor, constant: 2),
            listHighlight.leadingAnchor.constraint(equalTo: listPanel.leadingAnchor, constant: 4),
            listHighlight.trailingAnchor.constraint(equalTo: listPanel.trailingAnchor, constant: -4),
            listHighlight.bottomAnchor.constraint(equalTo: listPanel.bottomAnchor, constant: -4),
        ])
    }

    // MARK: - Animation

    private func scheduleNext() {
        guard isAnimating else { return }
        let delay: TimeInterval
        switch currentStage {
        case .keyboard:   delay = 1.0
        case .tapGlobe:   delay = 0.8
        case .showList:   delay = 0.8
        case .selectOurs: delay = 1.2
        }
        loopTimer?.invalidate()
        loopTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.advance()
        }
    }

    private func advance() {
        guard isAnimating else { return }
        let next: Stage
        switch currentStage {
        case .keyboard:   next = .tapGlobe
        case .tapGlobe:   next = .showList
        case .showList:   next = .selectOurs
        case .selectOurs: next = .keyboard
        }
        resetToStage(next, animated: true)
        scheduleNext()
    }

    private func resetToStage(_ stage: Stage, animated: Bool) {
        currentStage = stage
        let dur: TimeInterval = animated ? 0.3 : 0.0

        UIView.animate(withDuration: dur, delay: 0, options: .curveEaseInOut) {
            switch stage {
            case .keyboard:
                self.tapDot.alpha = 0
                self.tapRing.alpha = 0
                self.listPanel.alpha = 0
                self.listHighlight.alpha = 0

            case .tapGlobe:
                self.listPanel.alpha = 0
                self.listHighlight.alpha = 0

            case .showList:
                self.tapDot.alpha = 0
                self.tapRing.alpha = 0
                self.listPanel.alpha = 1
                self.listHighlight.alpha = 0

            case .selectOurs:
                self.listHighlight.alpha = 1
            }
        } completion: { _ in
            guard self.isAnimating else { return }
            if stage == .tapGlobe {
                self.showGlobeTapPulse()
            }
        }
    }

    private func showGlobeTapPulse() {
        let center = globeKey.superview?.convert(globeKey.center, to: containerView) ?? .zero
        tapDot.center = center
        tapRing.center = center

        tapDot.alpha = 0
        tapDot.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
        tapRing.alpha = 0
        tapRing.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)

        UIView.animate(withDuration: 0.2) {
            self.tapDot.alpha = 1
            self.tapDot.transform = .identity
        }
        UIView.animate(withDuration: 0.4, delay: 0.1, options: .curveEaseOut) {
            self.tapRing.alpha = 1
            self.tapRing.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
        }
        UIView.animate(withDuration: 0.2, delay: 0.5) {
            self.tapDot.alpha = 0
            self.tapRing.alpha = 0
        }
    }
}
