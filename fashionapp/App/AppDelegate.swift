import UIKit

/// Configures Firebase at the earliest UIKit lifecycle point so Analytics/Auth
/// never touch the default app before `FirebaseApp.configure()`.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        _ = FirebaseBootstrap.configureIfPossible()
        return true
    }
}
