import UIKit
import OSLog

// DEBUG TRACE: app lifecycle
private let appLog = Logger(
    subsystem: "com.translatorkeyboard.app.voice",
    category: "appdelegate"
)

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
        // DEBUG TRACE: app lifecycle
        appLog.debug("event=applicationDidEnterBackground")
        appServices.dictationRuntime.handleAppDidEnterBackground()
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // DEBUG TRACE: app lifecycle
        appLog.debug("event=applicationWillEnterForeground")
        appServices.dictationRuntime.handleAppWillEnterForeground()
    }

    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        // DEBUG TRACE: app lifecycle
        appLog.error("event=applicationDidReceiveMemoryWarning")
        appServices.dictationRuntime.handleMemoryWarning()
    }
}
