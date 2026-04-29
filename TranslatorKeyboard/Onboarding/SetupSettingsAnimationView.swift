import UIKit

/// iPhone 설정 화면을 닮은 미니 애니메이션 가이드 (v2).
/// Stage 1: 앱 설정 루트 (풍부한 행) → Stage 2: 키보드 상세 → Stage 3: 얼럿 → Stage 4: 토글 ON → 루프
/// 각 탭 대상에 파란 점 + 링 펄스 표시.
final class SetupSettingsAnimationView: UIView {

    // MARK: - Stage

    private enum Stage: Int {
        case root = 0
        case keyboard
        case alert
        case done
    }

    // MARK: - Constants

    private let settingsBg = UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1.0)
    private let rowHeight: CGFloat = 28
    private let fontSize: CGFloat = 10
    private let sectionFontSize: CGFloat = 8.5
    private let cardInset: CGFloat = 8
    private let cardRadius: CGFloat = 8

    // MARK: - Subviews

    private let containerView = UIView()
    private let navBar = UIView()
    private let navTitleLabel = UILabel()
    private let backChevron = UIImageView()
    private let backLabel = UILabel()

    // Stage 1 — root
    private let rootScrollContent = UIView()
    private let sectionHeaderAccess = UILabel()
    private let rootCard1 = UIView() // main settings card
    private let sectionHeaderLang = UILabel()
    private let rootCard2 = UIView() // language card
    // root rows
    private let rowAI = UIView()
    private let rowSearch = UIView()
    private let rowCellular = UIView()
    private let cellularToggle = MiniToggleView()
    private let rowKeyboard = UIView()
    private let keyboardRowHighlight = UIView()
    private let rowLanguage = UIView()
    private let languageValueLabel = UILabel()
    // row labels
    private let labelAI = UILabel()
    private let labelSearch = UILabel()
    private let labelCellular = UILabel()
    private let labelKeyboard = UILabel()
    private let labelLanguage = UILabel()

    // Stage 2 — keyboard detail
    private let detailContent = UIView()
    private let detailCard = UIView()
    private let translatorLabel = UILabel()
    private let translatorToggle = MiniToggleView()
    private let fullAccessLabel = UILabel()
    private let fullAccessToggle = MiniToggleView()
    private let detailNote = UILabel()

    // Stage 3 — alert
    private let dimOverlay = UIView()
    private let alertBox = UIView()
    private let alertTitleLabel = UILabel()
    private let alertBodyLabel = UILabel()
    private let alertDenyBtn = UILabel()
    private let alertAllowBtn = UILabel()

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
        navTitleLabel.text = L("onboarding.setup.anim.nav.root")
        sectionHeaderAccess.text = L("onboarding.setup.anim.section.access")
        sectionHeaderLang.text = L("onboarding.setup.anim.section.language")
        labelAI.text = L("onboarding.setup.anim.row.apple_intelligence")
        labelSearch.text = L("onboarding.setup.anim.row.search")
        labelCellular.text = L("onboarding.setup.anim.row.cellular")
        labelKeyboard.text = L("onboarding.setup.anim.row.keyboard")
        labelLanguage.text = L("onboarding.setup.anim.row.language")
        languageValueLabel.text = L("onboarding.setup.anim.language.current")
        translatorLabel.text = "OneBoard"
        fullAccessLabel.text = L("onboarding.setup.anim.row.full_access")
        detailNote.text = L("onboarding.setup.anim.detail.note")
        alertTitleLabel.text = L("onboarding.setup.anim.alert.title")
        alertBodyLabel.text = L("onboarding.setup.anim.alert.body")
        alertDenyBtn.text = L("onboarding.setup.anim.alert.deny")
        alertAllowBtn.text = L("onboarding.setup.anim.alert.allow")
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
        buildAlertOverlay()
        buildTapIndicator()
    }

    // MARK: Nav Bar

    private func buildNavBar() {
        navBar.backgroundColor = UIColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 1.0)
        navBar.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(navBar)

        navTitleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        navTitleLabel.textAlignment = .center
        navTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        navBar.addSubview(navTitleLabel)

        backChevron.image = UIImage(systemName: "chevron.left")
        backChevron.tintColor = .systemBlue
        backChevron.contentMode = .scaleAspectFit
        backChevron.translatesAutoresizingMaskIntoConstraints = false
        backChevron.alpha = 0
        navBar.addSubview(backChevron)

        backLabel.font = .systemFont(ofSize: 9)
        backLabel.textColor = .systemBlue
        backLabel.alpha = 0
        backLabel.translatesAutoresizingMaskIntoConstraints = false
        navBar.addSubview(backLabel)

        let sep = makeSeparator()
        navBar.addSubview(sep)

        NSLayoutConstraint.activate([
            navBar.topAnchor.constraint(equalTo: containerView.topAnchor),
            navBar.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            navBar.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            navBar.heightAnchor.constraint(equalToConstant: 26),
            navTitleLabel.centerXAnchor.constraint(equalTo: navBar.centerXAnchor),
            navTitleLabel.centerYAnchor.constraint(equalTo: navBar.centerYAnchor),
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
        rootScrollContent.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(rootScrollContent)

        // Section header 1
        configureSectionHeader(sectionHeaderAccess)
        rootScrollContent.addSubview(sectionHeaderAccess)

        // Card 1: 4 rows
        rootCard1.backgroundColor = .white
        rootCard1.layer.cornerRadius = cardRadius
        rootCard1.translatesAutoresizingMaskIntoConstraints = false
        rootScrollContent.addSubview(rootCard1)

        let aiIcon = makeAIBadgeIcon()
        let searchIcon = makeBadgeIcon("magnifyingglass", badgeColor: UIColor(white: 0.55, alpha: 1.0))
        let cellularIcon = makeBadgeIcon("antenna.radiowaves.left.and.right", badgeColor: .systemGreen)
        let kbIcon = makeBadgeIcon("keyboard", badgeColor: UIColor(white: 0.55, alpha: 1.0))

        configureRow(rowAI, icon: aiIcon, label: labelAI, accessory: makeChevron())
        configureRow(rowSearch, icon: searchIcon, label: labelSearch, accessory: makeChevron())
        cellularToggle.setOn(true, animated: false)
        configureRow(rowCellular, icon: cellularIcon, label: labelCellular, accessory: cellularToggle)
        let kbChevron = makeChevron()
        configureRow(rowKeyboard, icon: kbIcon, label: labelKeyboard, accessory: kbChevron)

        // Highlight for keyboard row
        keyboardRowHighlight.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.08)
        keyboardRowHighlight.layer.cornerRadius = 4
        keyboardRowHighlight.alpha = 0
        keyboardRowHighlight.translatesAutoresizingMaskIntoConstraints = false
        rowKeyboard.insertSubview(keyboardRowHighlight, at: 0)

        let rows1 = [rowAI, rowSearch, rowCellular, rowKeyboard]
        let stack1 = makeCardStack(rows: rows1)
        rootCard1.addSubview(stack1)
        pinCardStack(stack1, in: rootCard1)

        // Section header 2
        configureSectionHeader(sectionHeaderLang)
        rootScrollContent.addSubview(sectionHeaderLang)

        // Card 2: language row
        rootCard2.backgroundColor = .white
        rootCard2.layer.cornerRadius = cardRadius
        rootCard2.translatesAutoresizingMaskIntoConstraints = false
        rootScrollContent.addSubview(rootCard2)

        let globeIcon = makeBadgeIcon("globe", badgeColor: .systemBlue)
        languageValueLabel.font = .systemFont(ofSize: fontSize - 1)
        languageValueLabel.textColor = .secondaryLabel
        languageValueLabel.translatesAutoresizingMaskIntoConstraints = false
        let langAccessory = UIStackView(arrangedSubviews: [languageValueLabel, makeChevron()])
        langAccessory.spacing = 3
        langAccessory.alignment = .center
        langAccessory.translatesAutoresizingMaskIntoConstraints = false
        configureRow(rowLanguage, icon: globeIcon, label: labelLanguage, accessory: langAccessory)

        let stack2 = makeCardStack(rows: [rowLanguage])
        rootCard2.addSubview(stack2)
        pinCardStack(stack2, in: rootCard2)

        NSLayoutConstraint.activate([
            rootScrollContent.topAnchor.constraint(equalTo: navBar.bottomAnchor),
            rootScrollContent.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            rootScrollContent.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            rootScrollContent.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

            sectionHeaderAccess.topAnchor.constraint(equalTo: rootScrollContent.topAnchor, constant: 6),
            sectionHeaderAccess.leadingAnchor.constraint(equalTo: rootScrollContent.leadingAnchor, constant: cardInset + 10),
            sectionHeaderAccess.trailingAnchor.constraint(equalTo: rootScrollContent.trailingAnchor, constant: -cardInset),

            rootCard1.topAnchor.constraint(equalTo: sectionHeaderAccess.bottomAnchor, constant: 4),
            rootCard1.leadingAnchor.constraint(equalTo: rootScrollContent.leadingAnchor, constant: cardInset),
            rootCard1.trailingAnchor.constraint(equalTo: rootScrollContent.trailingAnchor, constant: -cardInset),

            sectionHeaderLang.topAnchor.constraint(equalTo: rootCard1.bottomAnchor, constant: 8),
            sectionHeaderLang.leadingAnchor.constraint(equalTo: rootScrollContent.leadingAnchor, constant: cardInset + 10),
            sectionHeaderLang.trailingAnchor.constraint(equalTo: rootScrollContent.trailingAnchor, constant: -cardInset),

            rootCard2.topAnchor.constraint(equalTo: sectionHeaderLang.bottomAnchor, constant: 4),
            rootCard2.leadingAnchor.constraint(equalTo: rootScrollContent.leadingAnchor, constant: cardInset),
            rootCard2.trailingAnchor.constraint(equalTo: rootScrollContent.trailingAnchor, constant: -cardInset),

            keyboardRowHighlight.topAnchor.constraint(equalTo: rowKeyboard.topAnchor, constant: 1),
            keyboardRowHighlight.bottomAnchor.constraint(equalTo: rowKeyboard.bottomAnchor, constant: -1),
            keyboardRowHighlight.leadingAnchor.constraint(equalTo: rowKeyboard.leadingAnchor, constant: 2),
            keyboardRowHighlight.trailingAnchor.constraint(equalTo: rowKeyboard.trailingAnchor, constant: -2),
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

        // Translator KB row
        let trRow = UIView()
        trRow.translatesAutoresizingMaskIntoConstraints = false
        translatorLabel.font = .systemFont(ofSize: fontSize)
        translatorLabel.translatesAutoresizingMaskIntoConstraints = false
        translatorToggle.setOn(true, animated: false)
        translatorToggle.translatesAutoresizingMaskIntoConstraints = false
        trRow.addSubview(translatorLabel)
        trRow.addSubview(translatorToggle)

        // Full access row
        let faRow = UIView()
        faRow.translatesAutoresizingMaskIntoConstraints = false
        let faIcon = makeBadgeIcon("keyboard", badgeColor: UIColor(white: 0.55, alpha: 1.0))
        fullAccessLabel.font = .systemFont(ofSize: fontSize)
        fullAccessLabel.translatesAutoresizingMaskIntoConstraints = false
        fullAccessToggle.setOn(false, animated: false)
        fullAccessToggle.translatesAutoresizingMaskIntoConstraints = false
        faRow.addSubview(faIcon)
        faRow.addSubview(fullAccessLabel)
        faRow.addSubview(fullAccessToggle)

        let detailStack = makeCardStack(rows: [trRow, faRow])
        detailCard.addSubview(detailStack)
        pinCardStack(detailStack, in: detailCard)

        // Detail note
        detailNote.font = .systemFont(ofSize: 7.5)
        detailNote.textColor = .secondaryLabel
        detailNote.numberOfLines = 0
        detailNote.translatesAutoresizingMaskIntoConstraints = false
        detailContent.addSubview(detailNote)

        NSLayoutConstraint.activate([
            detailContent.topAnchor.constraint(equalTo: navBar.bottomAnchor),
            detailContent.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            detailContent.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            detailContent.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

            detailCard.topAnchor.constraint(equalTo: detailContent.topAnchor, constant: 10),
            detailCard.leadingAnchor.constraint(equalTo: detailContent.leadingAnchor, constant: cardInset),
            detailCard.trailingAnchor.constraint(equalTo: detailContent.trailingAnchor, constant: -cardInset),

            trRow.heightAnchor.constraint(equalToConstant: rowHeight),
            translatorLabel.leadingAnchor.constraint(equalTo: trRow.leadingAnchor, constant: 10),
            translatorLabel.centerYAnchor.constraint(equalTo: trRow.centerYAnchor),
            translatorToggle.trailingAnchor.constraint(equalTo: trRow.trailingAnchor, constant: -8),
            translatorToggle.centerYAnchor.constraint(equalTo: trRow.centerYAnchor),

            faRow.heightAnchor.constraint(equalToConstant: rowHeight),
            faIcon.leadingAnchor.constraint(equalTo: faRow.leadingAnchor, constant: 8),
            faIcon.centerYAnchor.constraint(equalTo: faRow.centerYAnchor),
            fullAccessLabel.leadingAnchor.constraint(equalTo: faIcon.trailingAnchor, constant: 6),
            fullAccessLabel.centerYAnchor.constraint(equalTo: faRow.centerYAnchor),
            fullAccessToggle.trailingAnchor.constraint(equalTo: faRow.trailingAnchor, constant: -8),
            fullAccessToggle.centerYAnchor.constraint(equalTo: faRow.centerYAnchor),

            detailNote.topAnchor.constraint(equalTo: detailCard.bottomAnchor, constant: 6),
            detailNote.leadingAnchor.constraint(equalTo: detailContent.leadingAnchor, constant: cardInset + 10),
            detailNote.trailingAnchor.constraint(equalTo: detailContent.trailingAnchor, constant: -cardInset - 4),
        ])
    }

    // MARK: Alert

    private func buildAlertOverlay() {
        dimOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        dimOverlay.alpha = 0
        dimOverlay.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(dimOverlay)
        pin(dimOverlay, to: containerView)

        alertBox.backgroundColor = UIColor(white: 0.97, alpha: 1.0)
        alertBox.layer.cornerRadius = 10
        alertBox.alpha = 0
        alertBox.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
        alertBox.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(alertBox)

        alertTitleLabel.font = .systemFont(ofSize: 9.5, weight: .bold)
        alertTitleLabel.textAlignment = .center
        alertTitleLabel.numberOfLines = 0
        alertTitleLabel.translatesAutoresizingMaskIntoConstraints = false

        alertBodyLabel.font = .systemFont(ofSize: 8)
        alertBodyLabel.textColor = .secondaryLabel
        alertBodyLabel.textAlignment = .center
        alertBodyLabel.numberOfLines = 0
        alertBodyLabel.translatesAutoresizingMaskIntoConstraints = false

        let btnSep = makeSeparator()
        let vSep = makeSeparator()

        alertDenyBtn.font = .systemFont(ofSize: 9.5)
        alertDenyBtn.textColor = .systemBlue
        alertDenyBtn.textAlignment = .center
        alertDenyBtn.translatesAutoresizingMaskIntoConstraints = false

        alertAllowBtn.font = .systemFont(ofSize: 9.5, weight: .semibold)
        alertAllowBtn.textColor = .systemBlue
        alertAllowBtn.textAlignment = .center
        alertAllowBtn.translatesAutoresizingMaskIntoConstraints = false

        [alertTitleLabel, alertBodyLabel, btnSep, alertDenyBtn, alertAllowBtn, vSep].forEach { alertBox.addSubview($0) }

        NSLayoutConstraint.activate([
            alertBox.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            alertBox.centerYAnchor.constraint(equalTo: containerView.centerYAnchor, constant: 8),
            alertBox.widthAnchor.constraint(equalTo: containerView.widthAnchor, multiplier: 0.72),

            alertTitleLabel.topAnchor.constraint(equalTo: alertBox.topAnchor, constant: 10),
            alertTitleLabel.leadingAnchor.constraint(equalTo: alertBox.leadingAnchor, constant: 10),
            alertTitleLabel.trailingAnchor.constraint(equalTo: alertBox.trailingAnchor, constant: -10),

            alertBodyLabel.topAnchor.constraint(equalTo: alertTitleLabel.bottomAnchor, constant: 4),
            alertBodyLabel.leadingAnchor.constraint(equalTo: alertBox.leadingAnchor, constant: 10),
            alertBodyLabel.trailingAnchor.constraint(equalTo: alertBox.trailingAnchor, constant: -10),

            btnSep.topAnchor.constraint(equalTo: alertBodyLabel.bottomAnchor, constant: 10),
            btnSep.leadingAnchor.constraint(equalTo: alertBox.leadingAnchor),
            btnSep.trailingAnchor.constraint(equalTo: alertBox.trailingAnchor),
            btnSep.heightAnchor.constraint(equalToConstant: 0.5),

            alertDenyBtn.topAnchor.constraint(equalTo: btnSep.bottomAnchor),
            alertDenyBtn.leadingAnchor.constraint(equalTo: alertBox.leadingAnchor),
            alertDenyBtn.widthAnchor.constraint(equalTo: alertBox.widthAnchor, multiplier: 0.5),
            alertDenyBtn.heightAnchor.constraint(equalToConstant: 28),
            alertDenyBtn.bottomAnchor.constraint(equalTo: alertBox.bottomAnchor),

            alertAllowBtn.topAnchor.constraint(equalTo: btnSep.bottomAnchor),
            alertAllowBtn.trailingAnchor.constraint(equalTo: alertBox.trailingAnchor),
            alertAllowBtn.widthAnchor.constraint(equalTo: alertBox.widthAnchor, multiplier: 0.5),
            alertAllowBtn.heightAnchor.constraint(equalToConstant: 28),

            vSep.topAnchor.constraint(equalTo: btnSep.bottomAnchor),
            vSep.bottomAnchor.constraint(equalTo: alertBox.bottomAnchor),
            vSep.centerXAnchor.constraint(equalTo: alertBox.centerXAnchor),
            vSep.widthAnchor.constraint(equalToConstant: 0.5),
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

    private func showTapPulse(at target: UIView, in ref: UIView) {
        let center = target.superview?.convert(target.center, to: containerView) ?? .zero
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
        UIView.animate(withDuration: 0.25, delay: 0.45) {
            self.tapDot.alpha = 0
            self.tapRing.alpha = 0
        }
    }

    private func hideTapIndicator() {
        tapDot.alpha = 0
        tapRing.alpha = 0
    }

    // MARK: - Helpers

    /// Rounded-square badge + center symbol — 실제 설정앱 leading icon 스타일
    private func makeBadgeIcon(_ symbolName: String, badgeColor: UIColor, symbolColor: UIColor = .white) -> UIView {
        let badge = UIView()
        badge.backgroundColor = badgeColor
        badge.layer.cornerRadius = 5
        badge.translatesAutoresizingMaskIntoConstraints = false

        let symbol = UIImageView()
        let config = UIImage.SymbolConfiguration(pointSize: 9, weight: .medium)
        symbol.image = UIImage(systemName: symbolName, withConfiguration: config)
        symbol.tintColor = symbolColor
        symbol.contentMode = .scaleAspectFit
        symbol.translatesAutoresizingMaskIntoConstraints = false
        badge.addSubview(symbol)

        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: 20),
            badge.heightAnchor.constraint(equalToConstant: 20),
            symbol.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
            symbol.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            symbol.widthAnchor.constraint(equalToConstant: 12),
            symbol.heightAnchor.constraint(equalToConstant: 12),
        ])
        return badge
    }

    /// Apple Intelligence 아이콘 — 다색 그라데이션 badge
    private func makeAIBadgeIcon() -> UIView {
        let badge = UIView()
        badge.layer.cornerRadius = 5
        badge.clipsToBounds = true
        badge.translatesAutoresizingMaskIntoConstraints = false

        let gradient = CAGradientLayer()
        gradient.colors = [
            UIColor(red: 0.95, green: 0.45, blue: 0.55, alpha: 1.0).cgColor, // pink
            UIColor(red: 0.75, green: 0.40, blue: 0.85, alpha: 1.0).cgColor, // purple
            UIColor(red: 0.40, green: 0.55, blue: 0.95, alpha: 1.0).cgColor, // blue
        ]
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        gradient.frame = CGRect(x: 0, y: 0, width: 20, height: 20)
        badge.layer.insertSublayer(gradient, at: 0)

        let symbol = UIImageView()
        let config = UIImage.SymbolConfiguration(pointSize: 9, weight: .medium)
        symbol.image = UIImage(systemName: "sparkles", withConfiguration: config)
        symbol.tintColor = .white
        symbol.contentMode = .scaleAspectFit
        symbol.translatesAutoresizingMaskIntoConstraints = false
        badge.addSubview(symbol)

        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: 20),
            badge.heightAnchor.constraint(equalToConstant: 20),
            symbol.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
            symbol.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            symbol.widthAnchor.constraint(equalToConstant: 12),
            symbol.heightAnchor.constraint(equalToConstant: 12),
        ])
        return badge
    }

    /// Legacy — detail screen 등에서 단순 아이콘 사용 시
    private func makeRowIcon(_ name: String, color: UIColor) -> UIView {
        return makeBadgeIcon(name, badgeColor: color)
    }

    private func makeChevron() -> UIImageView {
        let iv = UIImageView()
        iv.image = UIImage(systemName: "chevron.right")
        iv.tintColor = UIColor(white: 0.78, alpha: 1.0)
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iv.widthAnchor.constraint(equalToConstant: 6),
            iv.heightAnchor.constraint(equalToConstant: 10),
        ])
        return iv
    }

    private func makeSeparator() -> UIView {
        let v = UIView()
        v.backgroundColor = UIColor(white: 0.88, alpha: 1.0)
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }

    private func configureSectionHeader(_ label: UILabel) {
        label.font = .systemFont(ofSize: sectionFontSize)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureRow(_ row: UIView, icon: UIView, label: UILabel, accessory: UIView) {
        row.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: fontSize)
        label.translatesAutoresizingMaskIntoConstraints = false
        accessory.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(icon)
        row.addSubview(label)
        row.addSubview(accessory)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: rowHeight),
            icon.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 8),
            icon.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            accessory.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -8),
            accessory.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])
    }

    private func makeCardStack(rows: [UIView]) -> UIStackView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        for (i, row) in rows.enumerated() {
            stack.addArrangedSubview(row)
            if i < rows.count - 1 {
                let sep = makeSeparator()
                let sepWrapper = UIView()
                sepWrapper.translatesAutoresizingMaskIntoConstraints = false
                sepWrapper.addSubview(sep)
                NSLayoutConstraint.activate([
                    sep.topAnchor.constraint(equalTo: sepWrapper.topAnchor),
                    sep.leadingAnchor.constraint(equalTo: sepWrapper.leadingAnchor, constant: 30),
                    sep.trailingAnchor.constraint(equalTo: sepWrapper.trailingAnchor),
                    sep.bottomAnchor.constraint(equalTo: sepWrapper.bottomAnchor),
                    sep.heightAnchor.constraint(equalToConstant: 0.5),
                ])
                stack.addArrangedSubview(sepWrapper)
            }
        }
        return stack
    }

    private func pinCardStack(_ stack: UIStackView, in card: UIView) {
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
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
        case .root:     delay = 2.5  // v3: 첫 장면 더 오래 체류
        case .keyboard: delay = 1.5
        case .alert:    delay = 1.6
        case .done:     delay = 1.0
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
        case .root:     next = .keyboard
        case .keyboard: next = .alert
        case .alert:    next = .done
        case .done:     next = .root
        }
        resetToStage(next, animated: true)
        scheduleNext()
    }

    private func resetToStage(_ stage: Stage, animated: Bool) {
        currentStage = stage
        let dur: TimeInterval = animated ? 0.35 : 0.0
        hideTapIndicator()

        UIView.animate(withDuration: dur, delay: 0, options: .curveEaseInOut) {
            switch stage {
            case .root:
                self.navTitleLabel.text = L("onboarding.setup.anim.nav.root")
                self.backChevron.alpha = 0
                self.backLabel.alpha = 0
                self.rootScrollContent.alpha = 1
                self.detailContent.alpha = 0
                self.dimOverlay.alpha = 0
                self.alertBox.alpha = 0
                self.alertBox.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
                self.fullAccessToggle.setOn(false, animated: false)

            case .keyboard:
                self.navTitleLabel.text = L("onboarding.setup.anim.nav.keyboard")
                self.backChevron.alpha = 1
                self.backLabel.alpha = 1
                self.rootScrollContent.alpha = 0
                self.detailContent.alpha = 1
                self.dimOverlay.alpha = 0
                self.alertBox.alpha = 0
                self.alertBox.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
                self.fullAccessToggle.setOn(false, animated: false)

            case .alert:
                self.dimOverlay.alpha = 1
                self.alertBox.alpha = 1
                self.alertBox.transform = .identity

            case .done:
                self.dimOverlay.alpha = 0
                self.alertBox.alpha = 0
                self.alertBox.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
                self.fullAccessToggle.setOn(true, animated: true)
            }
        } completion: { _ in
            guard self.isAnimating else { return }
            // Show tap pulse after stage settles
            switch stage {
            case .root:
                self.keyboardRowHighlight.alpha = 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.showTapPulse(at: self.rowKeyboard, in: self.rootScrollContent)
                }
            case .keyboard:
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.showTapPulse(at: self.fullAccessToggle, in: self.detailContent)
                }
            case .alert:
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    self.showTapPulse(at: self.alertAllowBtn, in: self.alertBox)
                }
            case .done:
                break
            }
        }
    }
}

// MARK: - Mini Toggle View

private final class MiniToggleView: UIView {

    private let track = UIView()
    private let thumb = UIView()
    private var thumbLeading: NSLayoutConstraint!

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        track.layer.cornerRadius = 7
        track.backgroundColor = UIColor(white: 0.88, alpha: 1.0)
        track.translatesAutoresizingMaskIntoConstraints = false
        addSubview(track)

        thumb.backgroundColor = .white
        thumb.layer.cornerRadius = 5.5
        thumb.layer.shadowColor = UIColor.black.cgColor
        thumb.layer.shadowOpacity = 0.15
        thumb.layer.shadowOffset = CGSize(width: 0, height: 0.5)
        thumb.layer.shadowRadius = 0.5
        thumb.translatesAutoresizingMaskIntoConstraints = false
        addSubview(thumb)

        thumbLeading = thumb.leadingAnchor.constraint(equalTo: track.leadingAnchor, constant: 1)

        NSLayoutConstraint.activate([
            track.centerYAnchor.constraint(equalTo: centerYAnchor),
            track.leadingAnchor.constraint(equalTo: leadingAnchor),
            track.widthAnchor.constraint(equalToConstant: 26),
            track.heightAnchor.constraint(equalToConstant: 14),
            widthAnchor.constraint(equalToConstant: 26),
            heightAnchor.constraint(equalToConstant: 14),
            thumb.centerYAnchor.constraint(equalTo: track.centerYAnchor),
            thumb.widthAnchor.constraint(equalToConstant: 11),
            thumb.heightAnchor.constraint(equalToConstant: 11),
            thumbLeading,
        ])
    }

    func setOn(_ on: Bool, animated: Bool) {
        let action = {
            self.thumbLeading.constant = on ? 14 : 1
            self.track.backgroundColor = on ? .systemGreen : UIColor(white: 0.88, alpha: 1.0)
            self.layoutIfNeeded()
        }
        if animated {
            UIView.animate(withDuration: 0.25, animations: action)
        } else {
            action()
        }
    }
}
