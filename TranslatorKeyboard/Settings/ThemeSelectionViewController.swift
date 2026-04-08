import UIKit

// MARK: - Theme Category

enum ThemeCategory: String, CaseIterable {
    case all         = "theme.category_all"
    case free        = "theme.category_free"
    case neon        = "theme.category_neon"
    case nature      = "theme.category_nature"
    case animation   = "theme.category_animation"
    case space       = "theme.category_space"
    case minimal     = "theme.category_minimal"

    var localizedName: String { L(rawValue) }
}

class ThemeSelectionViewController: UIViewController {

    private let freeThemes = KeyboardTheme.allThemes
    private let premiumThemes = KeyboardTheme.allPremiumThemes
    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 14
        layout.minimumLineSpacing = 16
        layout.sectionInset = UIEdgeInsets(top: 16, left: 20, bottom: 20, right: 20)
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .clear
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.dataSource = self
        cv.delegate = self
        cv.register(ThemeCell.self, forCellWithReuseIdentifier: ThemeCell.reuseId)
        cv.register(PremiumThemeCell.self, forCellWithReuseIdentifier: PremiumThemeCell.reuseId)
        cv.register(ThemeSectionHeader.self,
                    forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                    withReuseIdentifier: ThemeSectionHeader.reuseId)
        return cv
    }()

    private var selectedThemeId: String = "default"

    /// 애니메이션 프리뷰 스냅샷 캐시 — theme.id를 키로 사용
    private var animationPreviewCache: [String: UIImage] = [:]

    // MARK: - Category Tag Map
    // 태그가 없는 테마는 "전체"에만 표시됨
    private static let themeTagMap: [String: Set<ThemeCategory>] = [
        // 무료 테마 12개: .free 태그 일괄 부여 (allThemes에서 자동 처리)

        // 프리미엄 - 네온
        "premium_midnight_aurora":  [.neon, .space],
        "premium_starlit_night":    [.neon, .space],
        "premium_matrix_pulse":     [.neon, .animation],
        "premium_digital_rain":     [.neon, .animation],

        // 프리미엄 - 자연
        "premium_ocean_abyss":      [.nature],
        "premium_sunset_ember":     [.nature],
        "premium_volcanic_ember":   [.nature],
        "premium_northern_lights":  [.nature],
        "premium_sakura_breeze":    [.nature],
        "premium_deep_ocean":       [.nature],
        "premium_dark_walnut":      [.nature],
        "premium_natural_oak":      [.nature],
        "premium_mercury_ripple":   [.nature, .animation],

        // 프리미엄 - 우주
        "premium_stardust_drift":   [.space, .animation],
        "premium_edge_glow_green":  [.neon, .animation],
        "premium_edge_glow_red":    [.neon, .animation],
        "premium_edge_glow_blue":   [.neon, .animation],
        "premium_edge_glow_yellow": [.neon, .animation],
        "premium_edge_glow_purple": [.neon, .animation],

        // 프리미엄 - 네온 (정적)
        "premium_static_neon_green":  [.neon],
        "premium_static_neon_red":    [.neon],
        "premium_static_neon_blue":   [.neon],
        "premium_static_neon_yellow": [.neon],
        "premium_static_neon_purple": [.neon],

        // 프리미엄 - 자연/애니메이션
        "premium_midnight_snowfall": [.nature, .animation],
        "premium_cherry_blossom":    [.nature, .animation],

        // 프리미엄 - 미니멀
        "premium_rose_gold":        [.minimal],
        "premium_frost_crystal":    [.minimal],
        "premium_brushed_steel":    [.minimal],
        "premium_rose_carbon":      [.minimal],
        "premium_crimson_ivory":    [.minimal],
        "premium_lilac_sky":        [.minimal],
    ]

    private var selectedCategory: ThemeCategory = .all
    private var filteredFreeThemes: [KeyboardTheme] = []
    private var filteredPremiumThemes: [KeyboardTheme] = []

    // MARK: - Category Tab Bar

    private lazy var categoryScrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.showsHorizontalScrollIndicator = false
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.backgroundColor = AppColors.bg
        return sv
    }()

    private lazy var categoryStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 8
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private var categoryButtons: [UIButton] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = L("settings.keyboard_theme")
        view.backgroundColor = AppColors.bg
        navigationController?.navigationBar.prefersLargeTitles = true

        setupCategoryTabBar()

        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: categoryScrollView.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        selectedThemeId = AppGroupManager.shared.string(forKey: AppConstants.UserDefaultsKeys.keyboardTheme) ?? "default"
        applyFilter()   // 초기 필터 적용 (전체)

        NotificationCenter.default.addObserver(self, selector: #selector(handleLanguageChange), name: .languageDidChange, object: nil)

        // ★ v3: 앱 백그라운드/포그라운드 시 애니메이션 관리
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        selectedThemeId = AppGroupManager.shared.string(forKey: AppConstants.UserDefaultsKeys.keyboardTheme) ?? "default"
        animationPreviewCache.removeAll()
        applyFilter()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        animationPreviewCache.removeAll()
    }

    @objc private func handleLanguageChange() {
        navigationItem.title = L("settings.keyboard_theme")
        // 카테고리 버튼 텍스트 갱신
        for (index, button) in categoryButtons.enumerated() {
            let category = ThemeCategory.allCases[index]
            button.setTitle(category.localizedName, for: .normal)
        }
        collectionView.reloadData()
    }

    private func findIndexPath(forThemeId id: String) -> IndexPath? {
        if let index = freeThemes.firstIndex(where: { $0.id == id }) {
            return IndexPath(item: index, section: 0)
        }
        if let index = premiumThemes.firstIndex(where: { $0.id == id }) {
            return IndexPath(item: index, section: 1)
        }
        return nil
    }

    /// 필터된 배열에서 테마 ID로 IndexPath 찾기
    private func findFilteredIndexPath(forThemeId id: String) -> IndexPath? {
        if let index = filteredFreeThemes.firstIndex(where: { $0.id == id }) {
            return IndexPath(item: index, section: 0)
        }
        if let index = filteredPremiumThemes.firstIndex(where: { $0.id == id }) {
            let premiumSection = filteredFreeThemes.isEmpty ? 0 : 1
            return IndexPath(item: index, section: premiumSection)
        }
        return nil
    }

    // MARK: - Filtering

    private func applyFilter() {
        switch selectedCategory {
        case .all:
            filteredFreeThemes = freeThemes
            filteredPremiumThemes = premiumThemes
        case .free:
            filteredFreeThemes = freeThemes
            filteredPremiumThemes = []
        default:
            filteredFreeThemes = freeThemes.filter { theme in
                guard let tags = Self.themeTagMap[theme.id] else { return false }
                if selectedCategory != .animation && tags.contains(.animation) {
                    return false
                }
                return tags.contains(selectedCategory)
            }
            filteredPremiumThemes = premiumThemes.filter { theme in
                guard let tags = Self.themeTagMap[theme.id] else { return false }
                if selectedCategory != .animation && tags.contains(.animation) {
                    return false
                }
                return tags.contains(selectedCategory)
            }
        }
        collectionView.reloadData()
    }

    private func setupCategoryTabBar() {
        view.addSubview(categoryScrollView)
        categoryScrollView.addSubview(categoryStack)

        NSLayoutConstraint.activate([
            categoryScrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            categoryScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            categoryScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            categoryScrollView.heightAnchor.constraint(equalToConstant: 48),

            categoryStack.topAnchor.constraint(equalTo: categoryScrollView.topAnchor, constant: 8),
            categoryStack.leadingAnchor.constraint(equalTo: categoryScrollView.leadingAnchor, constant: 20),
            categoryStack.trailingAnchor.constraint(equalTo: categoryScrollView.trailingAnchor, constant: -20),
            categoryStack.bottomAnchor.constraint(equalTo: categoryScrollView.bottomAnchor, constant: -8),
            categoryStack.heightAnchor.constraint(equalToConstant: 32),
        ])

        for (index, category) in ThemeCategory.allCases.enumerated() {
            let button = UIButton(type: .system)
            button.setTitle(category.localizedName, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
            button.layer.cornerRadius = 16
            button.clipsToBounds = true
            button.tag = index
            button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 16, bottom: 6, right: 16)
            button.addTarget(self, action: #selector(categoryTapped(_:)), for: .touchUpInside)

            categoryButtons.append(button)
            categoryStack.addArrangedSubview(button)
        }

        updateCategoryButtonStyles()
    }

    @objc private func categoryTapped(_ sender: UIButton) {
        let categories = ThemeCategory.allCases
        guard sender.tag < categories.count else { return }

        selectedCategory = categories[sender.tag]
        updateCategoryButtonStyles()
        applyFilter()

        // 탭 변경 시 컬렉션뷰 맨 위로 스크롤
        if collectionView.numberOfSections > 0,
           collectionView.numberOfItems(inSection: 0) > 0 {
            collectionView.scrollToItem(at: IndexPath(item: 0, section: 0),
                                         at: .top, animated: false)
        } else {
            collectionView.setContentOffset(.zero, animated: false)
        }
    }

    private func updateCategoryButtonStyles() {
        for (index, button) in categoryButtons.enumerated() {
            let category = ThemeCategory.allCases[index]
            let isSelected = category == selectedCategory

            if isSelected {
                button.backgroundColor = AppColors.tierAccent
                button.setTitleColor(.white, for: .normal)
                button.layer.borderWidth = 0
            } else {
                button.backgroundColor = AppColors.card
                button.setTitleColor(AppColors.textSub, for: .normal)
                button.layer.borderWidth = 1
                button.layer.borderColor = AppColors.border.cgColor
            }
        }
    }
}

// MARK: - UICollectionViewDataSource & Delegate

extension ThemeSelectionViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        var count = 0
        if !filteredFreeThemes.isEmpty { count += 1 }
        if !filteredPremiumThemes.isEmpty { count += 1 }
        return count
    }

    /// 실제 섹션 인덱스 → free/premium 판별
    private enum SectionType {
        case free, premium
    }

    private func sectionType(for section: Int) -> SectionType {
        if !filteredFreeThemes.isEmpty {
            return section == 0 ? .free : .premium
        }
        return .premium
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        switch sectionType(for: section) {
        case .free:    return filteredFreeThemes.count
        case .premium: return filteredPremiumThemes.count
        }
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let theme: KeyboardTheme
        let type = sectionType(for: indexPath.section)
        switch type {
        case .free:    theme = filteredFreeThemes[indexPath.item]
        case .premium: theme = filteredPremiumThemes[indexPath.item]
        }

        #if DEBUG
        let isLocked = false
        #else
        let isPro = SubscriptionStatus.shared.isPro
        let isLocked = theme.isPremium && !isPro
        #endif
        let isSelected = theme.id == selectedThemeId

        switch type {
        case .premium:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: PremiumThemeCell.reuseId, for: indexPath) as! PremiumThemeCell

            // ★ v3: 라이브 애니메이션으로 전환 — 스냅샷 캐시 비활성화
            // cell.setAnimationPreviewCache(animationPreviewCache[theme.id])
            // cell.onPreviewRendered = { [weak self] image in
            //     self?.animationPreviewCache[theme.id] = image
            // }

            cell.configure(theme: theme, isSelected: isSelected, isLocked: isLocked)
            return cell
        case .free:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ThemeCell.reuseId, for: indexPath) as! ThemeCell
            cell.configure(theme: theme, isSelected: isSelected, isLocked: isLocked)
            return cell
        }
    }

    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        let header = collectionView.dequeueReusableSupplementaryView(
            ofKind: kind,
            withReuseIdentifier: ThemeSectionHeader.reuseId,
            for: indexPath
        ) as! ThemeSectionHeader

        switch sectionType(for: indexPath.section) {
        case .free:
            header.configure(title: L("theme.section_free"), showBadge: false)
        case .premium:
            header.configure(title: L("theme.section_premium"), showBadge: true)
        }
        return header
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {
        // 섹션에 아이템이 없으면 헤더도 숨김 (안전장치)
        let itemCount = collectionView.numberOfItems(inSection: section)
        guard itemCount > 0 else { return .zero }
        return CGSize(width: collectionView.bounds.width, height: 44)
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let totalSpacing: CGFloat = 20 * 2 + 14
        let width = (collectionView.bounds.width - totalSpacing) / 2
        switch sectionType(for: indexPath.section) {
        case .premium:
            return CGSize(width: floor(width), height: floor(width) * 1.45)
        case .free:
            return CGSize(width: floor(width), height: floor(width) * 1.15)
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let theme: KeyboardTheme
        switch sectionType(for: indexPath.section) {
        case .free:    theme = filteredFreeThemes[indexPath.item]
        case .premium: theme = filteredPremiumThemes[indexPath.item]
        }

        #if DEBUG
        // 개발 모드: Paywall 건너뜀
        #else
        let isPro = SubscriptionStatus.shared.isPro
        if theme.isPremium && !isPro {
            guard self.presentedViewController == nil else { return }
            let paywallVC = PaywallViewController()
            paywallVC.modalPresentationStyle = .pageSheet
            self.present(paywallVC, animated: true)
            return
        }
        #endif

        let previousId = selectedThemeId
        selectedThemeId = theme.id
        AppGroupManager.shared.set(theme.id, forKey: AppConstants.UserDefaultsKeys.keyboardTheme)
        ThemePatternRenderer.clearCache()

        // 필터된 배열에서 이전 선택 찾기 (안전 검증 포함)
        var indexPaths = [indexPath]
        if let prevPath = findFilteredIndexPath(forThemeId: previousId),
           prevPath != indexPath,
           prevPath.section < collectionView.numberOfSections,
           prevPath.item < collectionView.numberOfItems(inSection: prevPath.section) {
            indexPaths.append(prevPath)
        }
        collectionView.reloadItems(at: indexPaths)

        // Selection animation
        if let cell = collectionView.cellForItem(at: indexPath) {
            UIView.animate(withDuration: 0.15, animations: {
                cell.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
            }) { _ in
                UIView.animate(withDuration: 0.15) {
                    cell.transform = .identity
                }
            }
        }
    }

    // ★ v3: 화면 진입 시 애니메이션 재개
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if let premiumCell = cell as? PremiumThemeCell {
            premiumCell.startAnimations()
        }
    }

    // ★ v3: 화면 이탈 시 애니메이션 일시정지 (레이어는 유지)
    func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if let premiumCell = cell as? PremiumThemeCell {
            premiumCell.stopAnimations()
        }
    }

    // ★ v3: 앱 라이프사이클 — 애니메이션 관리
    @objc private func appDidEnterBackground() {
        for cell in collectionView.visibleCells {
            if let premiumCell = cell as? PremiumThemeCell {
                premiumCell.stopAnimations()
            }
        }
    }

    @objc private func appWillEnterForeground() {
        for cell in collectionView.visibleCells {
            if let premiumCell = cell as? PremiumThemeCell {
                premiumCell.startAnimations()
            }
        }
    }
}

// MARK: - ThemeSectionHeader

private class ThemeSectionHeader: UICollectionReusableView {
    static let reuseId = "ThemeSectionHeader"

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 16, weight: .bold)
        l.textColor = AppColors.text
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let proBadge: UILabel = {
        let l = UILabel()
        l.text = "PRO"
        l.font = .systemFont(ofSize: 10, weight: .heavy)
        l.textColor = .white
        l.backgroundColor = AppColors.tierAccent
        l.textAlignment = .center
        l.layer.cornerRadius = 4
        l.clipsToBounds = true
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(titleLabel)
        addSubview(proBadge)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            proBadge.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            proBadge.centerYAnchor.constraint(equalTo: centerYAnchor),
            proBadge.widthAnchor.constraint(equalToConstant: 34),
            proBadge.heightAnchor.constraint(equalToConstant: 18),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String, showBadge: Bool) {
        titleLabel.text = title
        proBadge.isHidden = !showBadge

        isAccessibilityElement = true
        accessibilityLabel = showBadge ? "\(title) PRO" : title
        accessibilityTraits = .header
    }
}

// MARK: - ThemeCell

private class ThemeCell: UICollectionViewCell {

    static let reuseId = "ThemeCell"

    private let cardView: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 14
        v.clipsToBounds = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let previewContainer: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 8
        v.clipsToBounds = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    // 3 rows of mini keys for QWERTY preview
    private var keyRows: [[UIView]] = []

    private let nameLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 13, weight: .semibold)
        l.textAlignment = .left
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let colorDotsStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 4
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private var dotViews: [UIView] = []

    private let checkmark: UIImageView = {
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .bold)
        let iv = UIImageView(image: UIImage(systemName: "checkmark.circle.fill", withConfiguration: config))
        iv.tintColor = AppColors.tierAccent
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.isHidden = true
        return iv
    }()

    private let lockOverlay: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor(white: 0.5, alpha: 0.4)
        v.layer.cornerRadius = 8
        v.clipsToBounds = true
        v.isHidden = true
        v.isUserInteractionEnabled = false
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let lockIcon: UIImageView = {
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        let iv = UIImageView(image: UIImage(systemName: "lock.fill", withConfiguration: config))
        iv.tintColor = .white
        iv.isUserInteractionEnabled = false
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        // 스케일 애니메이션 잔여 transform 초기화
        transform = .identity
        contentView.transform = .identity
        layer.removeAllAnimations()
        contentView.layer.removeAllAnimations()
        lockOverlay.isHidden = true
        checkmark.isHidden = true
        cardView.layer.borderColor = UIColor.clear.cgColor
        cardView.layer.borderWidth = 1
        nameLabel.textColor = AppColors.text
        accessibilityLabel = nil
        accessibilityHint = nil
        accessibilityTraits = .button
    }

    private func setupViews() {
        contentView.addSubview(cardView)
        cardView.addSubview(previewContainer)
        cardView.addSubview(nameLabel)
        cardView.addSubview(colorDotsStack)
        cardView.addSubview(checkmark)

        // Mini keyboard: 3 rows (10, 9, 7 keys)
        let keyCounts = [10, 9, 7]
        for count in keyCounts {
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 2
            row.distribution = .fillEqually
            row.translatesAutoresizingMaskIntoConstraints = false

            var rowKeys: [UIView] = []
            for _ in 0..<count {
                let kv = UIView()
                kv.layer.cornerRadius = 2
                rowKeys.append(kv)
                row.addArrangedSubview(kv)
            }
            keyRows.append(rowKeys)
            previewContainer.addSubview(row)
        }

        // lockOverlay: added AFTER key rows for correct Z-order
        previewContainer.addSubview(lockOverlay)
        lockOverlay.addSubview(lockIcon)

        // 4 color palette dots
        for _ in 0..<4 {
            let dot = UIView()
            dot.layer.cornerRadius = 4
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.widthAnchor.constraint(equalToConstant: 8).isActive = true
            dot.heightAnchor.constraint(equalToConstant: 8).isActive = true
            dotViews.append(dot)
            colorDotsStack.addArrangedSubview(dot)
        }

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            previewContainer.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 10),
            previewContainer.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 10),
            previewContainer.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -10),

            nameLabel.topAnchor.constraint(equalTo: previewContainer.bottomAnchor, constant: 10),
            nameLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 12),
            nameLabel.trailingAnchor.constraint(equalTo: checkmark.leadingAnchor, constant: -4),

            colorDotsStack.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 6),
            colorDotsStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 12),
            colorDotsStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -10),

            checkmark.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -10),
            checkmark.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),

            lockOverlay.topAnchor.constraint(equalTo: previewContainer.topAnchor),
            lockOverlay.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
            lockOverlay.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
            lockOverlay.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor),

            lockIcon.centerXAnchor.constraint(equalTo: lockOverlay.centerXAnchor),
            lockIcon.centerYAnchor.constraint(equalTo: lockOverlay.centerYAnchor),
        ])

        // Layout key rows
        let rows = previewContainer.subviews.compactMap { $0 as? UIStackView }
        for (i, row) in rows.enumerated() {
            let hPadding: CGFloat = i == 2 ? 12 : (i == 1 ? 6 : 4)
            NSLayoutConstraint.activate([
                row.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor, constant: hPadding),
                row.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor, constant: -hPadding),
                row.heightAnchor.constraint(equalToConstant: 14),
            ])
            if i == 0 {
                row.topAnchor.constraint(equalTo: previewContainer.topAnchor, constant: 6).isActive = true
            } else {
                row.topAnchor.constraint(equalTo: rows[i - 1].bottomAnchor, constant: 3).isActive = true
            }
            if i == rows.count - 1 {
                row.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor, constant: -6).isActive = true
            }
        }

        cardView.layer.borderWidth = 2
        cardView.layer.borderColor = UIColor.clear.cgColor
    }

    func configure(theme: KeyboardTheme, isSelected: Bool, isLocked: Bool) {
        cardView.backgroundColor = AppColors.card
        previewContainer.backgroundColor = theme.keyboardBackground

        for rowKeys in keyRows {
            for kv in rowKeys {
                kv.backgroundColor = theme.keyBackground
            }
        }
        // Last row: make first and last keys use special key color
        if let lastRow = keyRows.last, lastRow.count >= 2 {
            lastRow.first?.backgroundColor = theme.specialKeyBackground
            lastRow.last?.backgroundColor = theme.specialKeyBackground
        }

        nameLabel.text = theme.localizedDisplayName

        // Color palette dots
        let colors = [theme.keyboardBackground, theme.keyBackground, theme.specialKeyBackground, theme.keyTextColor]
        for (i, dot) in dotViews.enumerated() where i < colors.count {
            dot.backgroundColor = colors[i]
            dot.layer.borderWidth = 0.5
            dot.layer.borderColor = AppColors.border.cgColor
        }

        // Lock state
        lockOverlay.isHidden = !isLocked
        checkmark.isHidden = isLocked || !isSelected

        if isLocked {
            nameLabel.textColor = AppColors.textMuted
            cardView.layer.borderColor = AppColors.border.cgColor
            cardView.layer.borderWidth = 1
        } else {
            nameLabel.textColor = AppColors.text
            checkmark.isHidden = !isSelected
            cardView.layer.borderColor = isSelected ? AppColors.tierAccent.cgColor : AppColors.border.cgColor
            cardView.layer.borderWidth = isSelected ? 2 : 1
        }

        // VoiceOver accessibility
        isAccessibilityElement = true
        if isLocked {
            accessibilityLabel = "\(theme.localizedDisplayName), \(L("theme.section_premium")), \(L("accessibility.locked"))"
            accessibilityHint = L("accessibility.theme_locked_hint")
            accessibilityTraits = .button
        } else if isSelected {
            accessibilityLabel = "\(theme.localizedDisplayName), \(L("accessibility.selected"))"
            accessibilityTraits = [.button, .selected]
            accessibilityHint = nil
        } else {
            accessibilityLabel = theme.localizedDisplayName
            accessibilityTraits = .button
            accessibilityHint = L("accessibility.theme_select_hint")
        }
    }
}

// MARK: - PreviewKeyboardLayout

private enum PreviewKeyboardLayout {

    static func rows(for language: String) -> (row1: [String], row2: [String], row3: [String]) {
        switch language {
        case "ko":
            return (
                ["ㅂ","ㅈ","ㄷ","ㄱ","ㅅ","ㅛ","ㅕ","ㅑ","ㅐ","ㅔ"],
                ["ㅁ","ㄴ","ㅇ","ㄹ","ㅎ","ㅗ","ㅓ","ㅏ","ㅣ"],
                ["ㅋ","ㅌ","ㅊ","ㅍ","ㅠ","ㅜ","ㅡ"]
            )
        case "ru":
            return (
                ["Й","Ц","У","К","Е","Н","Г","Ш","Щ","З"],
                ["Ф","Ы","В","А","П","Р","О","Л","Д"],
                ["Я","Ч","С","М","И","Т","Ь"]
            )
        case "ja":
            return (
                ["あ","か","さ","た","な","は","ま","や","ら","わ"],
                ["い","き","し","ち","に","ひ","み","ゆ","り"],
                ["う","く","す","つ","ぬ","ふ","む"]
            )
        case "fr":
            return (
                ["A","Z","E","R","T","Y","U","I","O","P"],
                ["Q","S","D","F","G","H","J","K","L"],
                ["W","X","C","V","B","N","M"]
            )
        case "de":
            return (
                ["Q","W","E","R","T","Z","U","I","O","P"],
                ["A","S","D","F","G","H","J","K","L"],
                ["Y","X","C","V","B","N","M"]
            )
        default:
            return (
                ["Q","W","E","R","T","Y","U","I","O","P"],
                ["A","S","D","F","G","H","J","K","L"],
                ["Z","X","C","V","B","N","M"]
            )
        }
    }

    static func bottomRow(for language: String) -> (numKey: String, spaceLabel: String) {
        switch language {
        case "ko": return ("123", "간격")
        case "ja": return ("123", "空白")
        case "zh-Hans": return ("123", "空格")
        case "ru": return ("123", "пробел")
        case "es": return ("123", "espacio")
        case "fr": return ("123", "espace")
        case "de": return ("123", "Leerzeichen")
        case "it": return ("123", "spazio")
        default: return ("123", "space")
        }
    }
}

// MARK: - PremiumThemeCell

private class PremiumThemeCell: UICollectionViewCell {

    static let reuseId = "PremiumThemeCell"

    /// 프리뷰 렌더링 완료 시 ViewController에 스냅샷 전달하는 콜백
    var onPreviewRendered: ((UIImage) -> Void)?

    /// 캐시된 프리뷰 이미지를 설정 — 레이어 생성을 건너뜀
    func setAnimationPreviewCache(_ image: UIImage?) {
        cachedPreviewImage = image
    }

    private var cachedPreviewImage: UIImage?

    /// 화면 밖 셀의 무거운 리소스 해제 — ViewController의 didEndDisplaying에서 호출
    func clearOffscreenResources() {
        animationEffectView?.subviews.forEach { $0.removeFromSuperview() }
        animationEffectView?.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        cardView.layer.shouldRasterize = false
    }

    private let cardView: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 16
        v.clipsToBounds = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let previewContainer: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 10
        v.clipsToBounds = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private var previewGradientLayer: CAGradientLayer?
    private var previewPatternView: UIView?
    private var animationEffectView: UIView?
    private var currentPreviewThemeId: String?
    // ★ v3: 애니메이션 라이프사이클 관리
    /// 현재 셀이 보유한 테마 (애니메이션 재시작 시 참조)
    private var currentAnimTheme: KeyboardTheme?

    /// 애니메이션 활성 상태 (willDisplay/didEndDisplaying 전환)
    private var isAnimating = false

    private var keyLabels: [[UILabel]] = []
    private var specialKeyLabels: [UILabel] = []
    private var bottomKeyLabels: [UILabel] = []

    private var rowStacks: [UIStackView] = []
    private var bottomRow: UIView!

    private let nameLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 13, weight: .bold)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let subtitleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 10)
        l.textColor = .secondaryLabel
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let colorDotsStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 4
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()
    private var dotViews: [UIView] = []

    private let checkmark: UIImageView = {
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .bold)
        let iv = UIImageView(image: UIImage(systemName: "checkmark.circle.fill", withConfiguration: config))
        iv.tintColor = AppColors.tierAccent
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.isHidden = true
        return iv
    }()

    private let lockOverlay: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor(white: 0, alpha: 0.35)
        v.isHidden = true
        v.isUserInteractionEnabled = false
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let lockIcon: UIImageView = {
        let config = UIImage.SymbolConfiguration(pointSize: 28, weight: .medium)
        let iv = UIImageView(image: UIImage(systemName: "lock.fill", withConfiguration: config))
        iv.tintColor = .white
        iv.isUserInteractionEnabled = false
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        // 스케일 애니메이션 잔여 transform 초기화
        transform = .identity
        contentView.transform = .identity
        layer.removeAllAnimations()
        contentView.layer.removeAllAnimations()
        // 래스터화 상태 리셋 — 변환된 상태로 캡처 방지
        cardView.layer.shouldRasterize = false
        lockOverlay.isHidden = true
        checkmark.isHidden = true
        previewGradientLayer?.removeFromSuperlayer()
        previewGradientLayer = nil
        previewPatternView?.isHidden = true
        // ★ v3: 애니메이션 상태 리셋 + sublayer 정리
        isAnimating = false
        currentAnimTheme = nil
        // paused 상태에서 재사용될 수 있으므로 speed 복원
        if let effectLayer = animationEffectView?.layer, effectLayer.speed == 0 {
            effectLayer.speed = 1.0
            effectLayer.timeOffset = 0.0
            effectLayer.beginTime = 0.0
        }
        animationEffectView?.subviews.forEach { $0.removeFromSuperview() }
        animationEffectView?.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        animationEffectView?.isHidden = true
        currentPreviewThemeId = nil
        cardView.layer.borderColor = UIColor.clear.cgColor
        cardView.layer.borderWidth = 1

        // woodBlock cleanup — shadow 렌더링 경로 완전 해제
        for rowLabels in keyLabels {
            for label in rowLabels {
                label.clipsToBounds = true
                label.layer.borderWidth = 0
                label.layer.shadowOpacity = 0
                label.layer.shadowPath = nil
                label.layer.shadowColor = nil
                label.layer.shadowRadius = 0
            }
        }
        for label in specialKeyLabels {
            label.clipsToBounds = true
            label.layer.borderWidth = 0
            label.layer.shadowOpacity = 0
            label.layer.shadowPath = nil
            label.layer.shadowColor = nil
            label.layer.shadowRadius = 0
        }
        for label in bottomKeyLabels {
            label.clipsToBounds = true
            label.layer.borderWidth = 0
            label.layer.shadowOpacity = 0
            label.layer.shadowPath = nil
            label.layer.shadowColor = nil
            label.layer.shadowRadius = 0
        }

        // ★ v3: 스냅샷 캐시 미사용 — 관련 리셋 제거

        accessibilityLabel = nil
        accessibilityHint = nil
        accessibilityTraits = .button
    }

    private func hasLivePreviewAnimation(_ theme: KeyboardTheme) -> Bool {
        theme.hasWaveAnimation || theme.hasRainAnimation || theme.hasRippleAnimation
            || theme.hasStardustAnimation || theme.hasEdgeGlowAnimation
            || theme.hasSnowfallAnimation || theme.hasCherryBlossomAnimation
    }

    private func resolvePreviewLayoutIfNeeded() {
        guard previewContainer.bounds.width <= 0 || previewContainer.bounds.height <= 0 else { return }
        contentView.setNeedsLayout()
        contentView.layoutIfNeeded()
        previewContainer.setNeedsLayout()
        previewContainer.layoutIfNeeded()
    }

    private func updateRasterization(for theme: KeyboardTheme) {
        cardView.layer.shouldRasterize = false

        guard !hasLivePreviewAnimation(theme) else { return }
        let themeId = theme.id
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard self.currentPreviewThemeId == themeId else { return }
            guard self.cardView.bounds.width > 0, self.cardView.bounds.height > 0 else { return }
            self.cardView.layer.shouldRasterize = true
            self.cardView.layer.rasterizationScale = UIScreen.main.scale
        }
    }

    private func setupViews() {
        contentView.addSubview(cardView)
        cardView.addSubview(previewContainer)
        cardView.addSubview(nameLabel)
        cardView.addSubview(subtitleLabel)
        cardView.addSubview(colorDotsStack)
        cardView.addSubview(checkmark)

        for rowIndex in 0..<3 {
            let stack = UIStackView()
            stack.axis = .horizontal
            stack.spacing = 2
            stack.distribution = .fillEqually
            stack.translatesAutoresizingMaskIntoConstraints = false

            var labels: [UILabel] = []
            let keyCount = rowIndex == 0 ? 10 : (rowIndex == 1 ? 9 : 7)

            if rowIndex == 2 {
                let shiftLabel = makeKeyLabel(text: "⇧", isSpecial: true)
                stack.addArrangedSubview(shiftLabel)
                specialKeyLabels.append(shiftLabel)
            }

            for _ in 0..<keyCount {
                let label = makeKeyLabel(text: "", isSpecial: false)
                labels.append(label)
                stack.addArrangedSubview(label)
            }

            if rowIndex == 2 {
                let bsLabel = makeKeyLabel(text: "⌫", isSpecial: true)
                stack.addArrangedSubview(bsLabel)
                specialKeyLabels.append(bsLabel)
            }

            keyLabels.append(labels)
            rowStacks.append(stack)
            previewContainer.addSubview(stack)
        }

        // Bottom row
        bottomRow = UIView()
        bottomRow.translatesAutoresizingMaskIntoConstraints = false

        let numLabel = makeKeyLabel(text: "123", isSpecial: true)
        let globeLabel = makeKeyLabel(text: "🌐", isSpecial: true)
        let spaceLabel = makeKeyLabel(text: "space", isSpecial: false)
        let periodLabel = makeKeyLabel(text: ".", isSpecial: false)
        let returnLabel = makeKeyLabel(text: "↵", isSpecial: true)

        bottomKeyLabels = [numLabel, globeLabel, spaceLabel, periodLabel, returnLabel]

        for label in bottomKeyLabels {
            bottomRow.addSubview(label)
        }

        previewContainer.addSubview(bottomRow)

        // Lock overlay
        previewContainer.addSubview(lockOverlay)
        lockOverlay.addSubview(lockIcon)

        // Color dots
        for _ in 0..<4 {
            let dot = UIView()
            dot.layer.cornerRadius = 4
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.widthAnchor.constraint(equalToConstant: 8).isActive = true
            dot.heightAnchor.constraint(equalToConstant: 8).isActive = true
            dotViews.append(dot)
            colorDotsStack.addArrangedSubview(dot)
        }

        setupConstraints()
    }

    private func makeKeyLabel(text: String, isSpecial: Bool) -> UILabel {
        let l = UILabel()
        l.text = text
        l.textAlignment = .center
        l.font = .systemFont(ofSize: isSpecial ? 7 : 8.5, weight: isSpecial ? .semibold : .medium)
        l.layer.cornerRadius = 3
        l.clipsToBounds = true
        l.translatesAutoresizingMaskIntoConstraints = false
        l.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return l
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            previewContainer.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 10),
            previewContainer.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 10),
            previewContainer.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -10),

            nameLabel.topAnchor.constraint(equalTo: previewContainer.bottomAnchor, constant: 10),
            nameLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 12),
            nameLabel.trailingAnchor.constraint(equalTo: checkmark.leadingAnchor, constant: -4),

            subtitleLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            subtitleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 12),
            subtitleLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -12),

            colorDotsStack.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 6),
            colorDotsStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 12),
            colorDotsStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -10),

            checkmark.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -10),
            checkmark.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),

            lockOverlay.topAnchor.constraint(equalTo: previewContainer.topAnchor),
            lockOverlay.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
            lockOverlay.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
            lockOverlay.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor),

            lockIcon.centerXAnchor.constraint(equalTo: lockOverlay.centerXAnchor),
            lockIcon.centerYAnchor.constraint(equalTo: lockOverlay.centerYAnchor),
        ])

        // Keyboard rows layout
        for (i, stack) in rowStacks.enumerated() {
            let hPadding: CGFloat = i == 2 ? 2 : (i == 1 ? 4 : 4)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor, constant: hPadding),
                stack.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor, constant: -hPadding),
            ])
            if i == 0 {
                stack.topAnchor.constraint(equalTo: previewContainer.topAnchor, constant: 6).isActive = true
            } else {
                stack.topAnchor.constraint(equalTo: rowStacks[i - 1].bottomAnchor, constant: 3).isActive = true
            }
        }

        // Bottom row container
        NSLayoutConstraint.activate([
            bottomRow.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor, constant: 4),
            bottomRow.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor, constant: -4),
            bottomRow.topAnchor.constraint(equalTo: rowStacks.last!.bottomAnchor, constant: 3),
            bottomRow.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor, constant: -6),
        ])

        // Bottom row labels — pure Auto Layout chaining + ratio constraints
        let spacing: CGFloat = 2
        let numL = bottomKeyLabels[0]
        let globeL = bottomKeyLabels[1]
        let spaceL = bottomKeyLabels[2]
        let periodL = bottomKeyLabels[3]
        let returnL = bottomKeyLabels[4]

        NSLayoutConstraint.activate([
            numL.topAnchor.constraint(equalTo: bottomRow.topAnchor),
            numL.bottomAnchor.constraint(equalTo: bottomRow.bottomAnchor),
            globeL.topAnchor.constraint(equalTo: bottomRow.topAnchor),
            globeL.bottomAnchor.constraint(equalTo: bottomRow.bottomAnchor),
            spaceL.topAnchor.constraint(equalTo: bottomRow.topAnchor),
            spaceL.bottomAnchor.constraint(equalTo: bottomRow.bottomAnchor),
            periodL.topAnchor.constraint(equalTo: bottomRow.topAnchor),
            periodL.bottomAnchor.constraint(equalTo: bottomRow.bottomAnchor),
            returnL.topAnchor.constraint(equalTo: bottomRow.topAnchor),
            returnL.bottomAnchor.constraint(equalTo: bottomRow.bottomAnchor),

            numL.leadingAnchor.constraint(equalTo: bottomRow.leadingAnchor),
            globeL.leadingAnchor.constraint(equalTo: numL.trailingAnchor, constant: spacing),
            spaceL.leadingAnchor.constraint(equalTo: globeL.trailingAnchor, constant: spacing),
            periodL.leadingAnchor.constraint(equalTo: spaceL.trailingAnchor, constant: spacing),
            returnL.leadingAnchor.constraint(equalTo: periodL.trailingAnchor, constant: spacing),
            returnL.trailingAnchor.constraint(equalTo: bottomRow.trailingAnchor),

            globeL.widthAnchor.constraint(equalTo: numL.widthAnchor, multiplier: 0.8),
            spaceL.widthAnchor.constraint(equalTo: numL.widthAnchor, multiplier: 4.0),
            periodL.widthAnchor.constraint(equalTo: numL.widthAnchor, multiplier: 0.6),
            returnL.widthAnchor.constraint(equalTo: numL.widthAnchor, multiplier: 1.2),
        ])

        cardView.layer.borderWidth = 1
        cardView.layer.borderColor = UIColor.clear.cgColor
    }

    func configure(theme: KeyboardTheme, isSelected: Bool, isLocked: Bool) {
        currentPreviewThemeId = theme.id
        cardView.layer.shouldRasterize = false
        resolvePreviewLayoutIfNeeded()
        cardView.backgroundColor = AppColors.card

        // 1. Gradient background
        previewContainer.backgroundColor = theme.keyboardBackground
        if theme.hasGradient, let colors = theme.gradientColors {
            if previewGradientLayer == nil {
                let gl = CAGradientLayer()
                previewContainer.layer.insertSublayer(gl, at: 0)
                previewGradientLayer = gl
            }
            previewGradientLayer?.colors = colors.map { $0.cgColor }
            previewGradientLayer?.locations = theme.gradientLocations
            previewGradientLayer?.startPoint = theme.gradientDirection.startPoint
            previewGradientLayer?.endPoint = theme.gradientDirection.endPoint
            previewContainer.layoutIfNeeded()
            previewGradientLayer?.frame = previewContainer.bounds
        } else {
            previewGradientLayer?.removeFromSuperlayer()
            previewGradientLayer = nil
            previewContainer.backgroundColor = theme.keyboardBackground
        }

        // 2. Pattern overlay
        if theme.hasPattern {
            if previewPatternView == nil {
                let pv = UIView()
                pv.isUserInteractionEnabled = false
                pv.translatesAutoresizingMaskIntoConstraints = false
                previewContainer.insertSubview(pv, belowSubview: lockOverlay)
                NSLayoutConstraint.activate([
                    pv.topAnchor.constraint(equalTo: previewContainer.topAnchor),
                    pv.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
                    pv.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
                    pv.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor),
                ])
                previewPatternView = pv
            }
            previewContainer.layoutIfNeeded()
            if let img = ThemePatternRenderer.patternImage(
                style: theme.patternStyle, tint: theme.patternTint,
                opacity: theme.patternOpacity, size: CGSize(width: 64, height: 64)
            ) {
                previewPatternView?.backgroundColor = UIColor(patternImage: img)
                previewPatternView?.isHidden = false
            }
        } else {
            previewPatternView?.isHidden = true
        }

        // 2.5. Animation effect overlay (정적 프리뷰)
        configureAnimationPreview(theme: theme)

        // 3. Key labels by language
        let lang = LocalizationManager.shared.currentLanguage.rawValue
        let layout = PreviewKeyboardLayout.rows(for: lang)
        let bottom = PreviewKeyboardLayout.bottomRow(for: lang)

        let rows = [layout.row1, layout.row2, layout.row3]
        for (i, rowLabels) in keyLabels.enumerated() {
            for (j, label) in rowLabels.enumerated() {
                label.text = j < rows[i].count ? rows[i][j] : ""
                switch theme.keyVisualStyle {
                case .solid:
                    label.backgroundColor = theme.keyBackground
                case .translucent(let alpha, let tint):
                    label.backgroundColor = tint.withAlphaComponent(alpha)
                case .woodBlock(let borderColor, let shadowColor, _):
                    label.backgroundColor = theme.keyBackground
                    label.layer.borderWidth = 0.5
                    label.layer.borderColor = borderColor.cgColor
                    label.clipsToBounds = false
                    label.layer.shadowColor = shadowColor.cgColor
                    label.layer.shadowOffset = CGSize(width: 0, height: 1.5)
                    label.layer.shadowRadius = 0.8
                    label.layer.shadowOpacity = 1.0
                    label.layer.shadowPath = UIBezierPath(roundedRect: label.bounds, cornerRadius: label.layer.cornerRadius).cgPath
                case .edgeGlow(let borderColor, let glowColor):
                    label.backgroundColor = .clear
                    // ★ Fix: 프리뷰 키 간격(2pt)에서 글로우 블리딩 방지
                    label.layer.borderWidth = 0.8
                    label.layer.borderColor = borderColor.withAlphaComponent(0.4).cgColor
                    label.clipsToBounds = false
                    label.layer.shadowColor = glowColor.cgColor
                    label.layer.shadowOffset = .zero
                    label.layer.shadowRadius = 0.8
                    label.layer.shadowOpacity = 0.15
                    label.layer.shadowPath = UIBezierPath(roundedRect: label.bounds, cornerRadius: label.layer.cornerRadius).cgPath
                case .frostedGlass(let bgAlpha, let borderColor, _):
                    label.backgroundColor = UIColor(hex: "#192846").withAlphaComponent(bgAlpha)
                    label.layer.borderWidth = 0.5
                    label.layer.borderColor = borderColor.cgColor
                    label.clipsToBounds = false
                    label.layer.shadowColor = UIColor(red: 180/255, green: 200/255, blue: 240/255, alpha: 1).cgColor
                    label.layer.shadowOffset = .zero
                    label.layer.shadowRadius = 1.0
                    label.layer.shadowOpacity = 0.05
                    label.layer.shadowPath = UIBezierPath(roundedRect: label.bounds, cornerRadius: label.layer.cornerRadius).cgPath
                }
                label.textColor = theme.keyTextColor
            }
        }

        for label in specialKeyLabels {
            switch theme.specialKeyVisualStyle {
            case .solid:
                label.backgroundColor = theme.specialKeyBackground
            case .translucent(let alpha, let tint):
                label.backgroundColor = tint.withAlphaComponent(alpha)
            case .woodBlock(let borderColor, let shadowColor, _):
                label.backgroundColor = theme.specialKeyBackground
                label.layer.borderWidth = 0.5
                label.layer.borderColor = borderColor.cgColor
                label.clipsToBounds = false
                label.layer.shadowColor = shadowColor.cgColor
                label.layer.shadowOffset = CGSize(width: 0, height: 1.5)
                label.layer.shadowRadius = 0.8
                label.layer.shadowOpacity = 1.0
                label.layer.shadowPath = UIBezierPath(roundedRect: label.bounds, cornerRadius: label.layer.cornerRadius).cgPath
            case .edgeGlow(let borderColor, let glowColor):
                label.backgroundColor = .clear
                // ★ Fix: 프리뷰 키 간격(2pt)에서 글로우 블리딩 방지
                label.layer.borderWidth = 0.8
                label.layer.borderColor = borderColor.withAlphaComponent(0.4).cgColor
                label.clipsToBounds = false
                label.layer.shadowColor = glowColor.cgColor
                label.layer.shadowOffset = .zero
                label.layer.shadowRadius = 0.8
                label.layer.shadowOpacity = 0.15
                label.layer.shadowPath = UIBezierPath(roundedRect: label.bounds, cornerRadius: label.layer.cornerRadius).cgPath
            case .frostedGlass(let bgAlpha, let borderColor, _):
                label.backgroundColor = UIColor(hex: "#192846").withAlphaComponent(bgAlpha)
                label.layer.borderWidth = 0.5
                label.layer.borderColor = borderColor.cgColor
                label.clipsToBounds = false
                label.layer.shadowColor = UIColor(red: 180/255, green: 200/255, blue: 240/255, alpha: 1).cgColor
                label.layer.shadowOffset = .zero
                label.layer.shadowRadius = 1.0
                label.layer.shadowOpacity = 0.05
                label.layer.shadowPath = UIBezierPath(roundedRect: label.bounds, cornerRadius: label.layer.cornerRadius).cgPath
            }
            label.textColor = theme.keyTextColor
        }

        bottomKeyLabels[0].text = bottom.numKey
        bottomKeyLabels[2].text = bottom.spaceLabel
        for (i, label) in bottomKeyLabels.enumerated() {
            let isSpecial = (i == 0 || i == 1 || i == 4)
            if isSpecial {
                switch theme.specialKeyVisualStyle {
                case .solid: label.backgroundColor = theme.specialKeyBackground
                case .translucent(let a, let t): label.backgroundColor = t.withAlphaComponent(a)
                case .woodBlock(let borderColor, let shadowColor, _):
                    label.backgroundColor = theme.specialKeyBackground
                    label.layer.borderWidth = 0.5
                    label.layer.borderColor = borderColor.cgColor
                    label.clipsToBounds = false
                    label.layer.shadowColor = shadowColor.cgColor
                    label.layer.shadowOffset = CGSize(width: 0, height: 1.5)
                    label.layer.shadowRadius = 0.8
                    label.layer.shadowOpacity = 1.0
                    label.layer.shadowPath = UIBezierPath(roundedRect: label.bounds, cornerRadius: label.layer.cornerRadius).cgPath
                case .edgeGlow(let borderColor, let glowColor):
                    label.backgroundColor = .clear
                    // ★ Fix: 프리뷰 키 간격(2pt)에서 글로우 블리딩 방지
                    label.layer.borderWidth = 0.8
                    label.layer.borderColor = borderColor.withAlphaComponent(0.4).cgColor
                    label.clipsToBounds = false
                    label.layer.shadowColor = glowColor.cgColor
                    label.layer.shadowOffset = .zero
                    label.layer.shadowRadius = 0.8
                    label.layer.shadowOpacity = 0.15
                    label.layer.shadowPath = UIBezierPath(roundedRect: label.bounds, cornerRadius: label.layer.cornerRadius).cgPath
                case .frostedGlass(let bgAlpha, let borderColor, _):
                    label.backgroundColor = UIColor(hex: "#192846").withAlphaComponent(bgAlpha)
                    label.layer.borderWidth = 0.5
                    label.layer.borderColor = borderColor.cgColor
                    label.clipsToBounds = false
                    label.layer.shadowColor = UIColor(red: 180/255, green: 200/255, blue: 240/255, alpha: 1).cgColor
                    label.layer.shadowOffset = .zero
                    label.layer.shadowRadius = 1.0
                    label.layer.shadowOpacity = 0.05
                    label.layer.shadowPath = UIBezierPath(roundedRect: label.bounds, cornerRadius: label.layer.cornerRadius).cgPath
                }
            } else {
                switch theme.keyVisualStyle {
                case .solid: label.backgroundColor = theme.keyBackground
                case .translucent(let a, let t): label.backgroundColor = t.withAlphaComponent(a)
                case .woodBlock(let borderColor, let shadowColor, _):
                    label.backgroundColor = theme.keyBackground
                    label.layer.borderWidth = 0.5
                    label.layer.borderColor = borderColor.cgColor
                    label.clipsToBounds = false
                    label.layer.shadowColor = shadowColor.cgColor
                    label.layer.shadowOffset = CGSize(width: 0, height: 1.5)
                    label.layer.shadowRadius = 0.8
                    label.layer.shadowOpacity = 1.0
                    label.layer.shadowPath = UIBezierPath(roundedRect: label.bounds, cornerRadius: label.layer.cornerRadius).cgPath
                case .edgeGlow(let borderColor, let glowColor):
                    label.backgroundColor = .clear
                    // ★ Fix: 프리뷰 키 간격(2pt)에서 글로우 블리딩 방지
                    label.layer.borderWidth = 0.8
                    label.layer.borderColor = borderColor.withAlphaComponent(0.4).cgColor
                    label.clipsToBounds = false
                    label.layer.shadowColor = glowColor.cgColor
                    label.layer.shadowOffset = .zero
                    label.layer.shadowRadius = 0.8
                    label.layer.shadowOpacity = 0.15
                    label.layer.shadowPath = UIBezierPath(roundedRect: label.bounds, cornerRadius: label.layer.cornerRadius).cgPath
                case .frostedGlass(let bgAlpha, let borderColor, _):
                    label.backgroundColor = UIColor(hex: "#192846").withAlphaComponent(bgAlpha)
                    label.layer.borderWidth = 0.5
                    label.layer.borderColor = borderColor.cgColor
                    label.clipsToBounds = false
                    label.layer.shadowColor = UIColor(red: 180/255, green: 200/255, blue: 240/255, alpha: 1).cgColor
                    label.layer.shadowOffset = .zero
                    label.layer.shadowRadius = 1.0
                    label.layer.shadowOpacity = 0.05
                    label.layer.shadowPath = UIBezierPath(roundedRect: label.bounds, cornerRadius: label.layer.cornerRadius).cgPath
                }
            }
            label.textColor = theme.keyTextColor
        }

        // 4. Theme info
        nameLabel.text = theme.localizedDisplayName
        nameLabel.textColor = isLocked ? AppColors.textMuted : AppColors.text

        let englishName = theme.id
            .replacingOccurrences(of: "premium_", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
        subtitleLabel.text = englishName
        subtitleLabel.textColor = AppColors.textMuted

        let dotColors = [theme.keyboardBackground, theme.keyBackground, theme.specialKeyBackground, theme.keyTextColor]
        for (i, dot) in dotViews.enumerated() where i < dotColors.count {
            dot.backgroundColor = dotColors[i]
            dot.layer.borderWidth = 0.5
            dot.layer.borderColor = AppColors.border.cgColor
        }

        // 5. Lock/selection state
        lockOverlay.isHidden = !isLocked
        checkmark.isHidden = isLocked || !isSelected

        if isLocked {
            cardView.layer.borderColor = AppColors.border.cgColor
            cardView.layer.borderWidth = 1
        } else {
            cardView.layer.borderColor = isSelected ? AppColors.tierAccent.cgColor : AppColors.border.cgColor
            cardView.layer.borderWidth = isSelected ? 2.5 : 1
        }

        // 6. VoiceOver
        isAccessibilityElement = true
        if isLocked {
            accessibilityLabel = "\(theme.localizedDisplayName), \(L("theme.section_premium")), \(L("accessibility.locked"))"
            accessibilityHint = L("accessibility.theme_locked_hint")
            accessibilityTraits = .button
        } else if isSelected {
            accessibilityLabel = "\(theme.localizedDisplayName), \(L("accessibility.selected"))"
            accessibilityTraits = [.button, .selected]
        } else {
            accessibilityLabel = theme.localizedDisplayName
            accessibilityTraits = .button
            accessibilityHint = L("accessibility.theme_select_hint")
        }

        updateRasterization(for: theme)
    }

    // MARK: - ★ v3 Animation Lifecycle

    /// 화면에 보이는 셀의 애니메이션 시작/재개
    func startAnimations() {
        guard let effectView = animationEffectView,
              !effectView.isHidden,
              currentAnimTheme != nil else { return }
        guard !isAnimating else { return }
        isAnimating = true

        // effectView.layer가 paused 상태(speed==0)이면 resume만
        if effectView.layer.speed == 0 {
            resumeLayerAnimations(effectView.layer)
        }
        // speed > 0 이면 이미 동작 중이거나 새로 생성된 상태 → 추가 작업 불필요
    }

    /// 화면 밖으로 나간 셀의 애니메이션 일시정지
    func stopAnimations() {
        guard let effectView = animationEffectView else { return }
        isAnimating = false

        // 이미 paused 상태면 skip
        guard effectView.layer.speed != 0 else { return }
        pauseLayerAnimations(effectView.layer)
    }

    /// parent layer만 pause — sublayer는 Core Animation 트리 구조에 의해 자동 freeze
    private func pauseLayerAnimations(_ layer: CALayer) {
        let pausedTime = layer.convertTime(CACurrentMediaTime(), from: nil)
        layer.speed = 0.0
        layer.timeOffset = pausedTime
    }

    /// parent layer만 resume — sublayer는 자동 unfreeze
    private func resumeLayerAnimations(_ layer: CALayer) {
        let pausedTime = layer.timeOffset
        layer.speed = 1.0
        layer.timeOffset = 0.0
        layer.beginTime = 0.0
        let timeSincePause = layer.convertTime(CACurrentMediaTime(), from: nil) - pausedTime
        layer.beginTime = timeSincePause
    }

    // MARK: - Animation Preview Effects

    private func configureAnimationPreview(theme: KeyboardTheme) {
        guard theme.hasWaveAnimation || theme.hasRainAnimation || theme.hasRippleAnimation
              || theme.hasStardustAnimation || theme.hasEdgeGlowAnimation || theme.hasSnowfallAnimation
              || theme.hasCherryBlossomAnimation else {
            animationEffectView?.isHidden = true
            currentAnimTheme = nil  // ★ v3: 비-애니메이션 테마
            return
        }

        // ★ v3: 테마 저장 (애니메이션 재시작 시 참조)
        currentAnimTheme = theme

        if animationEffectView == nil {
            let v = UIView()
            v.isUserInteractionEnabled = false
            v.translatesAutoresizingMaskIntoConstraints = false
            v.clipsToBounds = true
            previewContainer.insertSubview(v, belowSubview: lockOverlay)
            NSLayoutConstraint.activate([
                v.topAnchor.constraint(equalTo: previewContainer.topAnchor),
                v.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
                v.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
                v.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor),
            ])
            animationEffectView = v
        }

        previewContainer.layoutIfNeeded()
        animationEffectView?.subviews.forEach { $0.removeFromSuperview() }
        animationEffectView?.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        animationEffectView?.isHidden = false

        guard let effectView = animationEffectView else { return }

        // ★ v3: 라이브 애니메이션 — 캐시 스냅샷 미사용, 직접 레이어 생성
        if theme.hasWaveAnimation {
            addWavePreviewEffect(to: effectView, theme: theme)
        } else if theme.hasRainAnimation {
            addRainPreviewEffect(to: effectView, theme: theme)
        } else if theme.hasRippleAnimation {
            addRipplePreviewEffect(to: effectView, theme: theme)
        } else if theme.hasStardustAnimation {
            addStardustPreviewEffect(to: effectView, theme: theme)
        } else if theme.hasEdgeGlowAnimation {
            addEdgeGlowPreviewEffect(to: effectView, theme: theme)
        } else if theme.hasSnowfallAnimation {
            addSnowfallPreviewEffect(to: effectView, theme: theme)
        } else if theme.hasCherryBlossomAnimation {
            addCherryBlossomPreviewEffect(to: effectView, theme: theme)
        }

        // ★ v3: 레이어 생성 완료 후 다음 프레임에서 애니메이션 시작
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.startAnimations()
        }
    }

    private func addWavePreviewEffect(to view: UIView, theme: KeyboardTheme) {
        let glowLayer = CAGradientLayer()
        glowLayer.frame = view.bounds.isEmpty ? CGRect(x: 0, y: 0, width: 168, height: 130) : view.bounds
        glowLayer.colors = [
            UIColor.clear.cgColor,
            UIColor.clear.cgColor,
            theme.keyTextColor.withAlphaComponent(0.12).cgColor,
            theme.keyTextColor.withAlphaComponent(0.20).cgColor,
            theme.keyTextColor.withAlphaComponent(0.12).cgColor,
            UIColor.clear.cgColor,
            UIColor.clear.cgColor,
        ]
        glowLayer.locations = [0.0, 0.25, 0.38, 0.45, 0.52, 0.65, 1.0]
        glowLayer.startPoint = CGPoint(x: 0, y: 0)
        glowLayer.endPoint = CGPoint(x: 1, y: 1)
        view.layer.addSublayer(glowLayer)
        // ★ v3: gradient locations 애니메이션 — gradient가 레이어 안에서 sweep
        // 현재 locations: [0.0, 0.25, 0.38, 0.45, 0.52, 0.65, 1.0]
        // 밝은 영역(0.38-0.52)을 좌→우로 이동시킴
        let locAnim = CABasicAnimation(keyPath: "locations")
        locAnim.fromValue = [0.0, 0.05, 0.15, 0.22, 0.29, 0.40, 1.0] as [NSNumber]
        locAnim.toValue   = [0.0, 0.60, 0.71, 0.78, 0.85, 0.95, 1.0] as [NSNumber]
        locAnim.duration = 2.5
        locAnim.repeatCount = .infinity
        locAnim.autoreverses = true
        locAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        locAnim.isRemovedOnCompletion = false
        glowLayer.add(locAnim, forKey: "wave_preview_anim")
    }

    // ★ v1: 디지털 레인 프리뷰 — 실제 키보드처럼 위→아래 연속 낙하
    // 구현 원리:
    //   - 10개 컬럼, 각 컬럼에 Trail A + Trail B (이중 트레일)
    //   - 각 트레일은 UIView 컨테이너 안에 12개 UILabel(카타카나/숫자)
    //   - CABasicAnimation(position.y)로 컨테이너를 위→아래로 연속 이동
    //   - Trail B는 Trail A 대비 반 주기(duration/2) 늦게 시작 → 끊김 없는 커버리지
    //   - animationEffectView.clipsToBounds=true이므로 프리뷰 밖 문자는 자동 클리핑
    //
    // 리소스 비교 (기존 vs 신규):
    //   기존: ~108 UILabel + ~108 CAAnimationGroup(각 2개 애니메이션) = 324 애니메이션 객체
    //   신규: 240 UILabel + 20 CABasicAnimation = 20 애니메이션 객체 (94% 감소)
    //   → 라벨 수는 증가하지만 애니메이션 수 대폭 감소로 GPU 부하 경감
    private func addRainPreviewEffect(to view: UIView, theme: KeyboardTheme) {
        let chars = "アイウエオカキクケコサシスセソ0123456789"
        let tint = theme.keyTextColor
        let previewH: CGFloat = view.bounds.isEmpty ? 130 : view.bounds.height

        let charH: CGFloat = 9.0       // 문자 간 세로 간격
        let fontSize: CGFloat = 6.0    // 프리뷰용 축소 폰트
        let charsPerTrail = 12         // 트레일당 문자 수 (trailHeight = 108pt)
        let trailHeight = CGFloat(charsPerTrail) * charH  // 108pt

        // 10개 컬럼 정의: (x좌표, 낙하 duration초, 시작 지연초)
        // duration이 작을수록 빠름 — 실제 키보드의 speed 차이를 재현
        let columnDefs: [(x: CGFloat, dur: Double, delay: Double)] = [
            (6,   3.2, 0.0),   (22,  4.8, 0.9),   (38,  2.8, 1.6),
            (56,  5.2, 0.4),   (72,  3.5, 2.1),   (90,  4.3, 0.7),
            (108, 3.0, 1.3),   (126, 5.0, 1.9),   (144, 3.6, 0.2),
            (160, 4.5, 1.1),
        ]

        for colDef in columnDefs {
            // Trail A와 Trail B — 반 주기 오프셋으로 연속 커버리지 보장
            for trailIdx in 0..<2 {
                let trailContainer = UIView()
                trailContainer.frame = CGRect(x: colDef.x, y: 0, width: 10, height: trailHeight)
                trailContainer.isUserInteractionEnabled = false

                for i in 0..<charsPerTrail {
                    // 의사 랜덤 문자 선택 (컬럼 x + 인덱스 + 트레일로 시드)
                    let charIndex = ((Int(colDef.x) &* 7) &+ (i &* 13) &+ (trailIdx &* 31)) % chars.count
                    let char = chars[chars.index(chars.startIndex, offsetBy: charIndex)]

                    let label = UILabel()
                    label.text = String(char)
                    label.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
                    label.textAlignment = .center

                    // 색상 그라디언트: 하단(head) 밝음 → 상단(tail) 어두움
                    // 실제 키보드의 20단계 colorPalette를 단순화
                    let t = CGFloat(i) / CGFloat(charsPerTrail - 1) // 0=상단(tail), 1=하단(head)
                    let alpha: CGFloat
                    if t > 0.85 {
                        // Head 영역 — 가장 밝은 초록
                        alpha = 0.45 + (t - 0.85) * 3.3   // 0.45 → ~0.94
                    } else if t > 0.50 {
                        // 중간 트레일 — 중간 밝기
                        alpha = 0.15 + (t - 0.50) * 0.86  // 0.15 → 0.45
                    } else {
                        // Tail 영역 — 어두운 초록 (최소 0.03 유지)
                        alpha = max(0.03, t * 0.30)        // 0.03 → 0.15
                    }
                    label.textColor = tint.withAlphaComponent(alpha)

                    label.frame = CGRect(x: 0, y: CGFloat(i) * charH, width: 10, height: charH)
                    trailContainer.addSubview(label)
                }

                view.addSubview(trailContainer)

                // 낙하 애니메이션: 프리뷰 위 → 프리뷰 아래로 연속 이동
                // fromValue: 트레일 전체가 프리뷰 위에 (head가 y=0에 닿기 직전)
                // toValue: 트레일 전체가 프리뷰 아래에 (tail이 y=previewH를 벗어남)
                let anim = CABasicAnimation(keyPath: "position.y")
                anim.fromValue = -(trailHeight / 2)            // 트레일 중심이 프리뷰 위
                anim.toValue = previewH + (trailHeight / 2)    // 트레일 중심이 프리뷰 아래
                anim.duration = colDef.dur
                anim.repeatCount = .infinity
                anim.timingFunction = CAMediaTimingFunction(name: .linear)
                anim.isRemovedOnCompletion = false

                // Trail B는 반 주기(duration/2) 늦게 시작 → 끊김 없는 연속 낙하
                // Trail A가 프리뷰 하단을 벗어날 때 Trail B가 프리뷰 중간에 위치
                let trailDelay = colDef.delay + (trailIdx == 1 ? colDef.dur / 2.0 : 0)
                anim.beginTime = CACurrentMediaTime() + trailDelay
                anim.fillMode = .backwards  // beginTime 이전에 fromValue 적용 (깜빡임 방지)

                trailContainer.layer.add(anim, forKey: "rain_fall_\(trailIdx)")
            }
        }
    }

    private func addRipplePreviewEffect(to view: UIView, theme: KeyboardTheme) {
        let tint = theme.patternTint
        let center = CGPoint(x: 70, y: 60)

        let radii: [(r: CGFloat, alpha: CGFloat, width: CGFloat)] = [
            (22, 0.28, 1.2),
            (38, 0.16, 1.0),
            (55, 0.08, 0.8),
        ]

        for ring in radii {
            let circleLayer = CAShapeLayer()
            let path = UIBezierPath(
                arcCenter: center,
                radius: ring.r,
                startAngle: 0,
                endAngle: 2 * .pi,
                clockwise: true
            )
            circleLayer.path = path.cgPath
            circleLayer.fillColor = UIColor.clear.cgColor
            circleLayer.strokeColor = tint.withAlphaComponent(ring.alpha).cgColor
            circleLayer.lineWidth = ring.width
            view.layer.addSublayer(circleLayer)
            // ★ v3: 개별 ring에 scale + opacity 애니메이션
            // path가 arcCenter=(70,60) 기준으로 그려져 있으므로
            // layer의 bounds/position/anchorPoint를 설정하여 (70,60) 기준 scale 확보
            let layerWidth: CGFloat = view.bounds.isEmpty ? 168 : view.bounds.width
            let layerHeight: CGFloat = view.bounds.isEmpty ? 130 : view.bounds.height
            circleLayer.bounds = CGRect(x: 0, y: 0, width: layerWidth, height: layerHeight)
            circleLayer.position = CGPoint(x: layerWidth / 2, y: layerHeight / 2)
            // ★ v3 FIX: anchorPoint를 ripple center(70,60) 비율로 설정 → scale이 여기서 발생
            circleLayer.anchorPoint = CGPoint(x: 70.0 / layerWidth, y: 60.0 / layerHeight)
            // anchorPoint 변경으로 position이 자동 이동하므로, position을 ripple center로 재설정
            circleLayer.position = CGPoint(x: 70, y: 60)

            let scaleAnim = CABasicAnimation(keyPath: "transform.scale")
            scaleAnim.fromValue = 0.85
            scaleAnim.toValue = 1.15
            scaleAnim.duration = 2.0 + Double(ring.r) * 0.02  // 바깥 ring일수록 살짝 느리게
            scaleAnim.repeatCount = .infinity
            scaleAnim.autoreverses = true
            scaleAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            scaleAnim.isRemovedOnCompletion = false

            let opacityAnim = CABasicAnimation(keyPath: "opacity")
            opacityAnim.fromValue = 0.5
            opacityAnim.toValue = 1.0
            opacityAnim.duration = scaleAnim.duration
            opacityAnim.repeatCount = .infinity
            opacityAnim.autoreverses = true
            opacityAnim.isRemovedOnCompletion = false

            let group = CAAnimationGroup()
            group.animations = [scaleAnim, opacityAnim]
            group.duration = scaleAnim.duration
            group.repeatCount = .infinity
            group.isRemovedOnCompletion = false
            circleLayer.add(group, forKey: "ripple_preview_anim")
        }

        let glowLayer = CALayer()
        glowLayer.frame = CGRect(x: center.x - 12, y: center.y - 12, width: 24, height: 24)
        glowLayer.cornerRadius = 12
        glowLayer.backgroundColor = tint.withAlphaComponent(0.08).cgColor
        view.layer.addSublayer(glowLayer)
        // ★ v3: 중심 glow 맥동
        let glowPulse = CABasicAnimation(keyPath: "opacity")
        glowPulse.fromValue = 0.4
        glowPulse.toValue = 1.0
        glowPulse.duration = 1.5
        glowPulse.repeatCount = .infinity
        glowPulse.autoreverses = true
        glowPulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        glowPulse.isRemovedOnCompletion = false
        glowLayer.add(glowPulse, forKey: "ripple_glow_anim")
    }

    private func addStardustPreviewEffect(to view: UIView, theme: KeyboardTheme) {
        let tint = theme.keyTextColor

        let stars: [(x: CGFloat, y: CGFloat, size: CGFloat, alpha: CGFloat)] = [
            (12, 15, 2.0, 0.6), (35, 30, 1.5, 0.4), (60, 10, 2.5, 0.5),
            (85, 40, 1.8, 0.55), (110, 18, 2.0, 0.45), (140, 35, 1.5, 0.5),
            (160, 12, 2.2, 0.4), (20, 55, 1.8, 0.5), (50, 70, 2.0, 0.45),
            (75, 50, 1.5, 0.55), (100, 65, 2.5, 0.4), (130, 55, 1.8, 0.5),
            (155, 70, 2.0, 0.45), (45, 95, 1.5, 0.4),
        ]

        for star in stars {
            let dot = CALayer()
            dot.frame = CGRect(x: star.x, y: star.y, width: star.size, height: star.size)
            dot.cornerRadius = star.size / 2
            dot.backgroundColor = tint.withAlphaComponent(star.alpha).cgColor
            view.layer.addSublayer(dot)
            // ★ v3: 시차 반짝임
            let anim = CABasicAnimation(keyPath: "opacity")
            anim.fromValue = star.alpha  // CGFloat
            anim.toValue = max(star.alpha - 0.3, CGFloat(0.1))  // CGFloat 통일
            anim.duration = Double.random(in: 0.8...2.0)
            anim.repeatCount = .infinity
            anim.autoreverses = true
            anim.beginTime = CACurrentMediaTime() + Double.random(in: 0.0...1.5)
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            anim.isRemovedOnCompletion = false
            dot.add(anim, forKey: "stardust_preview_anim")
        }

        let burstCenter = CGPoint(x: 90, y: 35)
        let burstParticles: [(dx: CGFloat, dy: CGFloat)] = [
            (-6, -10), (4, -12), (10, -4), (-8, 3),
            (7, 7), (-3, -14), (12, -8), (-10, -6),
        ]

        for p in burstParticles {
            let dot = CALayer()
            dot.frame = CGRect(x: burstCenter.x + p.dx, y: burstCenter.y + p.dy, width: 1.5, height: 1.5)
            dot.cornerRadius = 0.75
            dot.backgroundColor = tint.withAlphaComponent(0.7).cgColor
            view.layer.addSublayer(dot)
            // ★ v3: burst 반짝임 (더 빠르게)
            let anim = CABasicAnimation(keyPath: "opacity")
            anim.fromValue = CGFloat(0.7)
            anim.toValue = CGFloat(0.2)
            anim.duration = Double.random(in: 0.5...1.2)
            anim.repeatCount = .infinity
            anim.autoreverses = true
            anim.beginTime = CACurrentMediaTime() + Double.random(in: 0.0...0.8)
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            anim.isRemovedOnCompletion = false
            dot.add(anim, forKey: "stardust_burst_anim")
        }
    }

    private func addEdgeGlowPreviewEffect(to view: UIView, theme: KeyboardTheme) {
        guard case .edgeGlow(_, let glowColor) = theme.keyVisualStyle else { return }

        let glowLayer = CAGradientLayer()
        glowLayer.frame = view.bounds.isEmpty ? CGRect(x: 0, y: 0, width: 168, height: 130) : view.bounds
        // ★ Fix: 그라디언트 오버레이 alpha 대폭 축소
        // 0.15 → 0.06: 은은한 빛 느낌만 유지, 키 배경이 색으로 채워지는 착시 제거
        glowLayer.colors = [
            UIColor.clear.cgColor,
            UIColor.clear.cgColor,
            glowColor.withAlphaComponent(0.03).cgColor,
            glowColor.withAlphaComponent(0.06).cgColor,
            glowColor.withAlphaComponent(0.03).cgColor,
            UIColor.clear.cgColor,
            UIColor.clear.cgColor,
        ]
        glowLayer.locations = [0.0, 0.20, 0.35, 0.42, 0.49, 0.60, 1.0]
        glowLayer.startPoint = CGPoint(x: 0, y: 0)
        glowLayer.endPoint = CGPoint(x: 1, y: 1)
        view.layer.addSublayer(glowLayer)
        // ★ v3: gradient locations 애니메이션 (Wave와 동일 패턴, 약간 느린 duration)
        // 현재 locations: [0.0, 0.20, 0.35, 0.42, 0.49, 0.60, 1.0]
        let locAnim = CABasicAnimation(keyPath: "locations")
        locAnim.fromValue = [0.0, 0.02, 0.10, 0.17, 0.24, 0.35, 1.0] as [NSNumber]
        locAnim.toValue   = [0.0, 0.65, 0.75, 0.82, 0.89, 0.98, 1.0] as [NSNumber]
        locAnim.duration = 3.0
        locAnim.repeatCount = .infinity
        locAnim.autoreverses = true
        locAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        locAnim.isRemovedOnCompletion = false
        glowLayer.add(locAnim, forKey: "edgeglow_preview_anim")
    }

    private func addSnowfallPreviewEffect(to view: UIView, theme: KeyboardTheme) {
        let flakes: [(x: CGFloat, y: CGFloat, size: CGFloat, alpha: CGFloat)] = [
            (8, 12, 2.5, 0.6), (28, 35, 1.8, 0.45), (48, 8, 3.0, 0.55),
            (65, 50, 2.0, 0.5), (85, 20, 3.5, 0.6), (108, 45, 2.2, 0.45),
            (130, 10, 2.8, 0.55), (150, 55, 1.5, 0.4), (18, 65, 2.5, 0.5),
            (40, 80, 3.0, 0.55), (58, 58, 1.8, 0.4), (78, 72, 2.5, 0.5),
            (98, 38, 2.0, 0.45), (118, 68, 3.0, 0.55), (140, 42, 2.2, 0.5),
            (158, 75, 1.8, 0.4), (25, 95, 2.5, 0.5), (50, 108, 3.2, 0.55),
            (72, 90, 2.0, 0.45), (95, 102, 2.8, 0.5), (115, 85, 1.5, 0.4),
            (138, 98, 3.0, 0.5), (155, 110, 2.5, 0.45), (35, 118, 2.0, 0.4),
        ]

        for flake in flakes {
            let dot = CALayer()
            dot.frame = CGRect(x: flake.x, y: flake.y, width: flake.size, height: flake.size)
            dot.cornerRadius = flake.size / 2
            dot.backgroundColor = UIColor.white.withAlphaComponent(flake.alpha).cgColor
            dot.shadowColor = UIColor.white.cgColor
            dot.shadowOffset = .zero
            dot.shadowRadius = flake.size * 0.4
            dot.shadowOpacity = Float(flake.alpha * 0.5)
            // shadowPath 명시 → 오프스크린 렌더링 회피
            dot.shadowPath = UIBezierPath(
                roundedRect: CGRect(x: 0, y: 0, width: flake.size, height: flake.size),
                cornerRadius: flake.size / 2
            ).cgPath
            view.layer.addSublayer(dot)
            dot.name = "snow_flake"  // ★ v3: 디버깅용 태깅

            // ★ v3: 개별 눈송이 falling + 좌우 흔들림
            let fallAnim = CABasicAnimation(keyPath: "position.y")
            fallAnim.fromValue = dot.position.y - 8
            fallAnim.toValue = dot.position.y + 8
            fallAnim.duration = Double.random(in: 2.0...3.5)
            fallAnim.repeatCount = .infinity
            fallAnim.autoreverses = true
            fallAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            fallAnim.isRemovedOnCompletion = false

            let swayAnim = CABasicAnimation(keyPath: "position.x")
            swayAnim.fromValue = dot.position.x - 3
            swayAnim.toValue = dot.position.x + 3
            swayAnim.duration = Double.random(in: 1.5...2.5)
            swayAnim.repeatCount = .infinity
            swayAnim.autoreverses = true
            swayAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            swayAnim.isRemovedOnCompletion = false

            let maxDur = max(fallAnim.duration, swayAnim.duration)
            let group = CAAnimationGroup()
            group.animations = [fallAnim, swayAnim]
            group.duration = maxDur
            group.repeatCount = .infinity
            group.beginTime = CACurrentMediaTime() + Double.random(in: 0.0...2.0)
            group.isRemovedOnCompletion = false
            dot.add(group, forKey: "snow_preview_anim")
        }
    }

    private func addCherryBlossomPreviewEffect(to view: UIView, theme: KeyboardTheme) {
        // 핑크 꽃잎 점 20개 (오른쪽 상단 → 왼쪽 하단 방향 분포)
        let petals: [(x: CGFloat, y: CGFloat, size: CGFloat, alpha: CGFloat)] = [
            (140, 8, 4.0, 0.7), (155, 15, 3.5, 0.6), (125, 20, 3.0, 0.55),
            (148, 28, 4.5, 0.65), (160, 5, 3.0, 0.5), (130, 12, 3.5, 0.6),
            (118, 35, 3.0, 0.5), (135, 42, 2.5, 0.45), (105, 50, 3.5, 0.55),
            (90, 55, 3.0, 0.5), (115, 60, 2.5, 0.4), (75, 65, 3.5, 0.5),
            (60, 72, 3.0, 0.45), (95, 78, 2.5, 0.4), (45, 85, 3.5, 0.5),
            (30, 90, 3.0, 0.45), (70, 95, 2.5, 0.35), (15, 100, 3.0, 0.4),
            (50, 108, 2.5, 0.35), (25, 115, 3.0, 0.3),
        ]

        let petalColors: [UIColor] = [
            UIColor(red: 1.0, green: 0.718, blue: 0.773, alpha: 1),
            UIColor(red: 1.0, green: 0.784, blue: 0.839, alpha: 1),
            UIColor(red: 1.0, green: 0.667, blue: 0.733, alpha: 1),
            UIColor(red: 1.0, green: 0.816, blue: 0.855, alpha: 1),
        ]

        for (i, petal) in petals.enumerated() {
            let dot = CAShapeLayer()
            // 간단한 타원 꽃잎 형태
            let path = UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: petal.size, height: petal.size * 1.3))
            dot.path = path.cgPath
            dot.fillColor = petalColors[i % petalColors.count].withAlphaComponent(petal.alpha).cgColor
            dot.position = CGPoint(x: petal.x, y: petal.y)
            dot.bounds = CGRect(x: 0, y: 0, width: petal.size, height: petal.size * 1.3)
            // 회전으로 자연스러운 흩날림 효과
            dot.transform = CATransform3DMakeRotation(CGFloat(i) * 0.5, 0, 0, 1)
            view.layer.addSublayer(dot)
            dot.name = "cherry_petal"  // ★ v3: 디버깅용 태깅

            // ★ v3: 꽃잎 흩날림 — 대각선 이동 + 살짝 회전
            let driftX = CABasicAnimation(keyPath: "position.x")
            driftX.fromValue = dot.position.x + 4
            driftX.toValue = dot.position.x - 4
            driftX.duration = Double.random(in: 2.5...4.0)
            driftX.repeatCount = .infinity
            driftX.autoreverses = true
            driftX.isRemovedOnCompletion = false

            let driftY = CABasicAnimation(keyPath: "position.y")
            driftY.fromValue = dot.position.y - 3
            driftY.toValue = dot.position.y + 3
            driftY.duration = Double.random(in: 2.0...3.5)
            driftY.repeatCount = .infinity
            driftY.autoreverses = true
            driftY.isRemovedOnCompletion = false

            let rotateAnim = CABasicAnimation(keyPath: "transform.rotation.z")
            rotateAnim.fromValue = CGFloat(i) * 0.5 - 0.15  // 기존 회전값 기준 흔들림
            rotateAnim.toValue = CGFloat(i) * 0.5 + 0.15
            rotateAnim.duration = Double.random(in: 1.8...3.0)
            rotateAnim.repeatCount = .infinity
            rotateAnim.autoreverses = true
            rotateAnim.isRemovedOnCompletion = false

            let maxDur = max(max(driftX.duration, driftY.duration), rotateAnim.duration)
            let group = CAAnimationGroup()
            group.animations = [driftX, driftY, rotateAnim]
            group.duration = maxDur
            group.repeatCount = .infinity
            group.beginTime = CACurrentMediaTime() + Double.random(in: 0.0...2.0)
            group.isRemovedOnCompletion = false
            dot.add(group, forKey: "cherry_preview_anim")
        }

        // 오른쪽 상단 꽃 클러스터 (핑크 원형 뭉치)
        let clusterDots: [(x: CGFloat, y: CGFloat, size: CGFloat, alpha: CGFloat)] = [
            (145, 5, 6.0, 0.5), (152, 12, 5.0, 0.6), (138, 10, 7.0, 0.55),
            (158, 3, 5.5, 0.45), (148, 18, 4.5, 0.5), (160, 10, 6.0, 0.4),
            (133, 5, 5.0, 0.5), (155, 22, 4.0, 0.45),
        ]

        for dot in clusterDots {
            let layer = CALayer()
            layer.frame = CGRect(x: dot.x, y: dot.y, width: dot.size, height: dot.size)
            layer.cornerRadius = dot.size / 2
            layer.backgroundColor = UIColor(red: 1.0, green: 0.80, blue: 0.85, alpha: dot.alpha).cgColor
            view.layer.addSublayer(layer)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewGradientLayer?.frame = previewContainer.bounds

        // animationEffectView의 글로우 레이어 프레임 업데이트
        if let effectView = animationEffectView {
            for sublayer in effectView.layer.sublayers ?? [] {
                if let gradientLayer = sublayer as? CAGradientLayer {
                    gradientLayer.frame = effectView.bounds
                }
            }
        }

        // Shadow path 갱신 — bounds 확정 후 재설정
        for rowLabels in keyLabels {
            for label in rowLabels {
                if label.layer.shadowOpacity > 0 {
                    label.layer.shadowPath = UIBezierPath(
                        roundedRect: label.bounds,
                        cornerRadius: label.layer.cornerRadius
                    ).cgPath
                }
            }
        }
        for label in specialKeyLabels {
            if label.layer.shadowOpacity > 0 {
                label.layer.shadowPath = UIBezierPath(
                    roundedRect: label.bounds,
                    cornerRadius: label.layer.cornerRadius
                ).cgPath
            }
        }
        for label in bottomKeyLabels {
            if label.layer.shadowOpacity > 0 {
                label.layer.shadowPath = UIBezierPath(
                    roundedRect: label.bounds,
                    cornerRadius: label.layer.cornerRadius
                ).cgPath
            }
        }

    }
}
