import UIKit

class TabBarController: UITabBarController {

    override func viewDidLoad() {
        super.viewDidLoad()
        setupTabs()
        setupAppearance()
        NotificationCenter.default.addObserver(self, selector: #selector(handleLanguageChange), name: .languageDidChange, object: nil)
    }

    @objc private func handleLanguageChange() {
        let titles = [L("tab.home"), L("tab.ai_writer"), L("tab.history"), L("tab.theme"), L("tab.settings")]
        for (i, nav) in (viewControllers ?? []).enumerated() where i < titles.count {
            nav.tabBarItem.title = titles[i]
        }
    }

    private func setupTabs() {
        let homeVC = HomeViewController()
        let homeNav = UINavigationController(rootViewController: homeVC)
        homeNav.tabBarItem = UITabBarItem(
            title: L("tab.home"),
            image: UIImage(systemName: "house"),
            tag: 0
        )

        let aiWriterVC = AIWriterViewController()
        let aiWriterNav = UINavigationController(rootViewController: aiWriterVC)
        aiWriterNav.tabBarItem = UITabBarItem(
            title: L("tab.ai_writer"),
            image: UIImage(systemName: "star"),
            tag: 1
        )

        let historyVC = HistoryViewController()
        let historyNav = UINavigationController(rootViewController: historyVC)
        historyNav.tabBarItem = UITabBarItem(
            title: L("tab.history"),
            image: UIImage(systemName: "clock"),
            tag: 2
        )

        let themeVC = ThemeSelectionViewController()
        let themeNav = UINavigationController(rootViewController: themeVC)
        themeNav.tabBarItem = UITabBarItem(
            title: L("tab.theme"),
            image: UIImage(systemName: "paintpalette"),
            tag: 3
        )

        let settingsVC = SettingsViewController()
        let settingsNav = UINavigationController(rootViewController: settingsVC)
        settingsNav.tabBarItem = UITabBarItem(
            title: L("tab.settings"),
            image: UIImage(systemName: "gearshape"),
            tag: 4
        )

        viewControllers = [homeNav, aiWriterNav, historyNav, themeNav, settingsNav]
    }

    private func setupAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemChromeMaterial)
        appearance.backgroundColor = UIColor.white.withAlphaComponent(0.92)

        let normalAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: AppColors.textMuted]
        let selectedAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: AppColors.accent]

        appearance.stackedLayoutAppearance.normal.titleTextAttributes = normalAttrs
        appearance.stackedLayoutAppearance.normal.iconColor = AppColors.textMuted
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = selectedAttrs
        appearance.stackedLayoutAppearance.selected.iconColor = AppColors.accent

        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
    }
}
