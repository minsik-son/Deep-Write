import UIKit

class OnboardingViewController: UIViewController {

    // MARK: - Properties

    private let pageViewController = UIPageViewController(
        transitionStyle: .scroll,
        navigationOrientation: .horizontal
    )

    private var pages: [UIViewController] = []
    private var currentIndex = 0

    private let pageControl: UIPageControl = {
        let pc = UIPageControl()
        pc.numberOfPages = 4
        pc.currentPage = 0
        pc.currentPageIndicatorTintColor = .systemBlue
        pc.pageIndicatorTintColor = .systemGray4
        pc.translatesAutoresizingMaskIntoConstraints = false
        pc.isUserInteractionEnabled = false
        return pc
    }()

    private let ctaButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("시작하기", for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        btn.backgroundColor = .systemBlue
        btn.setTitleColor(.white, for: .normal)
        btn.layer.cornerRadius = 14
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let secondaryButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        btn.setTitleColor(.systemBlue, for: .normal)
        btn.backgroundColor = .clear
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.isHidden = true
        return btn
    }()

    private var secondaryButtonHeightConstraint: NSLayoutConstraint!

    // Setup page state
    private var hasVisitedSettings = false

    // Verification page state
    private var pollingTimer: Timer?
    private var timeoutTimer: Timer?
    private var verificationStatusLabel: UILabel!
    private var verificationPassed = false

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        buildPages()
        setupPageViewController()
        setupBottomControls()
        disableSwipeGesture()
        restoreProgress()
    }

    // MARK: - Page Factory

    private func buildPages() {
        pages = [
            makeWelcomePage(),           // 0
            makeSetupPage(),             // 1
            makeVerificationPage(),      // 2
            makeFeaturesPage(),          // 3
        ]
    }

    // MARK: - Setup

    private func setupPageViewController() {
        addChild(pageViewController)
        view.addSubview(pageViewController.view)
        pageViewController.didMove(toParent: self)
        pageViewController.view.translatesAutoresizingMaskIntoConstraints = false

        if let firstPage = pages.first {
            pageViewController.setViewControllers([firstPage], direction: .forward, animated: false)
        }
    }

    private func setupBottomControls() {
        view.addSubview(pageControl)
        view.addSubview(secondaryButton)
        view.addSubview(ctaButton)

        secondaryButtonHeightConstraint = secondaryButton.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            pageViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            pageViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pageViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pageViewController.view.bottomAnchor.constraint(equalTo: pageControl.topAnchor, constant: -12),

            pageControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pageControl.bottomAnchor.constraint(equalTo: secondaryButton.topAnchor, constant: -12),

            secondaryButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            secondaryButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            secondaryButton.bottomAnchor.constraint(equalTo: ctaButton.topAnchor, constant: -8),
            secondaryButtonHeightConstraint,

            ctaButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            ctaButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            ctaButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            ctaButton.heightAnchor.constraint(equalToConstant: 52),
        ])

        ctaButton.addTarget(self, action: #selector(ctaTapped), for: .touchUpInside)
        secondaryButton.addTarget(self, action: #selector(secondaryTapped), for: .touchUpInside)
    }

    private func disableSwipeGesture() {
        for view in pageViewController.view.subviews {
            if let scrollView = view as? UIScrollView {
                scrollView.isScrollEnabled = false
            }
        }
    }

    private func restoreProgress() {
        let defaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier) ?? UserDefaults.standard
        let savedIndex = min(defaults.integer(forKey: "onboarding_current_page"), pages.count - 1)

        if savedIndex > 0, savedIndex < pages.count {
            currentIndex = savedIndex
            pageViewController.setViewControllers([pages[savedIndex]], direction: .forward, animated: false)
            pageControl.currentPage = savedIndex
        }

        hasVisitedSettings = defaults.bool(forKey: "onboarding_returned_from_settings")
        updateCTAForCurrentPage()
    }

    // MARK: - Navigation

    @objc private func ctaTapped() {
        switch currentIndex {
        case 1:
            if !hasVisitedSettings {
                hasVisitedSettings = true
                let defaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier) ?? UserDefaults.standard
                defaults.set(true, forKey: "onboarding_returned_from_settings")
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
                return
            } else {
                goToPage(2)
                return
            }
        case 2:
            // v6: CTA = 키보드 열기 — warning UI는 유지, keyboard open + recovery polling만
            if let page = pages[safe: 2] {
                for subview in page.view.subviews where subview is UITextField {
                    subview.becomeFirstResponder()
                    break
                }
            }
            checkKeyboardStatus()
            if pollingTimer == nil && !verificationPassed {
                pollingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                    self?.checkKeyboardStatus()
                }
            }
            return
        case 3:
            showPaywallAfterOnboarding()
            return
        default:
            goToPage(currentIndex + 1)
        }
    }

    @objc private func secondaryTapped() {
        switch currentIndex {
        case 1:
            // "다시 설정으로 이동" — 설정 앱 다시 열기
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        case 2:
            // "다시 설정해보기" — Page 1로 돌아가기
            stopPolling()
            // 검증 페이지의 동적 뷰 정리 (fullAccess 경고, 타임아웃 메시지 등)
            if let page = pages[safe: 2] {
                for subview in page.view.subviews where subview.tag == 901 || subview.tag == 902 {
                    subview.removeFromSuperview()
                }
            }
            goToPage(1)
        default:
            break
        }
    }

    private func goToPage(_ index: Int) {
        guard index >= 0, index < pages.count else { return }
        let direction: UIPageViewController.NavigationDirection = index > currentIndex ? .forward : .reverse
        currentIndex = index
        pageViewController.setViewControllers([pages[index]], direction: direction, animated: true)
        pageControl.currentPage = index
        updateCTAForCurrentPage()
        let defaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier) ?? UserDefaults.standard
        defaults.set(index, forKey: "onboarding_current_page")

        if index == 2 {
            startPolling()
        }
    }

    private func updateCTAForCurrentPage() {
        ctaButton.isHidden = false
        pageControl.isHidden = false

        // 보조 버튼 기본 숨김 (height=0으로 공간 제거)
        secondaryButton.isHidden = true
        secondaryButtonHeightConstraint.constant = 0

        switch currentIndex {
        case 0:
            ctaButton.setTitle(L("onboarding.cta.start"), for: .normal)
            ctaButton.isEnabled = true
            ctaButton.backgroundColor = .systemBlue
        case 1:
            ctaButton.setTitle(hasVisitedSettings ? L("onboarding.cta.done_settings") : L("onboarding.cta.go_settings"), for: .normal)
            ctaButton.isEnabled = true
            ctaButton.backgroundColor = .systemBlue
            // 설정에서 돌아온 후: "다시 설정으로 이동" — ctaButton과 같은 크기/구조
            if hasVisitedSettings {
                secondaryButton.setTitle(L("onboarding.cta.reopen_settings"), for: .normal)
                secondaryButton.isHidden = false
                secondaryButtonHeightConstraint.constant = 52
                secondaryButton.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.12)
                secondaryButton.setTitleColor(.systemBlue, for: .normal)
                secondaryButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
                secondaryButton.layer.cornerRadius = 14
            }
        case 2:
            // v4: global CTA 재활용 — 키보드 열기 + 다시 설정해보기
            ctaButton.setTitle(L("onboarding.verify.open_keyboard"), for: .normal)
            ctaButton.isEnabled = true
            ctaButton.backgroundColor = .systemBlue
            // secondary = 다시 설정해보기 (filled style)
            secondaryButton.setTitle(L("onboarding.cta.back_to_settings"), for: .normal)
            secondaryButton.isHidden = false
            secondaryButtonHeightConstraint.constant = 50
            secondaryButton.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.12)
            secondaryButton.layer.cornerRadius = 14
        case 3:
            ctaButton.setTitle(L("onboarding.cta.start"), for: .normal)
            ctaButton.isEnabled = true
            ctaButton.backgroundColor = .systemBlue
        default:
            break
        }
    }

    private func completeOnboarding() {
        let defaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier) ?? UserDefaults.standard
        defaults.set(true, forKey: AppConstants.UserDefaultsKeys.hasCompletedOnboarding)
        defaults.removeObject(forKey: "onboarding_current_page")
        defaults.removeObject(forKey: "onboarding_returned_from_settings")
        dismiss(animated: true)
    }

    private func showPaywallAfterOnboarding() {
        let defaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier) ?? UserDefaults.standard
        defaults.set(true, forKey: AppConstants.UserDefaultsKeys.hasCompletedOnboarding)
        defaults.removeObject(forKey: "onboarding_current_page")
        defaults.removeObject(forKey: "onboarding_returned_from_settings")
        dismiss(animated: true) {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootVC = windowScene.windows.first?.rootViewController else { return }
            let topVC = rootVC.presentedViewController ?? rootVC
            let paywallVC = PaywallViewController()
            paywallVC.modalPresentationStyle = .pageSheet
            topVC.present(paywallVC, animated: true)
        }
    }

    // MARK: - Keyboard Detection

    private func registerForegroundObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func appDidBecomeActive() {
        if currentIndex == 1, hasVisitedSettings {
            updateCTAForCurrentPage()
        }
        // v1 recovery: page 3 foreground 복귀 시 즉시 재확인
        if currentIndex == 2, !verificationPassed {
            checkKeyboardStatus()
        }
    }

    // MARK: - Verification Polling

    private func startPolling() {
        stopPolling()
        verificationPassed = false
        updateCTAForCurrentPage()

        AppGroupManager.shared.removeObject(forKey: AppConstants.UserDefaultsKeys.keyboardFullAccessEnabled)

        verificationStatusLabel?.text = L("onboarding.verify.instruction")
        verificationStatusLabel?.textColor = .secondaryLabel

        pollingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkKeyboardStatus()
        }

        timeoutTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
            self?.handleTimeout()
        }
    }

    private func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        timeoutTimer?.invalidate()
        timeoutTimer = nil
    }

    private func checkKeyboardStatus() {
        let defaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier)
        guard let value = defaults?.object(forKey: AppConstants.UserDefaultsKeys.keyboardFullAccessEnabled) as? Bool else {
            return
        }

        if value {
            showVerificationSuccess()
        } else {
            showFullAccessRequired()
        }
    }

    private func showVerificationSuccess() {
        stopPolling()
        guard !verificationPassed else { return }
        verificationPassed = true

        // 인라인 성공 애니메이션 표시
        guard let page = pages[safe: 2] else { return }

        let successView = SuccessCheckAnimationView()
        successView.translatesAutoresizingMaskIntoConstraints = false
        page.view.addSubview(successView)
        NSLayoutConstraint.activate([
            successView.topAnchor.constraint(equalTo: page.view.topAnchor),
            successView.bottomAnchor.constraint(equalTo: page.view.bottomAnchor),
            successView.leadingAnchor.constraint(equalTo: page.view.leadingAnchor),
            successView.trailingAnchor.constraint(equalTo: page.view.trailingAnchor),
        ])

        successView.playAnimation()

        // 2초 후 features page로 자동 이동
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.goToPage(3)
        }
    }

    private func showFullAccessRequired() {
        // v1 recovery: false 감지 시 warning UI만 — polling 유지하여 true 전환 감지 가능

        guard let page = pages[safe: 2] else { return }

        // secondaryButton 숨김 (settingsButton과 중복 방지)
        secondaryButton.isHidden = true
        secondaryButtonHeightConstraint.constant = 0

        // Remove existing extra views
        for subview in page.view.subviews where subview.tag == 901 || subview.tag == 902 {
            subview.removeFromSuperview()
        }

        verificationStatusLabel?.text = L("onboarding.verify.no_full_access")
        verificationStatusLabel?.textColor = .systemOrange

        let descLabel = UILabel()
        descLabel.text = L("onboarding.verify.full_access_desc")
        descLabel.font = .systemFont(ofSize: 14)
        descLabel.textColor = .secondaryLabel
        descLabel.textAlignment = .center
        descLabel.numberOfLines = 0
        descLabel.translatesAutoresizingMaskIntoConstraints = false
        descLabel.tag = 901

        let settingsButton = UIButton(type: .system)
        settingsButton.setTitle(L("onboarding.verify.go_settings"), for: .normal)
        settingsButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        settingsButton.tag = 902
        settingsButton.addTarget(self, action: #selector(openSettingsFromVerification), for: .touchUpInside)

        page.view.addSubview(descLabel)
        page.view.addSubview(settingsButton)

        NSLayoutConstraint.activate([
            descLabel.topAnchor.constraint(equalTo: verificationStatusLabel.bottomAnchor, constant: 8),
            descLabel.leadingAnchor.constraint(equalTo: page.view.leadingAnchor, constant: 32),
            descLabel.trailingAnchor.constraint(equalTo: page.view.trailingAnchor, constant: -32),

            settingsButton.topAnchor.constraint(equalTo: descLabel.bottomAnchor, constant: 16),
            settingsButton.centerXAnchor.constraint(equalTo: page.view.centerXAnchor),
        ])
    }

    private func handleTimeout() {
        // v1 recovery: timeout은 warning UI만 — polling은 유지하여 recovery 가능
        timeoutTimer?.invalidate()
        timeoutTimer = nil

        guard let page = pages[safe: 2] else { return }

        // secondaryButton 숨김 (retryButton과 중복 방지)
        secondaryButton.isHidden = true
        secondaryButtonHeightConstraint.constant = 0

        // Remove existing extra views
        for subview in page.view.subviews where subview.tag == 901 || subview.tag == 902 {
            subview.removeFromSuperview()
        }

        verificationStatusLabel?.text = L("onboarding.verify.timeout")
        verificationStatusLabel?.textColor = .systemRed

        let descLabel = UILabel()
        descLabel.text = L("onboarding.verify.timeout_desc")
        descLabel.font = .systemFont(ofSize: 14)
        descLabel.textColor = .secondaryLabel
        descLabel.textAlignment = .center
        descLabel.numberOfLines = 0
        descLabel.translatesAutoresizingMaskIntoConstraints = false
        descLabel.tag = 901

        let retryButton = UIButton(type: .system)
        retryButton.setTitle(L("onboarding.verify.retry"), for: .normal)
        retryButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        retryButton.translatesAutoresizingMaskIntoConstraints = false
        retryButton.tag = 902
        retryButton.addTarget(self, action: #selector(retryFromSetup), for: .touchUpInside)

        page.view.addSubview(descLabel)
        page.view.addSubview(retryButton)

        NSLayoutConstraint.activate([
            descLabel.topAnchor.constraint(equalTo: verificationStatusLabel.bottomAnchor, constant: 8),
            descLabel.leadingAnchor.constraint(equalTo: page.view.leadingAnchor, constant: 32),
            descLabel.trailingAnchor.constraint(equalTo: page.view.trailingAnchor, constant: -32),

            retryButton.topAnchor.constraint(equalTo: descLabel.bottomAnchor, constant: 16),
            retryButton.centerXAnchor.constraint(equalTo: page.view.centerXAnchor),
        ])
    }

    @objc private func openSettingsFromVerification() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    @objc private func retryFromSetup() {
        // Clean up extra views from verification page
        if let page = pages[safe: 2] {
            for subview in page.view.subviews where subview.tag == 901 || subview.tag == 902 {
                subview.removeFromSuperview()
            }
        }
        goToPage(1)
    }
}

// MARK: - Welcome Page

private extension OnboardingViewController {
    func makeWelcomePage() -> UIViewController {
        let vc = UIViewController()
        vc.view.backgroundColor = .white

        // Hero image — 제공된 최종 히어로 이미지, 없으면 fallback
        let heroImageView = UIImageView()
        if let heroImage = UIImage(named: "onboarding_welcome_hero_v1") {
            heroImageView.image = heroImage
            heroImageView.contentMode = .scaleAspectFit
        } else {
            heroImageView.image = UIImage(systemName: "globe")
            heroImageView.tintColor = .systemBlue
            heroImageView.contentMode = .scaleAspectFit
        }
        heroImageView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = L("onboarding.welcome.title")
        titleLabel.font = .systemFont(ofSize: 32, weight: .bold)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let subtitleLabel = UILabel()
        subtitleLabel.text = L("onboarding.welcome.subtitle")
        subtitleLabel.font = .systemFont(ofSize: 17)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        vc.view.addSubview(heroImageView)
        vc.view.addSubview(titleLabel)
        vc.view.addSubview(subtitleLabel)

        // 이미지가 가로형이므로 좌우 여백 유지하며 적절한 크기로 표시
        let isHeroAsset = UIImage(named: "onboarding_welcome_hero_v1") != nil
        let imageHeight: CGFloat = isHeroAsset ? 220 : 100

        NSLayoutConstraint.activate([
            heroImageView.centerXAnchor.constraint(equalTo: vc.view.centerXAnchor),
            heroImageView.topAnchor.constraint(equalTo: vc.view.safeAreaLayoutGuide.topAnchor, constant: 60),
            heroImageView.leadingAnchor.constraint(greaterThanOrEqualTo: vc.view.leadingAnchor, constant: 24),
            heroImageView.trailingAnchor.constraint(lessThanOrEqualTo: vc.view.trailingAnchor, constant: -24),
            heroImageView.heightAnchor.constraint(equalToConstant: imageHeight),

            titleLabel.topAnchor.constraint(equalTo: heroImageView.bottomAnchor, constant: 32),
            titleLabel.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor, constant: -24),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            subtitleLabel.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor, constant: 24),
            subtitleLabel.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor, constant: -24),
        ])

        return vc
    }
}

// MARK: - Setup Page (Keyboard + Full Access + Trust)

private extension OnboardingViewController {
    func makeSetupPage() -> UIViewController {
        let vc = UIViewController()
        vc.view.backgroundColor = .systemBackground

        // Title
        let titleLabel = UILabel()
        titleLabel.text = L("onboarding.permission.title")
        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        // Trust header with lock icon
        let trustHeaderStack = UIStackView()
        trustHeaderStack.axis = .horizontal
        trustHeaderStack.spacing = 6
        trustHeaderStack.alignment = .center
        trustHeaderStack.translatesAutoresizingMaskIntoConstraints = false

        let lockIcon = UIImageView()
        lockIcon.image = UIImage(systemName: "lock.shield.fill")
        lockIcon.tintColor = .secondaryLabel
        lockIcon.contentMode = .scaleAspectFit
        lockIcon.translatesAutoresizingMaskIntoConstraints = false

        let trustHeaderLabel = UILabel()
        trustHeaderLabel.text = L("onboarding.trust.title")
        trustHeaderLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        trustHeaderLabel.textColor = .secondaryLabel
        trustHeaderLabel.translatesAutoresizingMaskIntoConstraints = false

        trustHeaderStack.addArrangedSubview(lockIcon)
        trustHeaderStack.addArrangedSubview(trustHeaderLabel)

        NSLayoutConstraint.activate([
            lockIcon.widthAnchor.constraint(equalToConstant: 18),
            lockIcon.heightAnchor.constraint(equalToConstant: 18),
        ])

        // Trust items
        let trustItems = [
            L("onboarding.trust.no_passwords"),
            L("onboarding.trust.no_storage"),
            L("onboarding.trust.ai_only"),
        ]

        let trustStack = UIStackView()
        trustStack.axis = .vertical
        trustStack.spacing = 12
        trustStack.translatesAutoresizingMaskIntoConstraints = false

        for item in trustItems {
            let row = makeTrustRow(text: item)
            trustStack.addArrangedSubview(row)
        }

        // Divider
        let divider = UIView()
        divider.backgroundColor = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false

        // Steps
        let step1View = makeSetupStepView(number: "1", text: L("onboarding.permission.step1"))
        let step2View = makeSetupStepView(number: "2", text: L("onboarding.permission.step2"))

        let stepStack = UIStackView(arrangedSubviews: [step1View, step2View])
        stepStack.axis = .vertical
        stepStack.spacing = 20
        stepStack.translatesAutoresizingMaskIntoConstraints = false

        // Settings Animation Preview — previewContainer로 여백 가운데 배치
        let animView = SetupSettingsAnimationView()
        animView.translatesAutoresizingMaskIntoConstraints = false

        let previewContainer = UIView()
        previewContainer.translatesAutoresizingMaskIntoConstraints = false
        previewContainer.addSubview(animView)

        // v10: infoContainer 도입 — div2를 실제 컨테이너로 묶어 정확한 pt 제어
        let infoContainer = UIView()
        infoContainer.translatesAutoresizingMaskIntoConstraints = false
        infoContainer.addSubview(trustHeaderStack)
        infoContainer.addSubview(trustStack)
        infoContainer.addSubview(divider)
        infoContainer.addSubview(stepStack)

        vc.view.addSubview(titleLabel)
        vc.view.addSubview(previewContainer)
        vc.view.addSubview(infoContainer)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: vc.view.safeAreaLayoutGuide.topAnchor, constant: 40),
            titleLabel.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor, constant: -24),

            // div1: previewContainer
            previewContainer.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 64),
            previewContainer.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor),
            previewContainer.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor),

            animView.centerXAnchor.constraint(equalTo: previewContainer.centerXAnchor),
            animView.topAnchor.constraint(equalTo: previewContainer.topAnchor),
            animView.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor),
            animView.widthAnchor.constraint(equalTo: vc.view.widthAnchor, multiplier: 0.6),
            animView.heightAnchor.constraint(equalToConstant: 210),

            // v10: div1-div2 = 96pt, div2-bottom = 12pt (정확한 pt 고정)
            infoContainer.topAnchor.constraint(equalTo: previewContainer.bottomAnchor, constant: 64),
            infoContainer.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor, constant: 32),
            infoContainer.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor, constant: -32),
            infoContainer.bottomAnchor.constraint(equalTo: vc.view.bottomAnchor, constant: -12),

            // infoContainer 내부
            trustHeaderStack.topAnchor.constraint(equalTo: infoContainer.topAnchor),
            trustHeaderStack.leadingAnchor.constraint(equalTo: infoContainer.leadingAnchor),

            trustStack.topAnchor.constraint(equalTo: trustHeaderStack.bottomAnchor, constant: 12),
            trustStack.leadingAnchor.constraint(equalTo: infoContainer.leadingAnchor),
            trustStack.trailingAnchor.constraint(equalTo: infoContainer.trailingAnchor),

            divider.topAnchor.constraint(equalTo: trustStack.bottomAnchor, constant: 16),
            divider.leadingAnchor.constraint(equalTo: infoContainer.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: infoContainer.trailingAnchor),
            divider.heightAnchor.constraint(equalToConstant: 0.5),

            stepStack.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 16),
            stepStack.leadingAnchor.constraint(equalTo: infoContainer.leadingAnchor),
            stepStack.trailingAnchor.constraint(equalTo: infoContainer.trailingAnchor),
            stepStack.bottomAnchor.constraint(equalTo: infoContainer.bottomAnchor),
        ])

        animView.startLoop()

        registerForegroundObserver()
        return vc
    }

    func makeSetupStepView(number: String, text: String) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let badge = UILabel()
        badge.text = number
        badge.font = .systemFont(ofSize: 16, weight: .bold)
        badge.textColor = .white
        badge.textAlignment = .center
        badge.backgroundColor = .systemBlue
        badge.layer.cornerRadius = 14
        badge.layer.masksToBounds = true
        badge.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 15)
        label.textColor = .label
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(badge)
        container.addSubview(label)

        NSLayoutConstraint.activate([
            badge.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            badge.topAnchor.constraint(equalTo: container.topAnchor),
            badge.widthAnchor.constraint(equalToConstant: 28),
            badge.heightAnchor.constraint(equalToConstant: 28),

            label.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            label.topAnchor.constraint(equalTo: container.topAnchor),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        return container
    }

    func makeTrustRow(text: String) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let checkmark = UIImageView()
        checkmark.image = UIImage(systemName: "checkmark.circle.fill")
        checkmark.tintColor = .systemGreen
        checkmark.contentMode = .scaleAspectFit
        checkmark.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 15)
        label.textColor = .label
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(checkmark)
        container.addSubview(label)

        NSLayoutConstraint.activate([
            checkmark.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            checkmark.topAnchor.constraint(equalTo: container.topAnchor, constant: 2),
            checkmark.widthAnchor.constraint(equalToConstant: 24),
            checkmark.heightAnchor.constraint(equalToConstant: 24),

            label.leadingAnchor.constraint(equalTo: checkmark.trailingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            label.topAnchor.constraint(equalTo: container.topAnchor),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        return container
    }
}

// MARK: - Verification Page

private extension OnboardingViewController {
    func makeVerificationPage() -> UIViewController {
        let vc = UIViewController()
        vc.view.backgroundColor = .white

        // v5: title/hint 제거 — 바로 animation부터 시작

        // Guide animation
        let animView = VerificationKeyboardSwitchAnimationView()
        animView.translatesAutoresizingMaskIntoConstraints = false

        // Hidden input field for keyboard open
        let inputField = UITextField()
        inputField.keyboardType = .default
        inputField.isSecureTextEntry = false
        inputField.alpha = 0.01
        inputField.translatesAutoresizingMaskIntoConstraints = false

        // v5: helper text — 유일한 안내 문장, 폰트 확대
        let statusLabel = UILabel()
        statusLabel.text = L("onboarding.verify.instruction")
        statusLabel.font = .systemFont(ofSize: 15, weight: .medium)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        self.verificationStatusLabel = statusLabel

        // Tap gesture to close keyboard
        let tapGesture = UITapGestureRecognizer(target: inputField, action: #selector(UIResponder.resignFirstResponder))
        tapGesture.cancelsTouchesInView = false
        vc.view.addGestureRecognizer(tapGesture)

        vc.view.addSubview(animView)
        vc.view.addSubview(inputField)
        vc.view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            // v5: animation이 첫 요소
            animView.topAnchor.constraint(equalTo: vc.view.safeAreaLayoutGuide.topAnchor, constant: 32),
            animView.centerXAnchor.constraint(equalTo: vc.view.centerXAnchor),
            animView.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor, constant: 60),
            animView.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor, constant: -60),
            animView.heightAnchor.constraint(equalTo: animView.widthAnchor, multiplier: 0.7),

            inputField.topAnchor.constraint(equalTo: animView.bottomAnchor, constant: 8),
            inputField.centerXAnchor.constraint(equalTo: vc.view.centerXAnchor),
            inputField.widthAnchor.constraint(equalToConstant: 1),
            inputField.heightAnchor.constraint(equalToConstant: 1),

            statusLabel.topAnchor.constraint(equalTo: animView.bottomAnchor, constant: 20),
            statusLabel.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor, constant: 32),
            statusLabel.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor, constant: -32),
        ])

        animView.startLoop()

        return vc
    }
}

// MARK: - Features Page (Consolidated)

private extension OnboardingViewController {
    func makeFeaturesPage() -> UIViewController {
        let vc = UIViewController()
        vc.view.backgroundColor = .systemBackground

        let titleLabel = UILabel()
        titleLabel.text = L("onboarding.features.title")
        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let features: [(icon: String, title: String, description: String)] = [
            ("textformat", L("onboarding.features.translate"), L("onboarding.features.translate_desc")),
            ("pencil.and.outline", L("onboarding.features.correct"), L("onboarding.features.correct_desc")),
            ("doc.on.clipboard", L("onboarding.features.clipboard"), L("onboarding.features.clipboard_desc")),
        ]

        let featureStack = UIStackView()
        featureStack.axis = .vertical
        featureStack.spacing = 28
        featureStack.translatesAutoresizingMaskIntoConstraints = false

        for feature in features {
            let row = makeFeatureRow(icon: feature.icon, title: feature.title, description: feature.description)
            featureStack.addArrangedSubview(row)
        }

        vc.view.addSubview(titleLabel)
        vc.view.addSubview(featureStack)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: vc.view.safeAreaLayoutGuide.topAnchor, constant: 60),
            titleLabel.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor, constant: -24),

            featureStack.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 40),
            featureStack.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor, constant: 32),
            featureStack.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor, constant: -32),
        ])

        return vc
    }

    func makeFeatureRow(icon: String, title: String, description: String) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let iconView = UIImageView()
        iconView.image = UIImage(systemName: icon)
        iconView.tintColor = .systemBlue
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let descLabel = UILabel()
        descLabel.text = description
        descLabel.font = .systemFont(ofSize: 14)
        descLabel.textColor = .secondaryLabel
        descLabel.numberOfLines = 0
        descLabel.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(iconView)
        container.addSubview(titleLabel)
        container.addSubview(descLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            iconView.topAnchor.constraint(equalTo: container.topAnchor, constant: 2),
            iconView.widthAnchor.constraint(equalToConstant: 32),
            iconView.heightAnchor.constraint(equalToConstant: 32),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor),

            descLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            descLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            descLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            descLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        return container
    }
}


// MARK: - Collection Safe Subscript

private extension Collection {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
