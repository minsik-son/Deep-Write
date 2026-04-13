import UIKit

class RewardedAdsViewController: UIViewController, AdManagerDelegate {

    // MARK: - Properties

    var onDismiss: (() -> Void)?
    private let mode: RewardMode
    private var maxAds: Int {
        mode == .compose ? FeatureGate.shared.maxDailyComposeAds : FeatureGate.shared.maxDailyRewardedAds
    }
    private var bonus: Int {
        mode == .compose ? FeatureGate.shared.composeRewardPerAd : FeatureGate.shared.rewardedAdBonusCount
    }

    // MARK: - UI Elements

    private let closeButton: UIButton = {
        let btn = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        btn.setImage(UIImage(systemName: "xmark", withConfiguration: config), for: .normal)
        btn.tintColor = AppColors.textSub
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let iconContainer: UIView = {
        let v = UIView()
        v.backgroundColor = AppColors.tierAccent.withAlphaComponent(0.12)
        v.layer.cornerRadius = 48
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let iconView: UIImageView = {
        let iv = UIImageView()
        let config = UIImage.SymbolConfiguration(pointSize: 40, weight: .medium)
        iv.image = UIImage(systemName: "gift.fill", withConfiguration: config)
        iv.tintColor = AppColors.tierAccent
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 24, weight: .bold)
        label.textColor = AppColors.text
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let descLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 15)
        label.textColor = AppColors.textSub
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let dotsContainer: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 10
        sv.alignment = .center
        sv.distribution = .equalCentering
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private let progressLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = AppColors.textSub
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let ctaButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        btn.setTitleColor(.white, for: .normal)
        btn.backgroundColor = AppColors.tierAccent
        btn.layer.cornerRadius = 14
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let closeTextButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle(L("reward.cta_close"), for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        btn.setTitleColor(AppColors.textSub, for: .normal)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let feedbackLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .white
        label.textAlignment = .center
        label.backgroundColor = AppColors.green
        label.layer.cornerRadius = 12
        label.clipsToBounds = true
        label.alpha = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private var dotViews: [UIView] = []
    private var isDismissing = false
    private var isAdInProgress = false

    /// 오늘의 광고 한도를 진짜 다 채웠는지 (daily cap 도달)
    private var isDailyQuotaExhausted: Bool {
        if mode == .compose {
            return DailyUsageManager.shared.composeRewardedAdCount >= FeatureGate.shared.maxDailyComposeAds
        } else {
            return DailyUsageManager.shared.rewardedAdCount(for: mode) >= FeatureGate.shared.maxDailyRewardedAds
        }
    }

    // MARK: - Init

    init(mode: RewardMode) {
        self.mode = mode
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColors.bg
        setupLayout()
        updateUI()
        AdManager.shared.delegate = self
        AdManager.shared.loadRewardedAd()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        onDismiss?()
    }

    // MARK: - Layout

    private func setupLayout() {
        // Close button (top-right)
        view.addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            closeButton.widthAnchor.constraint(equalToConstant: 32),
            closeButton.heightAnchor.constraint(equalToConstant: 32),
        ])
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        // Center content stack
        let centerStack = UIStackView(arrangedSubviews: [iconContainer, titleLabel, descLabel, dotsContainer, progressLabel])
        centerStack.axis = .vertical
        centerStack.alignment = .center
        centerStack.spacing = 16
        centerStack.setCustomSpacing(24, after: iconContainer)
        centerStack.setCustomSpacing(8, after: titleLabel)
        centerStack.setCustomSpacing(24, after: descLabel)
        centerStack.setCustomSpacing(8, after: dotsContainer)
        centerStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(centerStack)

        // Icon inside container
        iconContainer.addSubview(iconView)
        NSLayoutConstraint.activate([
            iconContainer.widthAnchor.constraint(equalToConstant: 96),
            iconContainer.heightAnchor.constraint(equalToConstant: 96),
            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
        ])

        // Center the stack vertically (slightly above center)
        NSLayoutConstraint.activate([
            centerStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            centerStack.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),
            centerStack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            centerStack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),
        ])

        // Dot indicators
        setupDots()

        // Bottom buttons
        view.addSubview(ctaButton)
        view.addSubview(closeTextButton)
        view.addSubview(feedbackLabel)

        NSLayoutConstraint.activate([
            ctaButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            ctaButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            ctaButton.heightAnchor.constraint(equalToConstant: 54),
            ctaButton.bottomAnchor.constraint(equalTo: closeTextButton.topAnchor, constant: -12),

            closeTextButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            closeTextButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),

            feedbackLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            feedbackLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            feedbackLabel.heightAnchor.constraint(equalToConstant: 44),
            feedbackLabel.bottomAnchor.constraint(equalTo: ctaButton.topAnchor, constant: -16),
        ])

        ctaButton.addTarget(self, action: #selector(watchAdTapped), for: .touchUpInside)
        closeTextButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
    }

    private func setupDots() {
        for _ in 0..<maxAds {
            let dot = UIView()
            dot.layer.cornerRadius = 6
            dot.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                dot.widthAnchor.constraint(equalToConstant: 12),
                dot.heightAnchor.constraint(equalToConstant: 12),
            ])
            dotsContainer.addArrangedSubview(dot)
            dotViews.append(dot)
        }
    }

    // MARK: - Update UI

    private func updateUI() {
        let watched: Int
        let canWatch: Bool
        if mode == .compose {
            watched = DailyUsageManager.shared.composeRewardedAdCount
            canWatch = DailyUsageManager.shared.canWatchComposeRewardedAd
        } else {
            watched = DailyUsageManager.shared.rewardedAdCount(for: mode)
            canWatch = DailyUsageManager.shared.canWatchRewardedAd(for: mode)
        }

        // Title
        let modeText: String
        switch mode {
        case .correction: modeText = L("reward.mode.correction")
        case .translation: modeText = L("reward.mode.translation")
        case .compose: modeText = L("reward.mode.compose")
        }
        titleLabel.text = String(format: L("reward.title_format"), modeText, bonus)

        // Description
        descLabel.text = String(format: L("reward.desc"), bonus)

        // Dots
        for (i, dot) in dotViews.enumerated() {
            if i < watched {
                dot.backgroundColor = AppColors.tierAccent
            } else {
                dot.backgroundColor = AppColors.border
            }
        }

        // Progress
        progressLabel.text = String(format: L("reward.progress"), watched, maxAds)

        // CTA — 3가지 상태 분기
        if canWatch {
            ctaButton.setTitle(L("reward.cta_watch"), for: .normal)
            ctaButton.backgroundColor = AppColors.tierAccent
            ctaButton.isEnabled = true
        } else if isDailyQuotaExhausted {
            // 진짜 오늘 광고 한도 모두 소진
            ctaButton.setTitle(L("reward.cta_done"), for: .normal)
            ctaButton.backgroundColor = AppColors.textMuted
            ctaButton.isEnabled = false
        } else {
            // 충전 완료, 보너스를 먼저 사용해야 하는 상태
            ctaButton.setTitle(L("reward.charge_complete"), for: .normal)
            ctaButton.backgroundColor = AppColors.textMuted
            ctaButton.isEnabled = false
        }
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func watchAdTapped() {
        guard !isAdInProgress else { return }
        isAdInProgress = true
        ctaButton.isEnabled = false
        AdManager.shared.showRewardedAd(from: self, mode: mode)
    }

    // MARK: - Feedback

    private func showFeedback(_ message: String, isError: Bool = false) {
        feedbackLabel.text = "  \(message)  "
        feedbackLabel.backgroundColor = isError ? .systemRed : AppColors.green
        feedbackLabel.alpha = 0
        feedbackLabel.transform = CGAffineTransform(translationX: 0, y: 10)

        UIView.animate(withDuration: 0.3) {
            self.feedbackLabel.alpha = 1
            self.feedbackLabel.transform = .identity
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            UIView.animate(withDuration: 0.3) {
                self.feedbackLabel.alpha = 0
            }
        }
    }

    // MARK: - AdManagerDelegate

    func adManagerDidRewardUser(_ manager: AdManager) {
        isAdInProgress = false

        // Animate the newly filled dot
        let watched = mode == .compose
            ? DailyUsageManager.shared.composeRewardedAdCount
            : DailyUsageManager.shared.rewardedAdCount(for: mode)
        let dotIndex = watched - 1
        if dotIndex >= 0, dotIndex < dotViews.count {
            let dot = dotViews[dotIndex]
            dot.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
            dot.backgroundColor = AppColors.tierAccent
            UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.8) {
                dot.transform = .identity
            }
        }

        showFeedback(String(format: L("reward.charge_complete_feedback"), bonus))

        // 보상 지급 후 짧은 피드백 보여준 뒤 자동 dismiss
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.autoDismissAfterReward()
        }
    }

    func adManagerDidFailToLoad(_ manager: AdManager) {
        isAdInProgress = false
        ctaButton.isEnabled = true
        updateUI()
        showFeedback(L("reward.ad_failed"), isError: true)
    }

    func adManagerDidDismissAd(_ manager: AdManager) {
        isAdInProgress = false
        ctaButton.isEnabled = true
        updateUI()
    }

    func adManagerReachedDailyLimit(_ manager: AdManager) {
        isAdInProgress = false
        ctaButton.isEnabled = true
        updateUI()
        showFeedback(L("reward.limit_reached"))
    }

    private func autoDismissAfterReward() {
        guard !isDismissing else { return }
        isDismissing = true
        dismiss(animated: true)
    }
}
