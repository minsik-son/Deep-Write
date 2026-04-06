import UIKit

/// Paste Guide 전용 — iPhone Settings UI를 정밀하게 재현한 애니메이션 가이드.
/// Root → Paste from Other Apps 탭 → Detail(Ask→Allow) → Root 반영 → 루프
final class PasteGuideSettingsAnimationView: UIView {

    // MARK: - Stage

    private enum Stage: Int {
        case root = 0        // root screen, trailing "Ask"
        case tapPaste        // tap indicator on Paste row
        case detail          // detail screen, Ask checked
        case tapAllow        // tap indicator on Allow
        case allowChecked    // Allow checked
        case rootReflected   // root screen, trailing "Allow"
    }

    // MARK: - Constants

    private let settingsBg = UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1.0)
    private let rowHeight: CGFloat = 32
    private let fontSize: CGFloat = 11
    private let sectionFontSize: CGFloat = 9
    private let cardInset: CGFloat = 10
    private let cardRadius: CGFloat = 10

    // MARK: - Subviews

    private let containerView = UIView()
    private let navBar = UIView()
    private let navTitle = UILabel()
    private let backChevron = UIImageView()
    private let backLabel = UILabel()

    // Root screen
    private let rootContent = UIView()
    private let sectionHeader1 = UILabel()
    private let rootCard1 = UIView()
    private let pasteRow = UIView()
    private let pasteValueLabel = UILabel()
    // v2: language section 제거됨

    // Detail screen
    private let detailContent = UIView()
    private let detailCard = UIView()
    private let askRow = UIView()
    private let denyRow = UIView()
    private let allowRow = UIView()
    private let askCheck = UIImageView()
    private let allowCheck = UIImageView()

    // Tap indicator
    private let tapDot = UIView()
    private let tapRing = UIView()

    // MARK: - State

    private var currentStage: Stage = .root
    private var loopTimer: Timer?
    private var isAnimating = false

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        buildUI()
        applyLocalizedText()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildUI()
        applyLocalizedText()
    }

    // MARK: - Public

    func startLoop() {
        guard !isAnimating else { return }
        isAnimating = true
        resetToStage(.root, animated: false)
        scheduleNext()
    }

    func stopLoop() {
        isAnimating = false
        loopTimer?.invalidate()
        loopTimer = nil
    }

    func applyLocalizedText() {
        navTitle.text = L("paste_guide.anim.nav.root")
        sectionHeader1.text = L("paste_guide.anim.section.access")
        pasteValueLabel.text = L("paste_guide.anim.value.ask")
    }

    // MARK: - Build UI

    private func buildUI() {
        containerView.backgroundColor = settingsBg
        containerView.layer.cornerRadius = 12
        containerView.clipsToBounds = true
        containerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(containerView)
        pin(containerView, to: self)

        buildNavBar()
        buildRootScreen()
        buildDetailScreen()
        buildTapIndicator()
    }

    // MARK: Nav

    private func buildNavBar() {
        navBar.backgroundColor = UIColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 1.0)
        navBar.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(navBar)

        navTitle.font = .systemFont(ofSize: 11, weight: .semibold)
        navTitle.textAlignment = .center
        navTitle.translatesAutoresizingMaskIntoConstraints = false
        navBar.addSubview(navTitle)

        backChevron.image = UIImage(systemName: "chevron.left")
        backChevron.tintColor = .systemBlue
        backChevron.contentMode = .scaleAspectFit
        backChevron.alpha = 0
        backChevron.translatesAutoresizingMaskIntoConstraints = false
        navBar.addSubview(backChevron)

        backLabel.font = .systemFont(ofSize: 9)
        backLabel.textColor = .systemBlue
        backLabel.alpha = 0
        backLabel.translatesAutoresizingMaskIntoConstraints = false
        navBar.addSubview(backLabel)

        let sep = makeSep()
        navBar.addSubview(sep)

        NSLayoutConstraint.activate([
            navBar.topAnchor.constraint(equalTo: containerView.topAnchor),
            navBar.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            navBar.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            navBar.heightAnchor.constraint(equalToConstant: 28),
            navTitle.centerXAnchor.constraint(equalTo: navBar.centerXAnchor),
            navTitle.centerYAnchor.constraint(equalTo: navBar.centerYAnchor),
            backChevron.leadingAnchor.constraint(equalTo: navBar.leadingAnchor, constant: 6),
            backChevron.centerYAnchor.constraint(equalTo: navBar.centerYAnchor),
            backChevron.widthAnchor.constraint(equalToConstant: 8),
            backChevron.heightAnchor.constraint(equalToConstant: 12),
            backLabel.leadingAnchor.constraint(equalTo: backChevron.trailingAnchor, constant: 1),
            backLabel.centerYAnchor.constraint(equalTo: navBar.centerYAnchor),
            sep.bottomAnchor.constraint(equalTo: navBar.bottomAnchor),
            sep.leadingAnchor.constraint(equalTo: navBar.leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: navBar.trailingAnchor),
            sep.heightAnchor.constraint(equalToConstant: 0.5),
        ])
    }

    // MARK: Root Screen

    private func buildRootScreen() {
        rootContent.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(rootContent)

        configureSectionLabel(sectionHeader1)
        rootContent.addSubview(sectionHeader1)

        // Card 1: AI, Search, Cellular, Keyboards
        rootCard1.backgroundColor = .white
        rootCard1.layer.cornerRadius = cardRadius
        rootCard1.translatesAutoresizingMaskIntoConstraints = false
        rootContent.addSubview(rootCard1)

        let aiIcon = makeBadge("sparkles", colors: [
            UIColor(red: 0.95, green: 0.45, blue: 0.55, alpha: 1).cgColor,
            UIColor(red: 0.75, green: 0.40, blue: 0.85, alpha: 1).cgColor,
            UIColor(red: 0.40, green: 0.55, blue: 0.95, alpha: 1).cgColor,
        ])
        let searchIcon = makeBadge("magnifyingglass", bg: UIColor(white: 0.55, alpha: 1))
        let cellularIcon = makeBadge("antenna.radiowaves.left.and.right", bg: .systemGreen)
        let kbIcon = makeBadge("keyboard", bg: UIColor(white: 0.55, alpha: 1))

        let aiLabel = makeLabel(L("paste_guide.anim.row.apple_intelligence"))
        let searchLabel = makeLabel(L("paste_guide.anim.row.search"))
        let cellularLabel = makeLabel(L("paste_guide.anim.row.cellular"))
        let kbLabel = makeLabel(L("paste_guide.anim.row.keyboards"))

        let cellToggle = MiniToggle()
        cellToggle.setOn(true, animated: false)

        let rows1 = makeRows([
            (aiIcon, aiLabel, makeChev()),
            (searchIcon, searchLabel, makeChev()),
            (cellularIcon, cellularLabel, cellToggle),
            (kbIcon, kbLabel, makeChev()),
        ])
        rootCard1.addSubview(rows1)
        pinStack(rows1, in: rootCard1)

        // Paste row (standalone card)
        let pasteCard = UIView()
        pasteCard.backgroundColor = .white
        pasteCard.layer.cornerRadius = cardRadius
        pasteCard.translatesAutoresizingMaskIntoConstraints = false
        rootContent.addSubview(pasteCard)

        pasteRow.translatesAutoresizingMaskIntoConstraints = false
        let pasteLabel = makeLabel(L("paste_guide.anim.row.paste_from_other_apps"))
        pasteValueLabel.font = .systemFont(ofSize: fontSize - 1)
        pasteValueLabel.textColor = .secondaryLabel
        pasteValueLabel.translatesAutoresizingMaskIntoConstraints = false
        let pasteAccessory = UIStackView(arrangedSubviews: [pasteValueLabel, makeChev()])
        pasteAccessory.spacing = 3
        pasteAccessory.alignment = .center
        pasteAccessory.translatesAutoresizingMaskIntoConstraints = false
        configureSimpleRow(pasteRow, label: pasteLabel, accessory: pasteAccessory)
        pasteCard.addSubview(pasteRow)
        pinStack(pasteRow, in: pasteCard)

        // v2: language section 제거 — rootCard1 + pasteCard만 유지

        NSLayoutConstraint.activate([
            rootContent.topAnchor.constraint(equalTo: navBar.bottomAnchor),
            rootContent.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            rootContent.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            rootContent.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

            sectionHeader1.topAnchor.constraint(equalTo: rootContent.topAnchor, constant: 12),
            sectionHeader1.leadingAnchor.constraint(equalTo: rootContent.leadingAnchor, constant: cardInset + 8),

            rootCard1.topAnchor.constraint(equalTo: sectionHeader1.bottomAnchor, constant: 6),
            rootCard1.leadingAnchor.constraint(equalTo: rootContent.leadingAnchor, constant: cardInset),
            rootCard1.trailingAnchor.constraint(equalTo: rootContent.trailingAnchor, constant: -cardInset),

            pasteCard.topAnchor.constraint(equalTo: rootCard1.bottomAnchor, constant: 14),
            pasteCard.leadingAnchor.constraint(equalTo: rootContent.leadingAnchor, constant: cardInset),
            pasteCard.trailingAnchor.constraint(equalTo: rootContent.trailingAnchor, constant: -cardInset),
        ])
    }

    // MARK: Detail Screen

    private func buildDetailScreen() {
        detailContent.alpha = 0
        detailContent.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(detailContent)

        detailCard.backgroundColor = .white
        detailCard.layer.cornerRadius = cardRadius
        detailCard.translatesAutoresizingMaskIntoConstraints = false
        detailContent.addSubview(detailCard)

        let askLabel = makeLabel(L("paste_guide.anim.option.ask"))
        let denyLabel = makeLabel(L("paste_guide.anim.option.deny"))
        let allowLabel = makeLabel(L("paste_guide.anim.option.allow"))

        askCheck.image = UIImage(systemName: "checkmark")
        askCheck.tintColor = .systemBlue
        askCheck.contentMode = .scaleAspectFit
        askCheck.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([askCheck.widthAnchor.constraint(equalToConstant: 12), askCheck.heightAnchor.constraint(equalToConstant: 12)])

        allowCheck.image = UIImage(systemName: "checkmark")
        allowCheck.tintColor = .systemBlue
        allowCheck.contentMode = .scaleAspectFit
        allowCheck.alpha = 0
        allowCheck.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([allowCheck.widthAnchor.constraint(equalToConstant: 12), allowCheck.heightAnchor.constraint(equalToConstant: 12)])

        askRow.translatesAutoresizingMaskIntoConstraints = false
        denyRow.translatesAutoresizingMaskIntoConstraints = false
        allowRow.translatesAutoresizingMaskIntoConstraints = false

        configureSimpleRow(askRow, label: askLabel, accessory: askCheck)
        configureSimpleRow(denyRow, label: denyLabel, accessory: UIView())
        configureSimpleRow(allowRow, label: allowLabel, accessory: allowCheck)

        let detailStack = makeCardStack(rows: [askRow, denyRow, allowRow])
        detailCard.addSubview(detailStack)
        pinStack(detailStack, in: detailCard)

        NSLayoutConstraint.activate([
            detailContent.topAnchor.constraint(equalTo: navBar.bottomAnchor),
            detailContent.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            detailContent.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            detailContent.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

            detailCard.topAnchor.constraint(equalTo: detailContent.topAnchor, constant: 10),
            detailCard.leadingAnchor.constraint(equalTo: detailContent.leadingAnchor, constant: cardInset),
            detailCard.trailingAnchor.constraint(equalTo: detailContent.trailingAnchor, constant: -cardInset),
        ])
    }

    // MARK: Tap Indicator

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

    private func showPulse(at target: UIView) {
        let center = target.superview?.convert(target.center, to: containerView) ?? .zero
        tapDot.center = center
        tapRing.center = center
        tapDot.alpha = 0; tapDot.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
        tapRing.alpha = 0; tapRing.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        UIView.animate(withDuration: 0.2) { self.tapDot.alpha = 1; self.tapDot.transform = .identity }
        UIView.animate(withDuration: 0.4, delay: 0.1, options: .curveEaseOut) {
            self.tapRing.alpha = 1; self.tapRing.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
        }
        UIView.animate(withDuration: 0.2, delay: 0.5) { self.tapDot.alpha = 0; self.tapRing.alpha = 0 }
    }

    private func hidePulse() { tapDot.alpha = 0; tapRing.alpha = 0 }

    // MARK: - Helpers

    private func makeSep() -> UIView {
        let v = UIView(); v.backgroundColor = UIColor(white: 0.88, alpha: 1); v.translatesAutoresizingMaskIntoConstraints = false; return v
    }

    private func configureSectionLabel(_ l: UILabel) {
        l.font = .systemFont(ofSize: sectionFontSize); l.textColor = .secondaryLabel; l.translatesAutoresizingMaskIntoConstraints = false
    }

    private func makeLabel(_ text: String) -> UILabel {
        let l = UILabel(); l.text = text; l.font = .systemFont(ofSize: fontSize); l.translatesAutoresizingMaskIntoConstraints = false; return l
    }

    private func makeChev() -> UIImageView {
        let iv = UIImageView(image: UIImage(systemName: "chevron.right"))
        iv.tintColor = UIColor(white: 0.78, alpha: 1); iv.contentMode = .scaleAspectFit; iv.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([iv.widthAnchor.constraint(equalToConstant: 6), iv.heightAnchor.constraint(equalToConstant: 10)])
        return iv
    }

    private func makeBadge(_ symbol: String, bg: UIColor) -> UIView {
        let v = UIView(); v.backgroundColor = bg; v.layer.cornerRadius = 5; v.translatesAutoresizingMaskIntoConstraints = false
        let iv = UIImageView(image: UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 9, weight: .medium)))
        iv.tintColor = .white; iv.contentMode = .scaleAspectFit; iv.translatesAutoresizingMaskIntoConstraints = false; v.addSubview(iv)
        NSLayoutConstraint.activate([v.widthAnchor.constraint(equalToConstant: 18), v.heightAnchor.constraint(equalToConstant: 18),
                                     iv.centerXAnchor.constraint(equalTo: v.centerXAnchor), iv.centerYAnchor.constraint(equalTo: v.centerYAnchor)])
        return v
    }

    private func makeBadge(_ symbol: String, colors: [CGColor]) -> UIView {
        let v = UIView(); v.layer.cornerRadius = 5; v.clipsToBounds = true; v.translatesAutoresizingMaskIntoConstraints = false
        let g = CAGradientLayer(); g.colors = colors; g.startPoint = .zero; g.endPoint = CGPoint(x: 1, y: 1); g.frame = CGRect(x: 0, y: 0, width: 18, height: 18)
        v.layer.insertSublayer(g, at: 0)
        let iv = UIImageView(image: UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 9, weight: .medium)))
        iv.tintColor = .white; iv.contentMode = .scaleAspectFit; iv.translatesAutoresizingMaskIntoConstraints = false; v.addSubview(iv)
        NSLayoutConstraint.activate([v.widthAnchor.constraint(equalToConstant: 18), v.heightAnchor.constraint(equalToConstant: 18),
                                     iv.centerXAnchor.constraint(equalTo: v.centerXAnchor), iv.centerYAnchor.constraint(equalTo: v.centerYAnchor)])
        return v
    }

    private func configureIconRow(_ row: UIView, icon: UIView, label: UILabel, accessory: UIView) {
        row.addSubview(icon); row.addSubview(label); row.addSubview(accessory)
        accessory.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: rowHeight),
            icon.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 2),
            icon.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 5),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            accessory.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -8),
            accessory.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])
    }

    private func configureSimpleRow(_ row: UIView, label: UILabel, accessory: UIView) {
        row.addSubview(label); row.addSubview(accessory)
        accessory.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: rowHeight),
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 10),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            accessory.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -8),
            accessory.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])
    }

    private func makeRows(_ items: [(UIView, UILabel, UIView)]) -> UIStackView {
        let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 0; stack.translatesAutoresizingMaskIntoConstraints = false
        for (i, item) in items.enumerated() {
            let row = UIView(); row.translatesAutoresizingMaskIntoConstraints = false
            configureIconRow(row, icon: item.0, label: item.1, accessory: item.2)
            stack.addArrangedSubview(row)
            if i < items.count - 1 {
                let s = makeSep(); stack.addArrangedSubview(s)
                s.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
            }
        }
        return stack
    }

    private func makeCardStack(rows: [UIView]) -> UIStackView {
        let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 0; stack.translatesAutoresizingMaskIntoConstraints = false
        for (i, row) in rows.enumerated() {
            stack.addArrangedSubview(row)
            if i < rows.count - 1 {
                let s = makeSep(); stack.addArrangedSubview(s)
                s.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
            }
        }
        return stack
    }

    private func pinStack(_ child: UIView, in parent: UIView) {
        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: parent.topAnchor),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
        ])
    }

    private func pin(_ child: UIView, to parent: UIView) {
        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: parent.topAnchor),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
        ])
    }

    // MARK: - Animation Loop

    private func scheduleNext() {
        guard isAnimating else { return }
        let delay: TimeInterval
        switch currentStage {
        case .root:          delay = 1.5
        case .tapPaste:      delay = 0.8
        case .detail:        delay = 1.2
        case .tapAllow:      delay = 0.8
        case .allowChecked:  delay = 1.0
        case .rootReflected: delay = 1.5
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
        case .root:          next = .tapPaste
        case .tapPaste:      next = .detail
        case .detail:        next = .tapAllow
        case .tapAllow:      next = .allowChecked
        case .allowChecked:  next = .rootReflected
        case .rootReflected: next = .root
        }
        resetToStage(next, animated: true)
        scheduleNext()
    }

    private func resetToStage(_ stage: Stage, animated: Bool) {
        currentStage = stage
        let dur: TimeInterval = animated ? 0.35 : 0.0
        hidePulse()

        UIView.animate(withDuration: dur, delay: 0, options: .curveEaseInOut) {
            switch stage {
            case .root:
                self.navTitle.text = L("paste_guide.anim.nav.root")
                self.backChevron.alpha = 0; self.backLabel.alpha = 0
                self.rootContent.alpha = 1; self.detailContent.alpha = 0
                self.pasteValueLabel.text = L("paste_guide.anim.value.ask")
                self.askCheck.alpha = 1; self.allowCheck.alpha = 0

            case .tapPaste:
                break

            case .detail:
                self.navTitle.text = L("paste_guide.anim.nav.detail")
                self.backChevron.alpha = 1; self.backLabel.alpha = 1
                self.rootContent.alpha = 0; self.detailContent.alpha = 1
                self.askCheck.alpha = 1; self.allowCheck.alpha = 0

            case .tapAllow:
                break

            case .allowChecked:
                self.askCheck.alpha = 0; self.allowCheck.alpha = 1

            case .rootReflected:
                self.navTitle.text = L("paste_guide.anim.nav.root")
                self.backChevron.alpha = 0; self.backLabel.alpha = 0
                self.rootContent.alpha = 1; self.detailContent.alpha = 0
                self.pasteValueLabel.text = L("paste_guide.anim.value.allow")
            }
        } completion: { _ in
            guard self.isAnimating else { return }
            switch stage {
            case .tapPaste:
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.showPulse(at: self.pasteRow) }
            case .tapAllow:
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.showPulse(at: self.allowRow) }
            default: break
            }
        }
    }
}

// MARK: - Mini Toggle (reuse)

private final class MiniToggle: UIView {
    private let track = UIView()
    private let thumb = UIView()
    private var thumbLeading: NSLayoutConstraint!

    override init(frame: CGRect) { super.init(frame: frame); setup() }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }

    private func setup() {
        track.layer.cornerRadius = 7; track.backgroundColor = UIColor(white: 0.88, alpha: 1); track.translatesAutoresizingMaskIntoConstraints = false; addSubview(track)
        thumb.backgroundColor = .white; thumb.layer.cornerRadius = 5.5; thumb.layer.shadowColor = UIColor.black.cgColor; thumb.layer.shadowOpacity = 0.15; thumb.layer.shadowOffset = CGSize(width: 0, height: 0.5); thumb.layer.shadowRadius = 0.5; thumb.translatesAutoresizingMaskIntoConstraints = false; addSubview(thumb)
        thumbLeading = thumb.leadingAnchor.constraint(equalTo: track.leadingAnchor, constant: 1)
        NSLayoutConstraint.activate([
            track.centerYAnchor.constraint(equalTo: centerYAnchor), track.leadingAnchor.constraint(equalTo: leadingAnchor),
            track.widthAnchor.constraint(equalToConstant: 26), track.heightAnchor.constraint(equalToConstant: 14),
            widthAnchor.constraint(equalToConstant: 26), heightAnchor.constraint(equalToConstant: 14),
            thumb.centerYAnchor.constraint(equalTo: track.centerYAnchor), thumb.widthAnchor.constraint(equalToConstant: 11), thumb.heightAnchor.constraint(equalToConstant: 11), thumbLeading,
        ])
    }

    func setOn(_ on: Bool, animated: Bool) {
        let action = { self.thumbLeading.constant = on ? 14 : 1; self.track.backgroundColor = on ? .systemGreen : UIColor(white: 0.88, alpha: 1); self.layoutIfNeeded() }
        animated ? UIView.animate(withDuration: 0.25, animations: action) : action()
    }
}
