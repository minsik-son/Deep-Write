import UIKit

class HomeViewController: UIViewController {

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    // MARK: - Greeting

    private let dateLabel = UILabel()
    private let greetingLabel = UILabel()

    // MARK: - Plan Card

    private let planCard = UIView()
    private let usageContainer = UIView()
    private let planCardTopLine = CAGradientLayer()
    private let usageBgGradient = CAGradientLayer()
    private var lastPlanCardWidth: CGFloat = 0
    private let planBadgeLabel = UILabel()
    private let planBadgeIconView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()
    private let planBadgeContainer: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 16
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    private var badgeLabelLeadingToIcon: NSLayoutConstraint!
    private var badgeLabelLeadingToContainer: NSLayoutConstraint!
    private let proLinkButton = UIButton(type: .system)
    private let corrProgressContainer = UIView()
    private let corrCenterLabel = UILabel()
    private let corrSubLabel = UILabel()
    private var corrTrackLayer = CAShapeLayer()
    private var corrProgressLayer = CAShapeLayer()
    private let transProgressContainer = UIView()
    private let transCenterLabel = UILabel()
    private let transSubLabel = UILabel()
    private var transTrackLayer = CAShapeLayer()
    private var transProgressLayer = CAShapeLayer()
    private let rewardCorrectionAdButton = UIButton(type: .system)
    private let rewardTranslationAdButton = UIButton(type: .system)

    private let circlesStack = UIStackView()

    // MARK: - Premium Tiles
    private let premiumTilesStack = UIStackView()
    private let premiumCorrNumLabel = UILabel()
    private let premiumTransNumLabel = UILabel()
    private let premiumComposeNumLabel = UILabel()
    private var circlesStackConstraints: [NSLayoutConstraint] = []
    private var premiumTilesConstraints: [NSLayoutConstraint] = []
    private let upgradeShimmerLayer = CAGradientLayer()
    private let upgradeGradientContainer = UIView()

    // MARK: - AI Writer Banner

    private let aiWriterBanner = UIView()
    private let pasteGuideBanner = UIView()

    // MARK: - Weekly Activity

    private let correctionCountLabel = UILabel()
    private let translationCountLabel = UILabel()
    private let clipboardCountLabel = UILabel()
    private let phrasesCountLabel = UILabel()

    // Stats 캐시 — refreshStats에서 계산, animateCountUp에서 재사용
    private var cachedCorrectionCount = 0
    private var cachedTranslationCount = 0
    private var cachedClipboardCount = 0
    private var cachedPhrasesCount = 0

    // MARK: - Calibration Card Labels
    private let calibrationTitleLabel = UILabel()
    private let calibrationDescLabel = UILabel()

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColors.bg
        setupNavigation()
        setupScrollView()
        buildContent()
        NotificationCenter.default.addObserver(self, selector: #selector(handleHistoryChange), name: .historyDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleLanguageChange), name: .languageDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleAppWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleHistoryChange), name: .savedPhrasesDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleSubscriptionChange), name: .subscriptionStatusDidChange, object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        StatsManager.shared.checkAndResetWeeklyStats()
        refreshStats()
        updateCalibrationCardText()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        animateEntrance()
    }

    // MARK: - Setup

    private func setupNavigation() {
        navigationItem.title = L("home.title")
        navigationController?.navigationBar.prefersLargeTitles = false
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.titleTextAttributes = [.foregroundColor: AppColors.text]
        navigationController?.navigationBar.standardAppearance = appearance
        navigationController?.navigationBar.scrollEdgeAppearance = appearance
    }

    private func setupScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 16),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -32),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -40),
        ])
    }

    // MARK: - Content

    private func buildContent() {
        // 1. Greeting Section
        buildGreetingSection()

        // 2. Plan Card
        buildPlanCard()
        contentStack.addArrangedSubview(planCard)
        contentStack.setCustomSpacing(16, after: planCard)

        // 3. AI Writer Banner
        buildAIWriterBanner()
        contentStack.addArrangedSubview(aiWriterBanner)
        contentStack.setCustomSpacing(24, after: aiWriterBanner)

        buildPasteGuideBanner()
        contentStack.addArrangedSubview(pasteGuideBanner)
        contentStack.setCustomSpacing(24, after: pasteGuideBanner)

        // 4. Weekly Activity
        let activityHeader = UILabel()
        activityHeader.text = L("home.activity.title").uppercased()
        activityHeader.font = .systemFont(ofSize: 13, weight: .semibold)
        activityHeader.textColor = AppColors.textMuted
        let attributedHeader = NSAttributedString(
            string: L("home.activity.title").uppercased(),
            attributes: [
                .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: AppColors.textMuted,
                .kern: 0.3,
            ]
        )
        activityHeader.attributedText = attributedHeader
        contentStack.addArrangedSubview(activityHeader)

        let activityCard = buildActivityCard()
        contentStack.addArrangedSubview(activityCard)
        contentStack.setCustomSpacing(24, after: activityCard)

        // 5. Touch Calibration CTA
        let calibrationCard = buildCalibrationCard()
        contentStack.addArrangedSubview(calibrationCard)

    }

    // MARK: - 1. Greeting Section

    private func buildGreetingSection() {
        let greetingContainer = UIStackView()
        greetingContainer.axis = .vertical
        greetingContainer.spacing = 6

        dateLabel.font = .systemFont(ofSize: 14, weight: .regular)
        dateLabel.textColor = AppColors.textMuted
        greetingContainer.addArrangedSubview(dateLabel)

        greetingLabel.font = .systemFont(ofSize: 26, weight: .bold)
        greetingLabel.textColor = AppColors.text
        greetingLabel.numberOfLines = 0

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = 1.3
        greetingLabel.attributedText = NSAttributedString(
            string: " ",
            attributes: [
                .font: UIFont.systemFont(ofSize: 26, weight: .bold),
                .paragraphStyle: paragraphStyle,
            ]
        )
        greetingContainer.addArrangedSubview(greetingLabel)

        contentStack.addArrangedSubview(greetingContainer)
        contentStack.setCustomSpacing(24, after: greetingContainer)
    }

    // MARK: - 2. Plan Card

    private func buildPlanCard() {
        planCard.backgroundColor = AppColors.card
        planCard.layer.cornerRadius = AppRadius.md
        planCard.layer.shadowColor = UIColor.black.cgColor
        planCard.layer.shadowOpacity = 0.04
        planCard.layer.shadowOffset = CGSize(width: 0, height: 1)
        planCard.layer.shadowRadius = 3

        // planCardTopLine: 3px gradient line at top (conditional insert)
        if planCardTopLine.superlayer == nil {
            planCardTopLine.startPoint = CGPoint(x: 0, y: 0.5)
            planCardTopLine.endPoint = CGPoint(x: 1, y: 0.5)
            planCardTopLine.frame = CGRect(x: 0, y: 0, width: max(planCard.bounds.width, 1), height: 3)

            let topLineMask = CAShapeLayer()
            let maskRect = CGRect(x: 0, y: 0, width: max(planCard.bounds.width, 1), height: 3)
            topLineMask.frame = maskRect
            topLineMask.path = UIBezierPath(
                roundedRect: maskRect,
                byRoundingCorners: [.topLeft, .topRight],
                cornerRadii: CGSize(width: 1.5, height: 1.5)
            ).cgPath
            planCardTopLine.mask = topLineMask

            planCard.layer.addSublayer(planCardTopLine)
        }

        let mainStack = UIStackView()
        mainStack.axis = .vertical
        mainStack.spacing = 16
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        planCard.addSubview(mainStack)
        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: planCard.topAnchor, constant: 24),
            mainStack.leadingAnchor.constraint(equalTo: planCard.leadingAnchor, constant: 24),
            mainStack.trailingAnchor.constraint(equalTo: planCard.trailingAnchor, constant: -24),
            mainStack.bottomAnchor.constraint(equalTo: planCard.bottomAnchor, constant: -24),
        ])

        // Top area: badge + pro link
        let topRow = UIStackView()
        topRow.axis = .horizontal
        topRow.alignment = .center
        topRow.distribution = .equalSpacing

        // Plan badge (pill shape) — 아이콘 + 텍스트
        planBadgeLabel.font = .systemFont(ofSize: 13, weight: .bold)
        planBadgeLabel.textAlignment = .center
        planBadgeLabel.translatesAutoresizingMaskIntoConstraints = false
        planBadgeLabel.setContentHuggingPriority(.required, for: .horizontal)
        planBadgeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        planBadgeContainer.addSubview(planBadgeIconView)
        planBadgeContainer.addSubview(planBadgeLabel)

        badgeLabelLeadingToIcon = planBadgeLabel.leadingAnchor.constraint(equalTo: planBadgeIconView.trailingAnchor, constant: 4)
        badgeLabelLeadingToContainer = planBadgeLabel.leadingAnchor.constraint(equalTo: planBadgeContainer.leadingAnchor, constant: 12)
        badgeLabelLeadingToIcon.isActive = true
        badgeLabelLeadingToContainer.isActive = false

        NSLayoutConstraint.activate([
            planBadgeContainer.heightAnchor.constraint(equalToConstant: 32),

            planBadgeIconView.leadingAnchor.constraint(equalTo: planBadgeContainer.leadingAnchor, constant: 10),
            planBadgeIconView.centerYAnchor.constraint(equalTo: planBadgeContainer.centerYAnchor),
            planBadgeIconView.widthAnchor.constraint(equalToConstant: 14),
            planBadgeIconView.heightAnchor.constraint(equalToConstant: 14),

            planBadgeLabel.trailingAnchor.constraint(equalTo: planBadgeContainer.trailingAnchor, constant: -12),
            planBadgeLabel.centerYAnchor.constraint(equalTo: planBadgeContainer.centerYAnchor),
        ])

        let badgeWrapper = UIView()
        badgeWrapper.addSubview(planBadgeContainer)
        NSLayoutConstraint.activate([
            planBadgeContainer.topAnchor.constraint(equalTo: badgeWrapper.topAnchor),
            planBadgeContainer.leadingAnchor.constraint(equalTo: badgeWrapper.leadingAnchor),
            planBadgeContainer.bottomAnchor.constraint(equalTo: badgeWrapper.bottomAnchor),
        ])

        topRow.addArrangedSubview(badgeWrapper)

        // Upgrade button (Free tier only — shimmer gradient pill)
        proLinkButton.translatesAutoresizingMaskIntoConstraints = false
        proLinkButton.addTarget(self, action: #selector(subscribeTapped), for: .touchUpInside)

        proLinkButton.backgroundColor = .clear
        proLinkButton.layer.cornerRadius = 16
        proLinkButton.layer.shadowColor = UIColor(red: 0.290, green: 0.102, blue: 0.541, alpha: 1).cgColor
        proLinkButton.layer.shadowOpacity = 0.35
        proLinkButton.layer.shadowRadius = 8
        proLinkButton.layer.shadowOffset = CGSize(width: 0, height: 2)

        upgradeGradientContainer.layer.cornerRadius = 16
        upgradeGradientContainer.clipsToBounds = true
        upgradeGradientContainer.isUserInteractionEnabled = false
        upgradeGradientContainer.translatesAutoresizingMaskIntoConstraints = false
        proLinkButton.addSubview(upgradeGradientContainer)

        let upgradeGradient = CAGradientLayer()
        upgradeGradient.colors = [
            UIColor(red: 0.290, green: 0.102, blue: 0.541, alpha: 1).cgColor,
            UIColor(red: 0.420, green: 0.247, blue: 0.627, alpha: 1).cgColor,
            UIColor(red: 0.545, green: 0.361, blue: 0.784, alpha: 1).cgColor,
        ]
        upgradeGradient.startPoint = CGPoint(x: 0, y: 0)
        upgradeGradient.endPoint = CGPoint(x: 1, y: 1)
        upgradeGradientContainer.layer.addSublayer(upgradeGradient)

        let highlightLine = UIView()
        highlightLine.backgroundColor = UIColor.white.withAlphaComponent(0.15)
        highlightLine.translatesAutoresizingMaskIntoConstraints = false
        highlightLine.isUserInteractionEnabled = false
        upgradeGradientContainer.addSubview(highlightLine)

        upgradeShimmerLayer.colors = [
            UIColor.clear.cgColor,
            UIColor.white.withAlphaComponent(0.12).cgColor,
            UIColor.clear.cgColor,
        ]
        upgradeShimmerLayer.locations = [0, 0.5, 1]
        upgradeShimmerLayer.startPoint = CGPoint(x: 0, y: 0.5)
        upgradeShimmerLayer.endPoint = CGPoint(x: 1, y: 0.5)
        upgradeGradientContainer.layer.addSublayer(upgradeShimmerLayer)

        let crownView = UIImageView(image: UIImage(named: "CrownIcon")?.withRenderingMode(.alwaysTemplate))
        crownView.tintColor = .systemYellow
        crownView.contentMode = .scaleAspectFit
        crownView.translatesAutoresizingMaskIntoConstraints = false
        crownView.isUserInteractionEnabled = false
        proLinkButton.addSubview(crownView)

        let upgradeLabel = UILabel()
        upgradeLabel.text = L("settings.plan.upgrade")
        upgradeLabel.font = .systemFont(ofSize: 12, weight: .bold)
        upgradeLabel.textColor = .white
        upgradeLabel.numberOfLines = 1
        upgradeLabel.adjustsFontSizeToFitWidth = true
        upgradeLabel.minimumScaleFactor = 0.8
        upgradeLabel.translatesAutoresizingMaskIntoConstraints = false
        upgradeLabel.isUserInteractionEnabled = false
        proLinkButton.addSubview(upgradeLabel)

        NSLayoutConstraint.activate([
            proLinkButton.heightAnchor.constraint(equalToConstant: 32),
            proLinkButton.widthAnchor.constraint(lessThanOrEqualToConstant: 120),

            upgradeGradientContainer.topAnchor.constraint(equalTo: proLinkButton.topAnchor),
            upgradeGradientContainer.leadingAnchor.constraint(equalTo: proLinkButton.leadingAnchor),
            upgradeGradientContainer.trailingAnchor.constraint(equalTo: proLinkButton.trailingAnchor),
            upgradeGradientContainer.bottomAnchor.constraint(equalTo: proLinkButton.bottomAnchor),

            highlightLine.topAnchor.constraint(equalTo: upgradeGradientContainer.topAnchor),
            highlightLine.leadingAnchor.constraint(equalTo: upgradeGradientContainer.leadingAnchor),
            highlightLine.trailingAnchor.constraint(equalTo: upgradeGradientContainer.trailingAnchor),
            highlightLine.heightAnchor.constraint(equalToConstant: 1),

            crownView.leadingAnchor.constraint(equalTo: proLinkButton.leadingAnchor, constant: 12),
            crownView.centerYAnchor.constraint(equalTo: proLinkButton.centerYAnchor),
            crownView.widthAnchor.constraint(equalToConstant: 14),
            crownView.heightAnchor.constraint(equalToConstant: 14),

            upgradeLabel.leadingAnchor.constraint(equalTo: crownView.trailingAnchor, constant: 5),
            upgradeLabel.centerYAnchor.constraint(equalTo: proLinkButton.centerYAnchor),
            upgradeLabel.trailingAnchor.constraint(equalTo: proLinkButton.trailingAnchor, constant: -14),
        ])
        topRow.addArrangedSubview(proLinkButton)

        mainStack.addArrangedSubview(topRow)

        // Usage area: grey background with two circles
        // usageContainer is a class property — no let declaration
        usageContainer.subviews.forEach { $0.removeFromSuperview() }

        usageContainer.backgroundColor = UIColor { $0.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.06)
            : UIColor(red: 0.965, green: 0.965, blue: 0.975, alpha: 1)
        }
        usageContainer.layer.cornerRadius = AppRadius.sm
        usageContainer.clipsToBounds = true

        // Pro/Premium usage background gradient (conditional insert)
        if usageBgGradient.superlayer == nil {
            usageBgGradient.startPoint = CGPoint(x: 0, y: 0)
            usageBgGradient.endPoint = CGPoint(x: 1, y: 1)
            usageBgGradient.cornerRadius = AppRadius.sm
            usageBgGradient.isHidden = true
            usageContainer.layer.insertSublayer(usageBgGradient, at: 0)
        }

        let circleSize: CGFloat = 72

        // Correction circle column
        let corrColumn = UIStackView()
        corrColumn.axis = .vertical
        corrColumn.spacing = 6
        corrColumn.alignment = .center

        corrProgressContainer.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            corrProgressContainer.widthAnchor.constraint(equalToConstant: circleSize),
            corrProgressContainer.heightAnchor.constraint(equalToConstant: circleSize),
        ])
        corrCenterLabel.font = .systemFont(ofSize: 15, weight: .bold)
        corrCenterLabel.textColor = AppColors.text
        corrCenterLabel.textAlignment = .center
        corrCenterLabel.translatesAutoresizingMaskIntoConstraints = false
        corrProgressContainer.addSubview(corrCenterLabel)
        NSLayoutConstraint.activate([
            corrCenterLabel.centerXAnchor.constraint(equalTo: corrProgressContainer.centerXAnchor),
            corrCenterLabel.centerYAnchor.constraint(equalTo: corrProgressContainer.centerYAnchor),
        ])

        corrSubLabel.text = L("home.daily.corrections")
        corrSubLabel.font = .systemFont(ofSize: 12, weight: .medium)
        corrSubLabel.textColor = AppColors.textSub

        corrColumn.addArrangedSubview(corrProgressContainer)
        corrColumn.addArrangedSubview(corrSubLabel)

        // Translation circle column
        let transColumn = UIStackView()
        transColumn.axis = .vertical
        transColumn.spacing = 6
        transColumn.alignment = .center

        transProgressContainer.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            transProgressContainer.widthAnchor.constraint(equalToConstant: circleSize),
            transProgressContainer.heightAnchor.constraint(equalToConstant: circleSize),
        ])
        transCenterLabel.font = .systemFont(ofSize: 15, weight: .bold)
        transCenterLabel.textColor = AppColors.text
        transCenterLabel.textAlignment = .center
        transCenterLabel.translatesAutoresizingMaskIntoConstraints = false
        transProgressContainer.addSubview(transCenterLabel)
        NSLayoutConstraint.activate([
            transCenterLabel.centerXAnchor.constraint(equalTo: transProgressContainer.centerXAnchor),
            transCenterLabel.centerYAnchor.constraint(equalTo: transProgressContainer.centerYAnchor),
        ])

        transSubLabel.text = L("home.daily.translations")
        transSubLabel.font = .systemFont(ofSize: 12, weight: .medium)
        transSubLabel.textColor = AppColors.textSub

        transColumn.addArrangedSubview(transProgressContainer)
        transColumn.addArrangedSubview(transSubLabel)

        // Two circles side by side
        circlesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        circlesStack.addArrangedSubview(corrColumn)
        circlesStack.addArrangedSubview(transColumn)
        circlesStack.axis = .horizontal
        circlesStack.spacing = 32
        circlesStack.alignment = .center
        circlesStack.distribution = .equalCentering
        circlesStack.translatesAutoresizingMaskIntoConstraints = false

        usageContainer.addSubview(circlesStack)
        circlesStackConstraints = [
            circlesStack.topAnchor.constraint(equalTo: usageContainer.topAnchor, constant: 16),
            circlesStack.centerXAnchor.constraint(equalTo: usageContainer.centerXAnchor),
            circlesStack.bottomAnchor.constraint(equalTo: usageContainer.bottomAnchor, constant: -16),
        ]
        NSLayoutConstraint.activate(circlesStackConstraints)

        // Premium tiles (3-column compact tiles — Premium only)
        premiumTilesStack.axis = .horizontal
        premiumTilesStack.spacing = 8
        premiumTilesStack.distribution = .fillEqually
        premiumTilesStack.translatesAutoresizingMaskIntoConstraints = false

        let corrTile = buildPremiumTile(numLabel: premiumCorrNumLabel,
                                        unitText: L("home.stat.this_week"),
                                        nameText: L("home.stat.corrections"))
        let transTile = buildPremiumTile(numLabel: premiumTransNumLabel,
                                         unitText: L("home.stat.this_week"),
                                         nameText: L("home.stat.translations"))
        let composeTile = buildPremiumTile(numLabel: premiumComposeNumLabel,
                                           unitText: L("home.stat.this_week"),
                                           nameText: L("home.tile.ai_compose"))

        premiumTilesStack.addArrangedSubview(corrTile)
        premiumTilesStack.addArrangedSubview(transTile)
        premiumTilesStack.addArrangedSubview(composeTile)

        usageContainer.addSubview(premiumTilesStack)
        premiumTilesConstraints = [
            premiumTilesStack.topAnchor.constraint(equalTo: usageContainer.topAnchor, constant: 16),
            premiumTilesStack.leadingAnchor.constraint(equalTo: usageContainer.leadingAnchor, constant: 12),
            premiumTilesStack.trailingAnchor.constraint(equalTo: usageContainer.trailingAnchor, constant: -12),
            premiumTilesStack.bottomAnchor.constraint(equalTo: usageContainer.bottomAnchor, constant: -16),
        ]
        // 기본 비활성 — updatePlanCard()에서 활성화

        mainStack.addArrangedSubview(usageContainer)

        // Reward Ad Buttons (free tier only, conditional per mode)
        configureRewardButton(rewardCorrectionAdButton, action: #selector(rewardCorrectionTapped))
        configureRewardButton(rewardTranslationAdButton, action: #selector(rewardTranslationTapped))

        mainStack.addArrangedSubview(rewardCorrectionAdButton)
        mainStack.addArrangedSubview(rewardTranslationAdButton)
    }

    private func configureRewardButton(_ button: UIButton, action: Selector) {
        button.backgroundColor = AppColors.tierAccentSoft
        button.layer.cornerRadius = AppRadius.sm
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        button.setTitleColor(AppColors.tierAccent, for: .normal)
        button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)

        let playIcon = UIImage(systemName: "play.fill")?.withConfiguration(
            UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        )
        button.setImage(playIcon, for: .normal)
        button.tintColor = AppColors.tierAccent
        button.semanticContentAttribute = .forceLeftToRight
        button.imageEdgeInsets = UIEdgeInsets(top: 0, left: -4, bottom: 0, right: 4)
        button.addTarget(self, action: action, for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 40).isActive = true
    }

    private func buildPremiumTile(numLabel: UILabel, unitText: String, nameText: String) -> UIView {
        let tile = UIView()
        tile.layer.cornerRadius = 12
        tile.clipsToBounds = true

        // 상단 3px 그라디언트 라인 (tag 100으로 식별)
        let topLine = CAGradientLayer()
        topLine.colors = [
            UIColor(red: 0.545, green: 0.361, blue: 0.784, alpha: 1).cgColor,
            UIColor(red: 0.655, green: 0.494, blue: 0.859, alpha: 1).cgColor,
        ]
        topLine.startPoint = CGPoint(x: 0, y: 0.5)
        topLine.endPoint = CGPoint(x: 1, y: 0.5)
        topLine.frame = CGRect(x: 0, y: 0, width: 200, height: 3) // viewDidLayoutSubviews에서 리사이즈
        tile.layer.addSublayer(topLine)
        tile.tag = 9001 // 타일 식별용

        // 배경색 (dynamic light/dark)
        tile.backgroundColor = UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.05)
                : UIColor.white.withAlphaComponent(0.7)
        }

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false

        // 숫자 라벨
        numLabel.font = .systemFont(ofSize: 22, weight: .heavy)
        numLabel.textColor = UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.769, green: 0.627, blue: 0.910, alpha: 1) // #C4A0E8
                : UIColor(red: 0.420, green: 0.247, blue: 0.627, alpha: 1) // #6B3FA0
        }
        numLabel.textAlignment = .center
        numLabel.text = "0"

        // "이번 주" 라벨
        let unitLabel = UILabel()
        unitLabel.font = .systemFont(ofSize: 9, weight: .semibold)
        unitLabel.textColor = UIColor(red: 0.655, green: 0.494, blue: 0.859, alpha: 1) // #A77EDB
        unitLabel.textAlignment = .center
        unitLabel.text = unitText

        // 카테고리명 라벨
        let nameLabel = UILabel()
        nameLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        nameLabel.textColor = UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(white: 0.467, alpha: 1) // #777
                : UIColor(white: 0.6, alpha: 1)   // #999
        }
        nameLabel.textAlignment = .center
        nameLabel.text = nameText

        stack.addArrangedSubview(numLabel)
        stack.addArrangedSubview(unitLabel)
        stack.addArrangedSubview(nameLabel)

        tile.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: tile.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: tile.bottomAnchor, constant: -12),
            stack.leadingAnchor.constraint(equalTo: tile.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: tile.trailingAnchor, constant: -8),
        ])

        return tile
    }

    /// Premium 타일 상단 그라디언트 라인을 실제 타일 너비로 리사이즈
    private func updateTileTopLines() {
        for tile in premiumTilesStack.arrangedSubviews where tile.tag == 9001 {
            if let topLine = tile.layer.sublayers?.first as? CAGradientLayer {
                topLine.frame = CGRect(x: 0, y: 0, width: tile.bounds.width, height: 3)
            }
        }
    }

    private func setupCircle(container: UIView, trackLayer: inout CAShapeLayer, progressLayer: inout CAShapeLayer, used: Int, total: Int, color: UIColor, isPremiumTrack: Bool = false) {
        trackLayer.removeFromSuperlayer()
        progressLayer.removeFromSuperlayer()

        let size: CGFloat = 72
        let center = CGPoint(x: size / 2, y: size / 2)
        let radius: CGFloat = (size - 6) / 2 // 6pt lineWidth
        let lineWidth: CGFloat = 6
        let startAngle = -CGFloat.pi / 2
        let endAngle = startAngle + 2 * CGFloat.pi

        let circularPath = UIBezierPath(
            arcCenter: center, radius: radius,
            startAngle: startAngle, endAngle: endAngle, clockwise: true
        )

        // Track
        trackLayer = CAShapeLayer()
        trackLayer.path = circularPath.cgPath
        let trackColor = UIColor { trait in
            if trait.userInterfaceStyle == .dark {
                return UIColor.white.withAlphaComponent(0.1)
            } else {
                return color.withAlphaComponent(isPremiumTrack ? 0.10 : 0.12)
            }
        }
        trackLayer.strokeColor = trackColor.cgColor
        // 라이트 모드: 원 중앙을 흰색으로 채움 / 다크 모드: 투명 유지
        let fillColor = UIColor { $0.userInterfaceStyle == .dark
            ? UIColor.clear
            : UIColor.white
        }
        trackLayer.fillColor = fillColor.cgColor
        trackLayer.lineWidth = lineWidth
        trackLayer.lineCap = .round
        container.layer.insertSublayer(trackLayer, at: 0)

        // Progress
        progressLayer = CAShapeLayer()
        progressLayer.path = circularPath.cgPath
        progressLayer.fillColor = UIColor.clear.cgColor
        progressLayer.lineWidth = lineWidth
        progressLayer.lineCap = .round

        let fraction = total > 0 ? CGFloat(used) / CGFloat(total) : 0
        progressLayer.strokeEnd = min(fraction, 1.0)

        if fraction >= 1.0 {
            progressLayer.strokeColor = UIColor.systemRed.cgColor
        } else if fraction >= 0.7 {
            progressLayer.strokeColor = AppColors.orange.cgColor
        } else {
            progressLayer.strokeColor = color.cgColor
        }

        container.layer.insertSublayer(progressLayer, at: 1)
    }

    private func updatePlanCard() {
        let tier = SubscriptionStatus.shared.currentTier
        let usage = DailyUsageManager.shared

        // Badge — tier별 색상 + PNG 아이콘 적용
        switch tier {
        case .free:
            planBadgeLabel.text = L("home.plan.free")
            planBadgeLabel.textColor = AppColors.tierAccent
            planBadgeContainer.backgroundColor = AppColors.tierAccentSoft
            planBadgeIconView.image = nil
            planBadgeIconView.isHidden = true
            badgeLabelLeadingToIcon.isActive = false
            badgeLabelLeadingToContainer.isActive = true
            proLinkButton.isHidden = false
            startUpgradeShimmer()
        case .pro:
            planBadgeLabel.text = L("home.plan.pro")
            planBadgeLabel.textColor = AppColors.gold
            planBadgeContainer.backgroundColor = AppColors.goldSoft
            planBadgeIconView.image = UIImage(named: "CrownIcon")
            planBadgeIconView.isHidden = false
            badgeLabelLeadingToContainer.isActive = false
            badgeLabelLeadingToIcon.isActive = true
            stopUpgradeShimmer()
            proLinkButton.isHidden = true
            rewardCorrectionAdButton.isHidden = true
            rewardTranslationAdButton.isHidden = true
        case .premium:
            planBadgeLabel.text = L("home.plan.premium")
            planBadgeLabel.textColor = AppColors.purple
            planBadgeContainer.backgroundColor = AppColors.purpleSoft
            planBadgeIconView.image = UIImage(named: "DiamondIcon")
            planBadgeIconView.isHidden = false
            badgeLabelLeadingToContainer.isActive = false
            badgeLabelLeadingToIcon.isActive = true
            stopUpgradeShimmer()
            proLinkButton.isHidden = true
            rewardCorrectionAdButton.isHidden = true
            rewardTranslationAdButton.isHidden = true
        }

        // Correction circle
        let corrUsed = usage.correctionCount
        let corrTotal = FeatureGate.shared.dailyCorrectionLimit
            + (UserDefaults(suiteName: AppConstants.appGroupIdentifier)?.integer(forKey: "bonus_correction_count") ?? 0)

        // Translation circle
        let transUsed = usage.translationCount
        let transTotal = FeatureGate.shared.dailyTranslationLimit
            + (UserDefaults(suiteName: AppConstants.appGroupIdentifier)?.integer(forKey: "bonus_translation_count") ?? 0)

        // Plan Card visual tier differentiation
        let isDark = traitCollection.userInterfaceStyle == .dark

        switch tier {
        case .free:
            planCardTopLine.isHidden = true
            planCard.layer.shadowColor = UIColor.black.cgColor
            planCard.layer.shadowOpacity = 0.04
            planCard.layer.shadowRadius = 3
            usageBgGradient.isHidden = true
            usageContainer.backgroundColor = UIColor { $0.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.06)
                : UIColor(red: 0.965, green: 0.965, blue: 0.975, alpha: 1)
            }

        case .pro:
            planCardTopLine.isHidden = false
            if isDark {
                planCardTopLine.colors = [
                    UIColor(red: 0.702, green: 0.549, blue: 0.235, alpha: 1).cgColor,
                    UIColor(red: 0.792, green: 0.631, blue: 0.298, alpha: 1).cgColor,
                ]
            } else {
                planCardTopLine.colors = [
                    UIColor(red: 0.471, green: 0.337, blue: 0.0, alpha: 1).cgColor,
                    UIColor(red: 0.596, green: 0.427, blue: 0.0, alpha: 1).cgColor,
                ]
            }
            planCard.layer.shadowColor = isDark
                ? UIColor(red: 0.702, green: 0.549, blue: 0.235, alpha: 1).cgColor
                : UIColor(red: 0.620, green: 0.455, blue: 0.165, alpha: 1).cgColor
            planCard.layer.shadowOpacity = isDark ? 0.12 : 0.08
            planCard.layer.shadowRadius = 12
            if isDark {
                usageBgGradient.isHidden = true
                usageContainer.backgroundColor = UIColor.white.withAlphaComponent(0.06)
            } else {
                usageContainer.backgroundColor = .clear
                usageBgGradient.isHidden = false
                usageBgGradient.colors = [
                    UIColor(red: 0.992, green: 0.980, blue: 0.953, alpha: 1).cgColor,
                    UIColor(red: 0.973, green: 0.957, blue: 0.922, alpha: 1).cgColor,
                ]
                let usageBounds = usageContainer.bounds
                if usageBounds.width > 0 && usageBounds.height > 0 {
                    usageBgGradient.frame = usageBounds
                }
            }

        case .premium:
            planCardTopLine.isHidden = false
            if isDark {
                planCardTopLine.colors = [
                    UIColor(red: 0.533, green: 0.376, blue: 0.792, alpha: 1).cgColor,
                    UIColor(red: 0.600, green: 0.431, blue: 0.859, alpha: 1).cgColor,
                ]
            } else {
                planCardTopLine.colors = [
                    UIColor(red: 0.369, green: 0.208, blue: 0.631, alpha: 1).cgColor,
                    UIColor(red: 0.416, green: 0.239, blue: 0.690, alpha: 1).cgColor,
                ]
            }
            planCard.layer.shadowColor = isDark
                ? UIColor(red: 0.533, green: 0.376, blue: 0.792, alpha: 1).cgColor
                : UIColor(red: 0.486, green: 0.306, blue: 0.749, alpha: 1).cgColor
            planCard.layer.shadowOpacity = isDark ? 0.12 : 0.08
            planCard.layer.shadowRadius = 12
            if isDark {
                usageBgGradient.isHidden = true
                usageContainer.backgroundColor = UIColor.white.withAlphaComponent(0.06)
            } else {
                usageContainer.backgroundColor = .clear
                usageBgGradient.isHidden = false
                usageBgGradient.colors = [
                    UIColor(red: 0.980, green: 0.969, blue: 0.992, alpha: 1).cgColor,
                    UIColor(red: 0.953, green: 0.933, blue: 0.976, alpha: 1).cgColor,
                ]
                let usageBounds = usageContainer.bounds
                if usageBounds.width > 0 && usageBounds.height > 0 {
                    usageBgGradient.frame = usageBounds
                }
            }
        }

        // Layout toggle: circles vs premium tiles
        let isPremiumTier = (tier == .premium)

        if isPremiumTier && FeatureGate.shared.isPremiumUnlimited {
            // ── Premium: 타일 표시, 원형 링 숨김 ──
            NSLayoutConstraint.deactivate(circlesStackConstraints)
            NSLayoutConstraint.activate(premiumTilesConstraints)
            circlesStack.isHidden = true
            premiumTilesStack.isHidden = false

            // 보상 버튼 숨김 (Premium은 필요 없음)
            rewardCorrectionAdButton.isHidden = true
            rewardTranslationAdButton.isHidden = true

            // 주간 사용량 업데이트
            premiumCorrNumLabel.text = "\(StatsManager.shared.weeklyCorrections)"
            premiumTransNumLabel.text = "\(StatsManager.shared.weeklyTranslations)"

            // AI 작성 주간 카운트
            var calendar = Calendar.current
            calendar.firstWeekday = 2  // Monday
            let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
            let monday = calendar.date(from: components) ?? Date()
            let weeklyComposeCount = ComposeHistoryManager.shared.items.filter { $0.timestamp >= monday }.count
            premiumComposeNumLabel.text = "\(weeklyComposeCount)"

            // 타일 topLine 프레임 보정
            DispatchQueue.main.async { [weak self] in
                self?.updateTileTopLines()
            }
        } else {
            // ── Free/Pro: 원형 링 표시, 타일 숨김 ──
            NSLayoutConstraint.deactivate(premiumTilesConstraints)
            NSLayoutConstraint.activate(circlesStackConstraints)
            circlesStack.isHidden = false
            premiumTilesStack.isHidden = true

            corrCenterLabel.text = "\(corrUsed)/\(corrTotal)"
            corrCenterLabel.font = .systemFont(ofSize: 15, weight: .bold)
            transCenterLabel.text = "\(transUsed)/\(transTotal)"
            transCenterLabel.font = .systemFont(ofSize: 15, weight: .bold)

            let corrRingColor: UIColor
            let transRingColor: UIColor
            switch tier {
            case .pro:
                corrRingColor = AppColors.gold
                transRingColor = AppColors.gold
            case .premium:
                corrRingColor = AppColors.purple
                transRingColor = AppColors.purple
            case .free:
                corrRingColor = AppColors.orange
                transRingColor = AppColors.tierAccent
            }

            setupCircle(container: corrProgressContainer, trackLayer: &corrTrackLayer, progressLayer: &corrProgressLayer, used: corrUsed, total: corrTotal, color: corrRingColor, isPremiumTrack: isPremiumTier)
            setupCircle(container: transProgressContainer, trackLayer: &transTrackLayer, progressLayer: &transProgressLayer, used: transUsed, total: transTotal, color: transRingColor, isPremiumTrack: isPremiumTier)
        }

        // Conditional reward button visibility (free tier only)
        if tier == .free {
            let corrMaxed = corrUsed >= corrTotal
            let transMaxed = transUsed >= transTotal

            rewardCorrectionAdButton.isHidden = !corrMaxed
            rewardTranslationAdButton.isHidden = !transMaxed

            rewardCorrectionAdButton.setTitle(String(format: L("home.reward_ad.cta_mode"), L("reward.mode.correction")), for: .normal)
            rewardTranslationAdButton.setTitle(String(format: L("home.reward_ad.cta_mode"), L("reward.mode.translation")), for: .normal)
        }
    }

    private func updateBannerColors() {
        let tier = SubscriptionStatus.shared.currentTier

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // AI Writer Banner gradient
        if let aiGradient = aiWriterBanner.layer.sublayers?.first as? CAGradientLayer {
            switch tier {
            case .free:
                aiGradient.colors = [
                    UIColor(red: 0.192, green: 0.510, blue: 0.965, alpha: 1).cgColor,
                    UIColor(red: 0.106, green: 0.392, blue: 0.855, alpha: 1).cgColor,
                ]
            case .pro:
                aiGradient.colors = [
                    UIColor(red: 0.773, green: 0.580, blue: 0.227, alpha: 1).cgColor,
                    UIColor(red: 0.620, green: 0.455, blue: 0.157, alpha: 1).cgColor,
                ]
            case .premium:
                aiGradient.colors = [
                    UIColor(red: 0.545, green: 0.361, blue: 0.784, alpha: 1).cgColor,
                    UIColor(red: 0.416, green: 0.247, blue: 0.667, alpha: 1).cgColor,
                ]
            }
        }

        // Paste Guide Banner gradient
        if let pasteGradient = pasteGuideBanner.layer.sublayers?.first as? CAGradientLayer {
            switch tier {
            case .free:
                pasteGradient.colors = [
                    UIColor(red: 0.0, green: 0.808, blue: 0.706, alpha: 1).cgColor,
                    UIColor(red: 0.0, green: 0.624, blue: 0.576, alpha: 1).cgColor,
                ]
            case .pro:
                pasteGradient.colors = [
                    UIColor(red: 0.722, green: 0.537, blue: 0.180, alpha: 1).cgColor,
                    UIColor(red: 0.541, green: 0.408, blue: 0.125, alpha: 1).cgColor,
                ]
            case .premium:
                pasteGradient.colors = [
                    UIColor(red: 0.486, green: 0.306, blue: 0.749, alpha: 1).cgColor,
                    UIColor(red: 0.369, green: 0.208, blue: 0.631, alpha: 1).cgColor,
                ]
            }
        }

        CATransaction.commit()
    }

    // MARK: - 3. AI Writer Banner

    private func buildAIWriterBanner() {
        aiWriterBanner.layer.cornerRadius = AppRadius.md
        aiWriterBanner.clipsToBounds = true

        // Gradient background
        let gradientLayer = CAGradientLayer()
        gradientLayer.colors = [
            UIColor(red: 0.192, green: 0.510, blue: 0.965, alpha: 1).cgColor, // #3182F6
            UIColor(red: 0.106, green: 0.392, blue: 0.855, alpha: 1).cgColor, // #1B64DA
        ]
        // 135 degrees: startPoint top-left, endPoint bottom-right
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        gradientLayer.frame = CGRect(x: 0, y: 0, width: 1000, height: 200) // will be resized in layoutSubviews
        aiWriterBanner.layer.insertSublayer(gradientLayer, at: 0)

        // Decorative circle (top-right, partially clipped)
        let decorCircle = UIView()
        decorCircle.backgroundColor = UIColor.white.withAlphaComponent(0.1)
        decorCircle.layer.cornerRadius = 50
        decorCircle.translatesAutoresizingMaskIntoConstraints = false
        aiWriterBanner.addSubview(decorCircle)
        NSLayoutConstraint.activate([
            decorCircle.widthAnchor.constraint(equalToConstant: 100),
            decorCircle.heightAnchor.constraint(equalToConstant: 100),
            decorCircle.topAnchor.constraint(equalTo: aiWriterBanner.topAnchor, constant: -30),
            decorCircle.trailingAnchor.constraint(equalTo: aiWriterBanner.trailingAnchor, constant: 30),
        ])

        // Text content
        let titleLabel = UILabel()
        titleLabel.text = L("home.ai_banner.title")
        titleLabel.font = .systemFont(ofSize: 18, weight: .bold)
        titleLabel.textColor = .white

        let subtitleLabel = UILabel()
        subtitleLabel.text = L("home.ai_banner.desc")
        subtitleLabel.font = .systemFont(ofSize: 14, weight: .regular)
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.8)
        subtitleLabel.numberOfLines = 0

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.translatesAutoresizingMaskIntoConstraints = false
        aiWriterBanner.addSubview(textStack)
        NSLayoutConstraint.activate([
            textStack.topAnchor.constraint(equalTo: aiWriterBanner.topAnchor, constant: 20),
            textStack.leadingAnchor.constraint(equalTo: aiWriterBanner.leadingAnchor, constant: 20),
            textStack.trailingAnchor.constraint(equalTo: aiWriterBanner.trailingAnchor, constant: -20),
            textStack.bottomAnchor.constraint(equalTo: aiWriterBanner.bottomAnchor, constant: -20),
        ])

        // Tap gesture
        let tap = UITapGestureRecognizer(target: self, action: #selector(aiWriterBannerTapped))
        aiWriterBanner.addGestureRecognizer(tap)
        aiWriterBanner.isUserInteractionEnabled = true

        // Store gradient layer for resizing
        aiWriterBanner.tag = 9999
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let gradientLayer = aiWriterBanner.layer.sublayers?.first as? CAGradientLayer {
            gradientLayer.frame = aiWriterBanner.bounds
        }
        if let gradientLayer = pasteGuideBanner.layer.sublayers?.first as? CAGradientLayer {
            gradientLayer.frame = pasteGuideBanner.bounds
        }

        // planCardTopLine + usageBgGradient resize (width change only)
        let currentPlanCardWidth = planCard.bounds.width
        if currentPlanCardWidth != lastPlanCardWidth && currentPlanCardWidth > 0 {
            lastPlanCardWidth = currentPlanCardWidth

            CATransaction.begin()
            CATransaction.setDisableActions(true)

            planCardTopLine.frame = CGRect(x: 0, y: 0, width: currentPlanCardWidth, height: 3)
            if let maskLayer = planCardTopLine.mask as? CAShapeLayer {
                let maskRect = CGRect(x: 0, y: 0, width: currentPlanCardWidth, height: 3)
                maskLayer.frame = maskRect
                maskLayer.path = UIBezierPath(
                    roundedRect: maskRect,
                    byRoundingCorners: [.topLeft, .topRight],
                    cornerRadii: CGSize(width: 1.5, height: 1.5)
                ).cgPath
            }

            let usageBounds = usageContainer.bounds
            if usageBounds.width > 0 && usageBounds.height > 0 {
                usageBgGradient.frame = usageBounds
            }

            // Premium 타일 topLine gradient 리사이즈
            if !premiumTilesStack.isHidden {
                updateTileTopLines()
            }

            // Upgrade button gradient + shimmer frame
            if !proLinkButton.isHidden,
               upgradeGradientContainer.bounds.width > 0 {
                let bounds = upgradeGradientContainer.bounds
                if let bgGradient = upgradeGradientContainer.layer.sublayers?.first as? CAGradientLayer {
                    bgGradient.frame = bounds
                }
                upgradeShimmerLayer.frame = bounds
                startUpgradeShimmer()
            }

            CATransaction.commit()
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        updatePlanCard()
        updateBannerColors()

        let usageBounds = usageContainer.bounds
        if !usageBgGradient.isHidden && usageBounds.width > 0 && usageBounds.height > 0 {
            usageBgGradient.frame = usageBounds
        }

        CATransaction.commit()
    }

    @objc private func aiWriterBannerTapped() {
        tabBarController?.selectedIndex = 1
    }

    private func buildPasteGuideBanner() {
        pasteGuideBanner.layer.cornerRadius = AppRadius.md
        pasteGuideBanner.clipsToBounds = true

        let gradientLayer = CAGradientLayer()
        gradientLayer.colors = [
            UIColor(red: 0.0, green: 0.808, blue: 0.706, alpha: 1).cgColor,
            UIColor(red: 0.0, green: 0.624, blue: 0.576, alpha: 1).cgColor,
        ]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        gradientLayer.frame = CGRect(x: 0, y: 0, width: 1000, height: 200)
        pasteGuideBanner.layer.insertSublayer(gradientLayer, at: 0)

        let decorCircle = UIView()
        decorCircle.backgroundColor = UIColor.white.withAlphaComponent(0.1)
        decorCircle.layer.cornerRadius = 50
        decorCircle.translatesAutoresizingMaskIntoConstraints = false
        pasteGuideBanner.addSubview(decorCircle)
        NSLayoutConstraint.activate([
            decorCircle.widthAnchor.constraint(equalToConstant: 100),
            decorCircle.heightAnchor.constraint(equalToConstant: 100),
            decorCircle.topAnchor.constraint(equalTo: pasteGuideBanner.topAnchor, constant: -30),
            decorCircle.trailingAnchor.constraint(equalTo: pasteGuideBanner.trailingAnchor, constant: 30),
        ])

        let titleLabel = UILabel()
        titleLabel.text = L("home.paste_guide_banner.title")
        titleLabel.font = .systemFont(ofSize: 18, weight: .bold)
        titleLabel.textColor = .white

        let subtitleLabel = UILabel()
        subtitleLabel.text = L("home.paste_guide_banner.desc")
        subtitleLabel.font = .systemFont(ofSize: 14, weight: .regular)
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.8)
        subtitleLabel.numberOfLines = 0

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.translatesAutoresizingMaskIntoConstraints = false
        pasteGuideBanner.addSubview(textStack)
        NSLayoutConstraint.activate([
            textStack.topAnchor.constraint(equalTo: pasteGuideBanner.topAnchor, constant: 20),
            textStack.leadingAnchor.constraint(equalTo: pasteGuideBanner.leadingAnchor, constant: 20),
            textStack.trailingAnchor.constraint(equalTo: pasteGuideBanner.trailingAnchor, constant: -20),
            textStack.bottomAnchor.constraint(equalTo: pasteGuideBanner.bottomAnchor, constant: -20),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(pasteGuideBannerTapped))
        pasteGuideBanner.addGestureRecognizer(tap)
        pasteGuideBanner.isUserInteractionEnabled = true

        pasteGuideBanner.tag = 9998
    }

    @objc private func pasteGuideBannerTapped() {
        let vc = PasteGuideViewController()
        navigationController?.pushViewController(vc, animated: true)
    }

    // MARK: - 4. Weekly Activity Card

    // MARK: - Calibration Card

    private func buildCalibrationCard() -> UIView {
        let card = UIView()
        card.backgroundColor = AppColors.card
        card.layer.cornerRadius = AppRadius.md
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = 0.06
        card.layer.shadowOffset = CGSize(width: 0, height: 2)
        card.layer.shadowRadius = 8

        let iconView = UIImageView()
        iconView.image = UIImage(named: "TypingAccuracyIcon") ?? UIImage(systemName: "keyboard")
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        calibrationTitleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        calibrationTitleLabel.textColor = AppColors.text

        calibrationDescLabel.font = .systemFont(ofSize: 13)
        calibrationDescLabel.textColor = AppColors.textMuted
        calibrationDescLabel.numberOfLines = 2

        updateCalibrationCardText()

        let textStack = UIStackView(arrangedSubviews: [calibrationTitleLabel, calibrationDescLabel])
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false

        let chevron = UIImageView()
        chevron.image = UIImage(systemName: "chevron.right")
        chevron.tintColor = AppColors.textMuted
        chevron.contentMode = .scaleAspectFit
        chevron.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(iconView)
        card.addSubview(textStack)
        card.addSubview(chevron)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 44),
            iconView.heightAnchor.constraint(equalToConstant: 32),

            textStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            textStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            textStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
            textStack.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -8),

            chevron.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            chevron.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 12),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(calibrationCardTapped))
        card.addGestureRecognizer(tap)
        card.isUserInteractionEnabled = true

        return card
    }

    @objc private func calibrationCardTapped() {
        let vc = CalibrationViewController()
        let nav = UINavigationController(rootViewController: vc)
        present(nav, animated: true)
    }

    private func updateCalibrationCardText() {
        calibrationTitleLabel.text = L("home.typing_accuracy.title")
        calibrationDescLabel.text = L("home.typing_accuracy.desc")
    }

    // MARK: - Activity Card

    private func buildActivityCard() -> UIView {
        let card = UIView()
        card.backgroundColor = AppColors.card
        card.layer.cornerRadius = AppRadius.md
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = 0.04
        card.layer.shadowOffset = CGSize(width: 0, height: 1)
        card.layer.shadowRadius = 3

        let stack = UIStackView()
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor),
        ])

        correctionCountLabel.text = "0"
        translationCountLabel.text = "0"
        clipboardCountLabel.text = "0"
        phrasesCountLabel.text = "0"

        let rows: [(icon: String, color: UIColor, title: String, subtitle: String, valueLabel: UILabel, action: Selector, isCustomImage: Bool)] = [
            ("CorrectionIcon", AppColors.orange, L("home.stat.corrections"), L("home.stat.this_week"), correctionCountLabel, #selector(correctionCardTapped), true),
            ("TranslationIcon", AppColors.accent, L("home.stat.translations"), L("home.stat.this_week"), translationCountLabel, #selector(translationCardTapped), true),
            ("ClipboardIcon", AppColors.green, L("home.stat.clipboard"), L("home.stat.saved"), clipboardCountLabel, #selector(clipboardCardTapped), true),
            ("PhrasesIcon", AppColors.pink, L("home.stat.phrases"), L("home.stat.saved"), phrasesCountLabel, #selector(phrasesCardTapped), true),
        ]

        for (i, row) in rows.enumerated() {
            let rowView = makeActivityRow(
                icon: row.icon,
                color: row.color,
                title: row.title,
                subtitle: row.subtitle,
                valueLabel: row.valueLabel,
                action: row.action,
                isCustomImage: row.isCustomImage
            )
            stack.addArrangedSubview(rowView)

            if i < rows.count - 1 {
                let divider = UIView()
                divider.backgroundColor = AppColors.border
                divider.translatesAutoresizingMaskIntoConstraints = false
                divider.heightAnchor.constraint(equalToConstant: 0.5).isActive = true

                let dividerWrapper = UIView()
                divider.translatesAutoresizingMaskIntoConstraints = false
                dividerWrapper.addSubview(divider)
                NSLayoutConstraint.activate([
                    divider.topAnchor.constraint(equalTo: dividerWrapper.topAnchor),
                    divider.leadingAnchor.constraint(equalTo: dividerWrapper.leadingAnchor, constant: 16),
                    divider.trailingAnchor.constraint(equalTo: dividerWrapper.trailingAnchor, constant: -16),
                    divider.bottomAnchor.constraint(equalTo: dividerWrapper.bottomAnchor),
                    divider.heightAnchor.constraint(equalToConstant: 0.5),
                ])
                stack.addArrangedSubview(dividerWrapper)
            }
        }

        return card
    }

    private func makeActivityRow(icon: String, color: UIColor, title: String, subtitle: String, valueLabel: UILabel, action: Selector, isCustomImage: Bool = false) -> UIView {
        let container = UIView()
        container.isUserInteractionEnabled = true
        let tap = UITapGestureRecognizer(target: self, action: action)
        container.addGestureRecognizer(tap)

        // Icon area (40x40 with colored background)
        let iconBg = UIView()
        iconBg.backgroundColor = UIColor { traitCollection in
            if traitCollection.userInterfaceStyle == .dark {
                return UIColor(red: 44/255, green: 44/255, blue: 46/255, alpha: 1.0)
            } else {
                return UIColor(red: 242/255, green: 243/255, blue: 245/255, alpha: 1.0)
            }
        }
        iconBg.layer.cornerRadius = 12
        iconBg.translatesAutoresizingMaskIntoConstraints = false

        let iconImage: UIImageView
        if isCustomImage {
            iconImage = UIImageView(image: UIImage(named: icon))
        } else {
            iconImage = UIImageView(image: UIImage(systemName: icon))
            iconImage.tintColor = color
        }
        iconImage.contentMode = .scaleAspectFit
        iconImage.translatesAutoresizingMaskIntoConstraints = false
        iconBg.addSubview(iconImage)
        NSLayoutConstraint.activate([
            iconImage.centerXAnchor.constraint(equalTo: iconBg.centerXAnchor),
            iconImage.centerYAnchor.constraint(equalTo: iconBg.centerYAnchor),
            iconImage.widthAnchor.constraint(equalToConstant: 24),
            iconImage.heightAnchor.constraint(equalToConstant: 24),
        ])

        // Title + subtitle stack
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 15, weight: .regular)
        titleLabel.textColor = AppColors.text

        let subtitleLabel = UILabel()
        subtitleLabel.text = subtitle
        subtitleLabel.font = .systemFont(ofSize: 12, weight: .regular)
        subtitleLabel.textColor = AppColors.textMuted

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 2

        // Value label
        valueLabel.font = .systemFont(ofSize: 17, weight: .bold)
        valueLabel.textColor = AppColors.text
        valueLabel.textAlignment = .right
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)

        // Chevron
        let chevronLabel = UILabel()
        chevronLabel.text = "\u{203A}"
        chevronLabel.font = .systemFont(ofSize: 20, weight: .regular)
        chevronLabel.textColor = AppColors.textMuted
        chevronLabel.setContentHuggingPriority(.required, for: .horizontal)

        // Horizontal layout
        iconBg.translatesAutoresizingMaskIntoConstraints = false
        textStack.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        chevronLabel.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(iconBg)
        container.addSubview(textStack)
        container.addSubview(valueLabel)
        container.addSubview(chevronLabel)

        NSLayoutConstraint.activate([
            // Icon
            iconBg.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            iconBg.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            iconBg.widthAnchor.constraint(equalToConstant: 40),
            iconBg.heightAnchor.constraint(equalToConstant: 40),

            // Text
            textStack.leadingAnchor.constraint(equalTo: iconBg.trailingAnchor, constant: 12),
            textStack.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            // Value
            valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: textStack.trailingAnchor, constant: 8),
            valueLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            // Chevron
            chevronLabel.leadingAnchor.constraint(equalTo: valueLabel.trailingAnchor, constant: 8),
            chevronLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            chevronLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            // Row height
            container.heightAnchor.constraint(equalToConstant: 64),
        ])

        return container
    }

    // MARK: - Actions

    private func startUpgradeShimmer() {
        guard !proLinkButton.isHidden else { return }
        guard upgradeShimmerLayer.animation(forKey: "shimmerAnim") == nil else { return }
        guard upgradeGradientContainer.bounds.width > 0 else { return }

        let bounds = upgradeGradientContainer.bounds

        if let bgGradient = upgradeGradientContainer.layer.sublayers?.first as? CAGradientLayer {
            bgGradient.frame = bounds
        }
        upgradeShimmerLayer.frame = bounds

        let anim = CABasicAnimation(keyPath: "transform.translation.x")
        anim.fromValue = -bounds.width
        anim.toValue = bounds.width
        anim.duration = 3.0
        anim.repeatCount = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        upgradeShimmerLayer.add(anim, forKey: "shimmerAnim")
    }

    private func stopUpgradeShimmer() {
        upgradeShimmerLayer.removeAnimation(forKey: "shimmerAnim")
    }

    @objc private func subscribeTapped() {
        let paywallVC = PaywallViewController()
        paywallVC.modalPresentationStyle = .pageSheet
        present(paywallVC, animated: true)
    }

    @objc private func rewardCorrectionTapped() {
        presentRewardedAds(mode: .correction)
    }

    @objc private func rewardTranslationTapped() {
        presentRewardedAds(mode: .translation)
    }

    @objc private func correctionCardTapped() {
        if !SubscriptionStatus.shared.isPro && DailyUsageManager.shared.remainingCorrections <= 0 {
            presentRewardedAds(mode: .correction)
        } else {
            navigateToHistory(filter: .correction)
        }
    }

    @objc private func translationCardTapped() {
        if !SubscriptionStatus.shared.isPro && DailyUsageManager.shared.remainingTranslations <= 0 {
            presentRewardedAds(mode: .translation)
        } else {
            navigateToHistory(filter: .translation)
        }
    }

    @objc private func clipboardCardTapped() {
        navigateToHistory(filter: .clipboard)
    }

    @objc private func phrasesCardTapped() {
        navigateToHistory(filter: nil)
    }

    private func presentRewardedAds(mode: RewardMode) {
        if DailyUsageManager.shared.canWatchRewardedAd(for: mode) {
            let rewardVC = RewardedAdsViewController(mode: mode)
            rewardVC.modalPresentationStyle = .fullScreen
            present(rewardVC, animated: true)
        } else {
            let paywallVC = PaywallViewController()
            paywallVC.modalPresentationStyle = .pageSheet
            present(paywallVC, animated: true)
        }
    }

    private func navigateToHistory(filter: HistoryType?) {
        guard let tabBar = tabBarController else { return }
        tabBar.selectedIndex = 2
        if let nav = tabBar.viewControllers?[2] as? UINavigationController,
           let historyVC = nav.viewControllers.first as? HistoryViewController {
            historyVC.selectFilter(filter)
        }
    }

    // MARK: - Notifications

    @objc private func handleHistoryChange() {
        refreshStats()
    }

    @objc private func handleAppWillEnterForeground() {
        StatsManager.shared.checkAndResetWeeklyStats()
        refreshStats()
        startUpgradeShimmer()
    }

    @objc private func handleLanguageChange() {
        navigationItem.title = L("home.title")
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        planCard.subviews.forEach { $0.removeFromSuperview() }
        planCard.layer.sublayers?.removeAll()
        // proLinkButton 내부 서브뷰/레이어 정리 (rebuild 시 중복 방지)
        proLinkButton.subviews.forEach { $0.removeFromSuperview() }
        proLinkButton.layer.sublayers?.removeAll()
        stopUpgradeShimmer()
        aiWriterBanner.subviews.forEach { $0.removeFromSuperview() }
        aiWriterBanner.layer.sublayers?.removeAll()
        pasteGuideBanner.subviews.forEach { $0.removeFromSuperview() }
        pasteGuideBanner.layer.sublayers?.removeAll()
        corrTrackLayer.removeFromSuperlayer()
        corrProgressLayer.removeFromSuperlayer()
        transTrackLayer.removeFromSuperlayer()
        transProgressLayer.removeFromSuperlayer()

        // planCardTopLine, usageBgGradient removed by sublayers?.removeAll()
        // Reset width so viewDidLayoutSubviews re-creates frame/mask
        lastPlanCardWidth = 0

        buildContent()
        refreshStats()
    }

    @objc private func handleSubscriptionChange() {
        refreshStats()
    }

    // MARK: - Data Refresh

    private func refreshStats() {
        let stats = StatsManager.shared

        // Date label
        updateDateLabel()

        // Greeting label
        let greeting = timeBasedGreeting()
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = 1.3
        greetingLabel.attributedText = NSAttributedString(
            string: greeting,
            attributes: [
                .font: UIFont.systemFont(ofSize: 26, weight: .bold),
                .foregroundColor: AppColors.text,
                .paragraphStyle: paragraphStyle,
            ]
        )

        // Plan card update
        updatePlanCard()

        // Banner gradient tier colors
        updateBannerColors()

        // Weekly stats
        correctionCountLabel.text = "\(stats.weeklyCorrections)"
        translationCountLabel.text = "\(stats.weeklyTranslations)"

        // Clipboard items count — HistoryManager 기반
        let clipboardCount = HistoryManager.shared.totalCount(ofType: .clipboard)
        clipboardCountLabel.text = "\(clipboardCount)"

        // Saved phrases count — SavedPhrasesManager 기반
        let phrasesCount = SavedPhrasesManager.shared.getPhrases().count
        phrasesCountLabel.text = "\(phrasesCount)"

        // 캐시 업데이트
        cachedCorrectionCount = stats.weeklyCorrections
        cachedTranslationCount = stats.weeklyTranslations
        cachedClipboardCount = clipboardCount
        cachedPhrasesCount = phrasesCount
    }

    private func updateDateLabel() {
        let now = Date()
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale.current
        timeFormatter.dateFormat = "a h:mm"

        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = Locale.current
        weekdayFormatter.dateFormat = "EEEE"

        let timeString = timeFormatter.string(from: now)
        let weekdayString = weekdayFormatter.string(from: now)
        dateLabel.text = "\(timeString) \u{00B7} \(weekdayString)"
    }

    private func timeBasedGreeting() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 {
            return L("home.greeting.morning")
        } else if hour < 18 {
            return L("home.greeting.afternoon")
        } else {
            return L("home.greeting.evening")
        }
    }

    // MARK: - Animations

    private var hasAnimated = false

    private func animateEntrance() {
        guard !hasAnimated else { return }
        hasAnimated = true

        let animatableViews = contentStack.arrangedSubviews
        for v in animatableViews {
            v.alpha = 0
            v.transform = CGAffineTransform(translationX: 0, y: 20)
        }

        for (i, v) in animatableViews.enumerated() {
            UIView.animate(
                withDuration: 0.4,
                delay: Double(i) * 0.05,
                options: .curveEaseOut
            ) {
                v.alpha = 1
                v.transform = .identity
            }
        }

        // Count-up animation for stat labels
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.animateCountUp()
        }
    }

    private func animateCountUp() {
        // 캐시된 값 사용 — 중복 디코딩 제거
        animateLabel(correctionCountLabel, to: cachedCorrectionCount)
        animateLabel(translationCountLabel, to: cachedTranslationCount)
        animateLabel(clipboardCountLabel, to: cachedClipboardCount)
        animateLabel(phrasesCountLabel, to: cachedPhrasesCount)
    }

    private func animateLabel(_ label: UILabel, to target: Int) {
        guard target > 0 else {
            label.text = "0"
            return
        }
        label.text = "0"
        let duration: Double = 1.2
        let steps = min(target, 60)
        let interval = duration / Double(steps)

        for step in 1...steps {
            let delay = interval * Double(step)
            // easeOut: progress accelerates early, decelerates late
            let progress = 1.0 - pow(1.0 - Double(step) / Double(steps), 3.0)
            let value = Int(round(Double(target) * progress))
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak label] in
                label?.text = "\(value)"
            }
        }
    }
}
