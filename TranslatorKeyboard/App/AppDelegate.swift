import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    /// Process-level service container — survives scene lifecycle.
    let appServices = AppProcessServices()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Stale dictation cleanup on launch
        appServices.dictationRuntime.cleanupIfStale()
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        appServices.dictationRuntime.handleAppDidEnterBackground()
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        appServices.dictationRuntime.handleAppWillEnterForeground()
    }

    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        appServices.dictationRuntime.handleMemoryWarning()
    }
}
