import UIKit

class HomeViewController: UIViewController {

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    // MARK: - Greeting

    private let dateLabel = UILabel()
    private let greetingLabel = UILabel()

    // MARK: - Plan Card

    private let planCard = UIView()
    private let planBadgeLabel = UILabel()
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

    // MARK: - AI Writer Banner

    private let aiWriterBanner = UIView()

    // MARK: - Weekly Activity

    private let correctionCountLabel = UILabel()
    private let translationCountLabel = UILabel()
    private let clipboardCountLabel = UILabel()
    private let phrasesCountLabel = UILabel()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColors.bg
        setupNavigation()
        setupScrollView()
        buildContent()
        NotificationCenter.default.addObserver(self, selector: #selector(handleHistoryChange), name: .historyDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleLanguageChange), name: .languageDidChange, object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        StatsManager.shared.checkAndResetWeeklyStats()
        refreshStats()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        animateEntrance()
    }

    // MARK: - Setup

    private func setupNavigation() {
        title = L("home.title")
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

        // Plan badge (pill shape)
        planBadgeLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        planBadgeLabel.textColor = AppColors.accent
        planBadgeLabel.backgroundColor = AppColors.accentSoft
        planBadgeLabel.textAlignment = .center
        planBadgeLabel.layer.cornerRadius = 20
        planBadgeLabel.clipsToBounds = true
        planBadgeLabel.translatesAutoresizingMaskIntoConstraints = false

        let badgeWrapper = UIView()
        badgeWrapper.addSubview(planBadgeLabel)
        NSLayoutConstraint.activate([
            planBadgeLabel.topAnchor.constraint(equalTo: badgeWrapper.topAnchor),
            planBadgeLabel.leadingAnchor.constraint(equalTo: badgeWrapper.leadingAnchor),
            planBadgeLabel.bottomAnchor.constraint(equalTo: badgeWrapper.bottomAnchor),
            planBadgeLabel.heightAnchor.constraint(equalToConstant: 32),
        ])
        // Intrinsic content size + padding
        planBadgeLabel.setContentHuggingPriority(.required, for: .horizontal)
        planBadgeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        topRow.addArrangedSubview(badgeWrapper)

        // Pro link button
        proLinkButton.setTitle("Pro \(L("home.plan.subscribe")) \u{2192}", for: .normal)
        proLinkButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        proLinkButton.setTitleColor(AppColors.accent, for: .normal)
        proLinkButton.addTarget(self, action: #selector(subscribeTapped), for: .touchUpInside)
        topRow.addArrangedSubview(proLinkButton)

        mainStack.addArrangedSubview(topRow)

        // Usage area: grey background with two circles
        let usageContainer = UIView()
        usageContainer.backgroundColor = UIColor { $0.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.06)
            : UIColor(red: 0.965, green: 0.965, blue: 0.975, alpha: 1)
        }
        usageContainer.layer.cornerRadius = AppRadius.sm

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
        let circlesStack = UIStackView(arrangedSubviews: [corrColumn, transColumn])
        circlesStack.axis = .horizontal
        circlesStack.spacing = 32
        circlesStack.alignment = .center
        circlesStack.distribution = .equalCentering
        circlesStack.translatesAutoresizingMaskIntoConstraints = false

        usageContainer.addSubview(circlesStack)
        NSLayoutConstraint.activate([
            circlesStack.topAnchor.constraint(equalTo: usageContainer.topAnchor, constant: 16),
            circlesStack.centerXAnchor.constraint(equalTo: usageContainer.centerXAnchor),
            circlesStack.bottomAnchor.constraint(equalTo: usageContainer.bottomAnchor, constant: -16),
        ])

        mainStack.addArrangedSubview(usageContainer)

        // Reward Ad Buttons (free tier only, conditional per mode)
        configureRewardButton(rewardCorrectionAdButton, action: #selector(rewardCorrectionTapped))
        configureRewardButton(rewardTranslationAdButton, action: #selector(rewardTranslationTapped))

        mainStack.addArrangedSubview(rewardCorrectionAdButton)
        mainStack.addArrangedSubview(rewardTranslationAdButton)
    }

    private func configureRewardButton(_ button: UIButton, action: Selector) {
        button.backgroundColor = AppColors.accentSoft
        button.layer.cornerRadius = AppRadius.sm
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        button.setTitleColor(AppColors.accent, for: .normal)
        button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)

        let playIcon = UIImage(systemName: "play.fill")?.withConfiguration(
            UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        )
        button.setImage(playIcon, for: .normal)
        button.tintColor = AppColors.accent
        button.semanticContentAttribute = .forceLeftToRight
        button.imageEdgeInsets = UIEdgeInsets(top: 0, left: -4, bottom: 0, right: 4)
        button.addTarget(self, action: action, for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 40).isActive = true
    }

    private func setupCircle(container: UIView, trackLayer: inout CAShapeLayer, progressLayer: inout CAShapeLayer, used: Int, total: Int, color: UIColor) {
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
        let trackColor = UIColor { $0.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.1)
            : UIColor(red: 0.910, green: 0.910, blue: 0.929, alpha: 1)
        }
        trackLayer.strokeColor = trackColor.cgColor
        trackLayer.fillColor = UIColor.clear.cgColor
        trackLayer.lineWidth = lineWidth
        trackLayer.lineCap = .round
        container.layer.addSublayer(trackLayer)

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

        container.layer.addSublayer(progressLayer)
    }

    private func updatePlanCard() {
        let tier = SubscriptionStatus.shared.currentTier
        let usage = DailyUsageManager.shared

        // Badge
        switch tier {
        case .free:
            planBadgeLabel.text = "  Free Plan  "
            proLinkButton.isHidden = false
        case .pro:
            planBadgeLabel.text = "  Pro Plan  "
            proLinkButton.isHidden = true
            rewardCorrectionAdButton.isHidden = true
            rewardTranslationAdButton.isHidden = true
        case .premium:
            planBadgeLabel.text = "  Premium Plan  "
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

        if tier == .premium && FeatureGate.shared.isPremiumUnlimited {
            corrCenterLabel.text = L("home.plan.unlimited")
            corrCenterLabel.font = .systemFont(ofSize: 20, weight: .bold)
            transCenterLabel.text = L("home.plan.unlimited")
            transCenterLabel.font = .systemFont(ofSize: 20, weight: .bold)
            setupCircle(container: corrProgressContainer, trackLayer: &corrTrackLayer, progressLayer: &corrProgressLayer, used: 1, total: 1, color: AppColors.green)
            setupCircle(container: transProgressContainer, trackLayer: &transTrackLayer, progressLayer: &transProgressLayer, used: 1, total: 1, color: AppColors.green)
            corrProgressLayer.strokeColor = AppColors.green.cgColor
            transProgressLayer.strokeColor = AppColors.green.cgColor
        } else {
            corrCenterLabel.text = "\(corrUsed)/\(corrTotal)"
            corrCenterLabel.font = .systemFont(ofSize: 15, weight: .bold)
            transCenterLabel.text = "\(transUsed)/\(transTotal)"
            transCenterLabel.font = .systemFont(ofSize: 15, weight: .bold)
            setupCircle(container: corrProgressContainer, trackLayer: &corrTrackLayer, progressLayer: &corrProgressLayer, used: corrUsed, total: corrTotal, color: AppColors.orange)
            setupCircle(container: transProgressContainer, trackLayer: &transTrackLayer, progressLayer: &transProgressLayer, used: transUsed, total: transTotal, color: AppColors.accent)
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
        // Resize gradient layer of AI Writer banner
        if let gradientLayer = aiWriterBanner.layer.sublayers?.first as? CAGradientLayer {
            gradientLayer.frame = aiWriterBanner.bounds
        }
    }

    @objc private func aiWriterBannerTapped() {
        tabBarController?.selectedIndex = 1
    }

    // MARK: - 4. Weekly Activity Card

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

        let rows: [(icon: String, color: UIColor, title: String, subtitle: String, valueLabel: UILabel, action: Selector)] = [
            ("pencil", AppColors.orange, L("home.stat.corrections"), L("home.stat.this_week"), correctionCountLabel, #selector(correctionCardTapped)),
            ("globe", AppColors.accent, L("home.stat.translations"), L("home.stat.this_week"), translationCountLabel, #selector(translationCardTapped)),
            ("doc.on.clipboard", AppColors.green, L("home.stat.clipboard"), L("home.stat.saved"), clipboardCountLabel, #selector(clipboardCardTapped)),
            ("bookmark.fill", AppColors.pink, L("home.stat.phrases"), L("home.stat.saved"), phrasesCountLabel, #selector(phrasesCardTapped)),
        ]

        for (i, row) in rows.enumerated() {
            let rowView = makeActivityRow(
                icon: row.icon,
                color: row.color,
                title: row.title,
                subtitle: row.subtitle,
                valueLabel: row.valueLabel,
                action: row.action
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

    private func makeActivityRow(icon: String, color: UIColor, title: String, subtitle: String, valueLabel: UILabel, action: Selector) -> UIView {
        let container = UIView()
        container.isUserInteractionEnabled = true
        let tap = UITapGestureRecognizer(target: self, action: action)
        container.addGestureRecognizer(tap)

        // Icon area (40x40 with colored background)
        let iconBg = UIView()
        iconBg.backgroundColor = color.withAlphaComponent(0.12)
        iconBg.layer.cornerRadius = 12
        iconBg.translatesAutoresizingMaskIntoConstraints = false

        let iconImage = UIImageView(image: UIImage(systemName: icon))
        iconImage.tintColor = color
        iconImage.contentMode = .scaleAspectFit
        iconImage.translatesAutoresizingMaskIntoConstraints = false
        iconBg.addSubview(iconImage)
        NSLayoutConstraint.activate([
            iconImage.centerXAnchor.constraint(equalTo: iconBg.centerXAnchor),
            iconImage.centerYAnchor.constraint(equalTo: iconBg.centerYAnchor),
            iconImage.widthAnchor.constraint(equalToConstant: 18),
            iconImage.heightAnchor.constraint(equalToConstant: 18),
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

    @objc private func handleLanguageChange() {
        title = L("home.title")
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        planCard.subviews.forEach { $0.removeFromSuperview() }
        planCard.layer.sublayers?.removeAll()
        aiWriterBanner.subviews.forEach { $0.removeFromSuperview() }
        aiWriterBanner.layer.sublayers?.removeAll()
        corrTrackLayer.removeFromSuperlayer()
        corrProgressLayer.removeFromSuperlayer()
        transTrackLayer.removeFromSuperlayer()
        transProgressLayer.removeFromSuperlayer()
        buildContent()
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

        // Weekly stats
        correctionCountLabel.text = "\(stats.weeklyCorrections)"
        translationCountLabel.text = "\(stats.weeklyTranslations)"

        // Clipboard items count
        let clipboardData = UserDefaults(suiteName: AppConstants.appGroupIdentifier)?.data(forKey: AppConstants.UserDefaultsKeys.clipboardHistory)
        let clipboardCount: Int
        if let data = clipboardData, let items = try? JSONDecoder().decode([ClipboardItem].self, from: data) {
            clipboardCount = items.count
        } else {
            clipboardCount = 0
        }
        clipboardCountLabel.text = "\(clipboardCount)"

        // Saved phrases count
        let phrasesData = UserDefaults(suiteName: AppConstants.appGroupIdentifier)?.data(forKey: AppConstants.UserDefaultsKeys.savedPhrases)
        let phrasesCount: Int
        if let data = phrasesData, let items = try? JSONDecoder().decode([String].self, from: data) {
            phrasesCount = items.count
        } else {
            phrasesCount = 0
        }
        phrasesCountLabel.text = "\(phrasesCount)"
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
        let stats = StatsManager.shared
        animateLabel(correctionCountLabel, to: stats.weeklyCorrections)
        animateLabel(translationCountLabel, to: stats.weeklyTranslations)

        let clipboardData = UserDefaults(suiteName: AppConstants.appGroupIdentifier)?.data(forKey: AppConstants.UserDefaultsKeys.clipboardHistory)
        let clipCount: Int
        if let data = clipboardData, let items = try? JSONDecoder().decode([ClipboardItem].self, from: data) {
            clipCount = items.count
        } else {
            clipCount = 0
        }
        animateLabel(clipboardCountLabel, to: clipCount)

        let phrasesData = UserDefaults(suiteName: AppConstants.appGroupIdentifier)?.data(forKey: AppConstants.UserDefaultsKeys.savedPhrases)
        let phrasesCount: Int
        if let data = phrasesData, let items = try? JSONDecoder().decode([String].self, from: data) {
            phrasesCount = items.count
        } else {
            phrasesCount = 0
        }
        animateLabel(phrasesCountLabel, to: phrasesCount)
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
