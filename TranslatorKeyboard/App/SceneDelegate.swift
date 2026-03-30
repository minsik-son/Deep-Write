import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }
        window = UIWindow(windowScene: windowScene)
        let tabBarController = TabBarController()
        window?.rootViewController = tabBarController
        window?.makeKeyAndVisible()

        // 라이트/다크 모드 적용
        let isDark = UserDefaults(suiteName: AppConstants.appGroupIdentifier)?.bool(forKey: AppConstants.UserDefaultsKeys.appDarkMode) ?? false
        window?.overrideUserInterfaceStyle = isDark ? .dark : .light

        // 온보딩: 첫 실행 시 표시
        let defaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier) ?? UserDefaults.standard
        if !defaults.bool(forKey: AppConstants.UserDefaultsKeys.hasCompletedOnboarding) {
            let onboardingVC = OnboardingViewController()
            onboardingVC.modalPresentationStyle = .fullScreen
            tabBarController.present(onboardingVC, animated: false)
        }

        if let urlContext = connectionOptions.urlContexts.first {
            handleURL(urlContext.url, tabBar: tabBarController)
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }
        guard let tabBar = window?.rootViewController as? TabBarController else { return }
        handleURL(url, tabBar: tabBar)
    }

    private func handleURL(_ url: URL, tabBar: TabBarController) {
        guard url.scheme == "translatorkeyboard" else { return }

        switch url.host {
        case "settings":
            tabBar.selectedIndex = 4

        case "paywall":
            let paywallVC = PaywallViewController()
            paywallVC.modalPresentationStyle = .pageSheet
            let presenter = tabBar.presentedViewController ?? tabBar
            presenter.present(paywallVC, animated: true)

        case "reward-ad":
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let modeParam = components?.queryItems?.first(where: { $0.name == "mode" })?.value
            let mode: RewardMode = modeParam == "translation" ? .translation : .correction
            let rewardVC = RewardedAdsViewController(mode: mode)
            rewardVC.modalPresentationStyle = .fullScreen
            let presenter = tabBar.presentedViewController ?? tabBar
            presenter.present(rewardVC, animated: true)

        case "dictation":
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let queryItems = components?.queryItems ?? []

            guard let sessionParam = queryItems.first(where: { $0.name == "session" })?.value,
                  UUID(uuidString: sessionParam) != nil else {
                return
            }

            let localeParam = queryItems.first(where: { $0.name == "locale" })?.value ?? "en-US"
            guard DictationConstants.supportedLocales.contains(localeParam) else {
                return
            }

            // Verify command file matches
            let store = DictationSharedStore()
            guard let command = store.readCommand(),
                  command.sessionId == sessionParam,
                  command.action == .start,
                  command.locale == localeParam else {
                return
            }

            // Resolve process-level runtime from AppDelegate
            guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }
            let runtime = appDelegate.appServices.dictationRuntime

            let bootstrapVC = DictationBootstrapViewController()
            bootstrapVC.configure(sessionId: sessionParam, locale: localeParam, runtime: runtime)
            bootstrapVC.modalPresentationStyle = .fullScreen
            let presenter = tabBar.presentedViewController ?? tabBar
            presenter.present(bootstrapVC, animated: true)

        default:
            break
        }
    }
}
