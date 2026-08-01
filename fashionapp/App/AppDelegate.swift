import UIKit
import FirebaseCore

/// Configures Firebase as soon as the adaptor constructs this object —
/// earlier than `didFinishLaunching`, so Analytics/Auth see a default app.
@objc(SylyoAppDelegate)
final class AppDelegate: NSObject, UIApplicationDelegate {
    override init() {
        super.init()
        _ = FirebaseBootstrap.configureIfPossible()
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        _ = FirebaseBootstrap.configureIfPossible()
        return true
    }
}
