import UIKit
import StoreKit

class PaywallViewController: UIViewController {

    private let storeKitManager = StoreKitManager.shared

    // MARK: - Pricing Fallbacks (when StoreKit products not available)

    private struct FallbackPrice {
        let display: String
        let monthly: String?
    }

    private let fallbackPrices: [String: FallbackPrice] = [
        StoreKitManager.ProductID.yearlyPro.rawValue: FallbackPrice(display: "$47.99/yr", monthly: "$3.99/mo"),
        StoreKitManager.ProductID.monthlyPro.rawValue: FallbackPrice(display: "$7.99/mo", monthly: nil),
        StoreKitManager.ProductID.monthlyPremium.rawValue: FallbackPrice(display: "$14.99/mo", monthly: nil),
    ]

    // MARK: - State

    private enum SelectedPlan {
        case yearlyPro, monthlyPro, premium
    }
    private var selectedPlan: SelectedPlan = .yearlyPro
    private var isLoading = false

    // CTA 버튼에 표시할 가격 (StoreKit 로드 전 폴백)
    private var yearlyCtaPrice = "$47.99"
    private var monthlyCtaPrice = "$7.99"
    private var premiumCtaPrice = "$14.99"

    // MARK: - UI Components

    private let scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.showsVerticalScrollIndicator = false
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private let contentStack: UIStackView = {
        let s = UIStackView()
        s.axis = .vertical
        s.spacing = 24
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    private let closeButton: UIButton = {
        let btn = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        btn.setImage(UIImage(systemName: "xmark", withConfiguration: config), for: .normal)
        btn.tintColor = AppColors.textSub
        btn.backgroundColor = UIColor { $0.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.1)
            : UIColor(red: 0.965, green: 0.965, blue: 0.976, alpha: 1) // #F6F6F9
        }
        btn.layer.cornerRadius = 16
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    // Plan selector radio views
    private var yearlyRadio = UIView()
    private var monthlyRadio = UIView()
    private var premiumRadio = UIView()

    // Price labels (updated by StoreKit)
    private let yearlyPriceLabel = UILabel()
    private let yearlyBilledLabel = UILabel()
    private let monthlyPriceLabel = UILabel()
    private let premiumPriceLabel = UILabel()

    // Plan selector cards
    private let yearlyCard = UIView()
    private let monthlyCard = UIView()
    private let premiumCard = UIView()

    // Benefits stack (동적 업데이트용)
    private let benefitsStack = UIStackView()

    // CTA Button
    private let ctaButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.titleLabel?.font = .systemFont(ofSize: 17, weight: .bold)
        btn.setTitleColor(.white, for: .normal)
        btn.backgroundColor = AppColors.tierAccent
        btn.layer.cornerRadius = 16
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let ctaSpinner: UIActivityIndicatorView = {
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.color = .white
        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        return spinner
    }()

    // Cancel anytime label
    private let cancelAnytimeLabel: UILabel = {
        let label = UILabel()
        label.text = L("paywall.cancel_anytime")
        label.font = .systemFont(ofSize: 12)
        label.textColor = AppColors.textMuted
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColors.bg
        setupLayout()
        buildHeroSection()
        buildBenefitsList()
        buildPlanSelector()
        buildBottomSection()
        applyFallbackPrices()
        loadProducts()
        updateSelectionState()
    }

    // MARK: - Layout

    private func setupLayout() {
        view.addSubview(closeButton)
        view.addSubview(scrollView)
        view.addSubview(ctaButton)
        view.addSubview(cancelAnytimeLabel)
        scrollView.addSubview(contentStack)
        ctaButton.addSubview(ctaSpinner)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 32),
            closeButton.heightAnchor.constraint(equalToConstant: 32),

            scrollView.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: ctaButton.topAnchor, constant: -12),

            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 8),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 24),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -24),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -16),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -48),

            ctaButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            ctaButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            ctaButton.heightAnchor.constraint(equalToConstant: 54),
            ctaButton.bottomAnchor.constraint(equalTo: cancelAnytimeLabel.topAnchor, constant: -8),

            cancelAnytimeLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            cancelAnytimeLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            cancelAnytimeLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),

            ctaSpinner.centerXAnchor.constraint(equalTo: ctaButton.centerXAnchor),
            ctaSpinner.centerYAnchor.constraint(equalTo: ctaButton.centerYAnchor),
        ])

        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        ctaButton.addTarget(self, action: #selector(ctaTapped), for: .touchUpInside)
    }

    // MARK: - Hero Section

    private func buildHeroSection() {
        let heroStack = UIStackView()
        heroStack.axis = .vertical
        heroStack.spacing = 12
        heroStack.alignment = .center

        // Bolt icon
        let iconConfig = UIImage.SymbolConfiguration(pointSize: 48, weight: .medium)
        let iconView = UIImageView(image: UIImage(systemName: "bolt.fill", withConfiguration: iconConfig))
        iconView.tintColor = AppColors.tierAccent
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 56),
            iconView.heightAnchor.constraint(equalToConstant: 56),
        ])
        heroStack.addArrangedSubview(iconView)

        // Title
        let titleLabel = UILabel()
        titleLabel.text = L("paywall.hero.title")
        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        titleLabel.textColor = AppColors.text
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        heroStack.addArrangedSubview(titleLabel)

        // Subtitle
        let subtitleLabel = UILabel()
        subtitleLabel.text = L("paywall.hero.subtitle")
        subtitleLabel.font = .systemFont(ofSize: 15)
        subtitleLabel.textColor = AppColors.textSub
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0
        heroStack.addArrangedSubview(subtitleLabel)

        contentStack.addArrangedSubview(heroStack)
    }

    // MARK: - Benefits List

    private func buildBenefitsList() {
        benefitsStack.axis = .vertical
        benefitsStack.spacing = 16
        updateBenefitsContent()
        contentStack.addArrangedSubview(benefitsStack)
    }

    /// 선택된 플랜에 따라 혜택 내용 업데이트
    private func updateBenefitsContent() {
        // 기존 내용 제거
        benefitsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let isPremium = (selectedPlan == .premium)

        let usageTitle = isPremium ? L("paywall.benefit.usage.premium") : L("paywall.benefit.usage")
        let usageDesc = isPremium ? L("paywall.benefit.usage_desc.premium") : L("paywall.benefit.usage_desc")

        // AI 메시지 작성 (톤 스타일 대체)
        let composeTitle = isPremium ? L("paywall.benefit.compose.premium") : L("paywall.benefit.compose")
        let composeDesc = isPremium ? L("paywall.benefit.compose_desc.premium") : L("paywall.benefit.compose_desc")

        let benefits: [(icon: String, title: String, desc: String)] = [
            ("일일100회", usageTitle, usageDesc),
            ("모든톤스타일", composeTitle, composeDesc),
            ("프리미엄테마", L("paywall.benefit.themes"), L("paywall.benefit.themes_desc")),
            ("광고없음", L("paywall.benefit.no_ads"), L("paywall.benefit.no_ads_desc")),
        ]

        for benefit in benefits {
            let row = makeBenefitRow(icon: benefit.icon, title: benefit.title, desc: benefit.desc)
            benefitsStack.addArrangedSubview(row)
        }
    }

    private func makeBenefitRow(icon: String, title: String, desc: String) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 14
        row.alignment = .center

        // Icon area — 대시보드(HomeViewController)와 동일한 스타일
        let iconBg = UIView()
        iconBg.backgroundColor = UIColor { traitCollection in
            if traitCollection.userInterfaceStyle == .dark {
                return UIColor(red: 44/255, green: 44/255, blue: 46/255, alpha: 1.0)    // #2C2C2E
            } else {
                return UIColor(red: 242/255, green: 243/255, blue: 245/255, alpha: 1.0) // #F2F3F5
            }
        }
        iconBg.layer.cornerRadius = 12
        iconBg.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconBg.widthAnchor.constraint(equalToConstant: 40),
            iconBg.heightAnchor.constraint(equalToConstant: 40),
        ])

        // 커스텀 아이콘 이미지
        let iconView = UIImageView(image: UIImage(named: icon))
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconBg.addSubview(iconView)
        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: iconBg.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconBg.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),
        ])

        // Text area
        let textStack = UIStackView()
        textStack.axis = .vertical
        textStack.spacing = 2

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = AppColors.text

        let descLabel = UILabel()
        descLabel.text = desc
        descLabel.font = .systemFont(ofSize: 13)
        descLabel.textColor = AppColors.textSub
        descLabel.numberOfLines = 0

        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(descLabel)

        row.addArrangedSubview(iconBg)
        row.addArrangedSubview(textStack)

        return row
    }

    // MARK: - Plan Selector

    private func buildPlanSelector() {
        // Section header
        let sectionLabel = UILabel()
        sectionLabel.text = L("paywall.plan_section")
        sectionLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        sectionLabel.textColor = AppColors.textMuted
        sectionLabel.text = sectionLabel.text?.uppercased()
        contentStack.addArrangedSubview(sectionLabel)
        contentStack.setCustomSpacing(12, after: sectionLabel)

        // Three plan cards
        yearlyCard.tag = 0
        monthlyCard.tag = 1
        premiumCard.tag = 2

        let yearlyContent = buildPlanRow(
            card: yearlyCard,
            radio: &yearlyRadio,
            title: L("paywall.pro_yearly"),
            priceLabel: yearlyPriceLabel,
            subLabel: yearlyBilledLabel,
            badge: L("paywall.save_percent"),
            badgeColor: AppColors.red,
            action: #selector(yearlyProTapped)
        )
        contentStack.addArrangedSubview(yearlyContent)
        contentStack.setCustomSpacing(10, after: yearlyContent)

        let monthlyContent = buildPlanRow(
            card: monthlyCard,
            radio: &monthlyRadio,
            title: L("paywall.pro_monthly"),
            priceLabel: monthlyPriceLabel,
            subLabel: nil,
            badge: nil,
            badgeColor: nil,
            action: #selector(monthlyProTapped)
        )
        contentStack.addArrangedSubview(monthlyContent)
        contentStack.setCustomSpacing(10, after: monthlyContent)

        let premiumContent = buildPlanRow(
            card: premiumCard,
            radio: &premiumRadio,
            title: L("paywall.premium_monthly"),
            priceLabel: premiumPriceLabel,
            subLabel: nil,
            badge: "UNLIMITED",
            badgeColor: AppColors.orange,
            action: #selector(premiumTapped)
        )
        contentStack.addArrangedSubview(premiumContent)
    }

    private func buildPlanRow(
        card: UIView,
        radio: inout UIView,
        title: String,
        priceLabel: UILabel,
        subLabel: UILabel?,
        badge: String?,
        badgeColor: UIColor?,
        action: Selector
    ) -> UIView {
        card.backgroundColor = AppColors.card
        card.layer.cornerRadius = 16
        card.layer.borderWidth = 2
        card.layer.borderColor = AppColors.border.cgColor
        card.isUserInteractionEnabled = true
        card.addGestureRecognizer(UITapGestureRecognizer(target: self, action: action))

        // Radio circle
        let radioOuter = UIView()
        radioOuter.layer.cornerRadius = 11
        radioOuter.layer.borderWidth = 2
        radioOuter.layer.borderColor = AppColors.textMuted.cgColor
        radioOuter.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            radioOuter.widthAnchor.constraint(equalToConstant: 22),
            radioOuter.heightAnchor.constraint(equalToConstant: 22),
        ])

        let radioInner = UIView()
        radioInner.backgroundColor = AppColors.tierAccent
        radioInner.layer.cornerRadius = 6
        radioInner.translatesAutoresizingMaskIntoConstraints = false
        radioInner.isHidden = true
        radioOuter.addSubview(radioInner)
        NSLayoutConstraint.activate([
            radioInner.centerXAnchor.constraint(equalTo: radioOuter.centerXAnchor),
            radioInner.centerYAnchor.constraint(equalTo: radioOuter.centerYAnchor),
            radioInner.widthAnchor.constraint(equalToConstant: 12),
            radioInner.heightAnchor.constraint(equalToConstant: 12),
        ])

        radio = radioOuter

        // Title + badge
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 16, weight: .bold)
        titleLabel.textColor = AppColors.text

        let titleRow = UIStackView(arrangedSubviews: [titleLabel])
        titleRow.axis = .horizontal
        titleRow.spacing = 8
        titleRow.alignment = .center

        if let badge = badge, let color = badgeColor {
            let badgeLabel = UILabel()
            badgeLabel.text = "  \(badge)  "
            badgeLabel.font = .systemFont(ofSize: 10, weight: .bold)
            badgeLabel.textColor = .white
            badgeLabel.backgroundColor = color
            badgeLabel.layer.cornerRadius = 4
            badgeLabel.layer.masksToBounds = true
            titleRow.addArrangedSubview(badgeLabel)
        }

        // Price
        priceLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        priceLabel.textColor = AppColors.textSub

        let infoStack = UIStackView(arrangedSubviews: [titleRow, priceLabel])
        infoStack.axis = .vertical
        infoStack.spacing = 2
        infoStack.alignment = .leading

        if let sub = subLabel {
            sub.font = .systemFont(ofSize: 12)
            sub.textColor = AppColors.textMuted
            infoStack.addArrangedSubview(sub)
        }

        // Horizontal: radio + info
        let hStack = UIStackView(arrangedSubviews: [radioOuter, infoStack])
        hStack.axis = .horizontal
        hStack.spacing = 14
        hStack.alignment = .center
        hStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(hStack)

        NSLayoutConstraint.activate([
            hStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            hStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            hStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            hStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
        ])

        return card
    }

    // MARK: - Bottom Section

    private func buildBottomSection() {
        let restoreButton = UIButton(type: .system)
        restoreButton.setTitle(L("onboarding.subscription.restore"), for: .normal)
        restoreButton.titleLabel?.font = .systemFont(ofSize: 12)
        restoreButton.setTitleColor(AppColors.textMuted, for: .normal)
        restoreButton.addTarget(self, action: #selector(restoreTapped), for: .touchUpInside)

        let dotLabel1 = UILabel()
        dotLabel1.text = "\u{00B7}"
        dotLabel1.font = .systemFont(ofSize: 12)
        dotLabel1.textColor = AppColors.textMuted

        let termsButton = UIButton(type: .system)
        termsButton.setTitle(L("settings.terms"), for: .normal)
        termsButton.titleLabel?.font = .systemFont(ofSize: 12)
        termsButton.setTitleColor(AppColors.textMuted, for: .normal)
        termsButton.addTarget(self, action: #selector(termsTapped), for: .touchUpInside)

        let dotLabel2 = UILabel()
        dotLabel2.text = "\u{00B7}"
        dotLabel2.font = .systemFont(ofSize: 12)
        dotLabel2.textColor = AppColors.textMuted

        let privacyButton = UIButton(type: .system)
        privacyButton.setTitle(L("settings.privacy"), for: .normal)
        privacyButton.titleLabel?.font = .systemFont(ofSize: 12)
        privacyButton.setTitleColor(AppColors.textMuted, for: .normal)
        privacyButton.addTarget(self, action: #selector(privacyTapped), for: .touchUpInside)

        let linksStack = UIStackView(arrangedSubviews: [restoreButton, dotLabel1, termsButton, dotLabel2, privacyButton])
        linksStack.axis = .horizontal
        linksStack.spacing = 6
        linksStack.alignment = .center

        let bottomStack = UIStackView(arrangedSubviews: [linksStack])
        bottomStack.axis = .vertical
        bottomStack.spacing = 8
        bottomStack.alignment = .center

        contentStack.addArrangedSubview(bottomStack)
    }

    // MARK: - Selection State

    private func updateSelectionState() {
        let cards: [(UIView, UIView, SelectedPlan)] = [
            (yearlyCard, yearlyRadio, .yearlyPro),
            (monthlyCard, monthlyRadio, .monthlyPro),
            (premiumCard, premiumRadio, .premium),
        ]

        for (card, radio, plan) in cards {
            let isSelected = plan == selectedPlan
            card.layer.borderWidth = 2
            card.layer.borderColor = isSelected ? AppColors.tierAccent.cgColor : AppColors.border.cgColor
            let selectedCardBg = UIColor { $0.userInterfaceStyle == .dark
                ? AppColors.tierAccent.withAlphaComponent(0.15)
                : AppColors.tierAccentSoft
            }
            card.backgroundColor = isSelected ? selectedCardBg : AppColors.card

            // Radio fill
            radio.layer.borderColor = isSelected ? AppColors.tierAccent.cgColor : AppColors.textMuted.cgColor
            if let inner = radio.subviews.first {
                inner.isHidden = !isSelected
            }

            // Bounce animation
            if isSelected {
                UIView.animate(withDuration: 0.12, animations: {
                    card.transform = CGAffineTransform(scaleX: 0.97, y: 0.97)
                }) { _ in
                    UIView.animate(withDuration: 0.12) {
                        card.transform = .identity
                    }
                }
            }
        }

        // Update CTA text
        let ctaText: String
        switch selectedPlan {
        case .yearlyPro:
            ctaText = String(format: L("paywall.cta_yearly"), yearlyCtaPrice)
        case .monthlyPro:
            ctaText = String(format: L("paywall.cta_monthly"), monthlyCtaPrice)
        case .premium:
            ctaText = String(format: L("paywall.cta_premium"), premiumCtaPrice)
        }
        ctaButton.setTitle(ctaText, for: .normal)
        updateBenefitsContent()
    }

    // MARK: - Pricing

    private func applyFallbackPrices() {
        let yearlyKey = StoreKitManager.ProductID.yearlyPro.rawValue
        let monthlyKey = StoreKitManager.ProductID.monthlyPro.rawValue
        let premiumKey = StoreKitManager.ProductID.monthlyPremium.rawValue

        yearlyPriceLabel.text = String(format: L("paywall.per_month"), "$3.99")
        yearlyBilledLabel.text = L("paywall.billed_yearly")
        monthlyPriceLabel.text = String(format: L("paywall.per_month"), "$7.99")
        premiumPriceLabel.text = String(format: L("paywall.per_month"), "$14.99")

        yearlyCtaPrice = "$47.99"
        monthlyCtaPrice = "$7.99"
        premiumCtaPrice = "$14.99"
    }

    private func loadProducts() {
        Task {
            do {
                try await storeKitManager.loadProducts()
                updatePriceLabels()
            } catch {
                // StoreKit failed -- fallback prices already displayed
            }
        }
    }

    private func updatePriceLabels() {
        for product in storeKitManager.products {
            switch product.id {
            case StoreKitManager.ProductID.yearlyPro.rawValue:
                let monthlyPrice = product.price / 12
                let formatter = NumberFormatter()
                formatter.numberStyle = .currency
                formatter.locale = product.priceFormatStyle.locale
                if let formatted = formatter.string(from: monthlyPrice as NSDecimalNumber) {
                    yearlyPriceLabel.text = String(format: L("paywall.per_month"), formatted)
                }
                yearlyBilledLabel.text = product.displayPrice
                yearlyCtaPrice = product.displayPrice

            case StoreKitManager.ProductID.monthlyPro.rawValue:
                monthlyPriceLabel.text = String(format: L("paywall.per_month"), product.displayPrice)
                monthlyCtaPrice = product.displayPrice

            case StoreKitManager.ProductID.monthlyPremium.rawValue:
                premiumPriceLabel.text = String(format: L("paywall.per_month"), product.displayPrice)
                premiumCtaPrice = product.displayPrice

            default:
                break
            }
        }
        updateSelectionState()
    }

    // MARK: - Loading State

    private func setLoading(_ loading: Bool) {
        isLoading = loading
        ctaButton.isEnabled = !loading
        if loading {
            ctaButton.setTitle("", for: .normal)
            ctaSpinner.startAnimating()
        } else {
            ctaSpinner.stopAnimating()
            updateSelectionState()
        }
    }

    // MARK: - Error Toast

    private func showError(_ message: String) {
        let toast = UILabel()
        toast.text = "  \(message)  "
        toast.font = .systemFont(ofSize: 14, weight: .medium)
        toast.textColor = .white
        toast.backgroundColor = UIColor.systemRed
        toast.layer.cornerRadius = 10
        toast.clipsToBounds = true
        toast.textAlignment = .center
        toast.alpha = 0
        toast.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toast)

        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toast.bottomAnchor.constraint(equalTo: ctaButton.topAnchor, constant: -12),
            toast.heightAnchor.constraint(equalToConstant: 36),
        ])

        UIView.animate(withDuration: 0.3) { toast.alpha = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            UIView.animate(withDuration: 0.3, animations: { toast.alpha = 0 }) { _ in
                toast.removeFromSuperview()
            }
        }
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func yearlyProTapped() {
        selectedPlan = .yearlyPro
        updateSelectionState()
    }

    @objc private func monthlyProTapped() {
        selectedPlan = .monthlyPro
        updateSelectionState()
    }

    @objc private func premiumTapped() {
        selectedPlan = .premium
        updateSelectionState()
    }

    @objc private func ctaTapped() {
        guard !isLoading else { return }

        let productId: StoreKitManager.ProductID
        switch selectedPlan {
        case .yearlyPro: productId = .yearlyPro
        case .monthlyPro: productId = .monthlyPro
        case .premium: productId = .monthlyPremium
        }

        purchaseProduct(id: productId)
    }

    private func purchaseProduct(id: StoreKitManager.ProductID) {
        guard let product = storeKitManager.products.first(where: { $0.id == id.rawValue }) else {
            showError(L("paywall.error_loading"))
            return
        }

        setLoading(true)
        Task {
            do {
                let transaction = try await storeKitManager.purchase(product)
                setLoading(false)
                if transaction != nil {
                    showSuccessAndDismiss()
                }
            } catch {
                setLoading(false)
                showError(L("paywall.error_purchase"))
            }
        }
    }

    private func showSuccessAndDismiss() {
        let check = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
        check.tintColor = AppColors.green
        check.contentMode = .scaleAspectFit
        check.translatesAutoresizingMaskIntoConstraints = false
        check.alpha = 0
        check.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
        view.addSubview(check)

        NSLayoutConstraint.activate([
            check.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            check.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            check.widthAnchor.constraint(equalToConstant: 80),
            check.heightAnchor.constraint(equalToConstant: 80),
        ])

        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.8) {
            check.alpha = 1
            check.transform = .identity
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.dismiss(animated: true)
        }
    }

    @objc private func restoreTapped() {
        setLoading(true)
        Task {
            do {
                try await storeKitManager.restorePurchases()
                setLoading(false)
                if SubscriptionStatus.shared.isPro {
                    showSuccessAndDismiss()
                } else {
                    showError(L("paywall.error_no_subscription"))
                }
            } catch {
                setLoading(false)
                showError(L("paywall.error_restore"))
            }
        }
    }

    @objc private func termsTapped() {
        if let url = URL(string: LegalLinks.terms) {
            UIApplication.shared.open(url)
        }
    }

    @objc private func privacyTapped() {
        if let url = URL(string: LegalLinks.privacy) {
            UIApplication.shared.open(url)
        }
    }
}
