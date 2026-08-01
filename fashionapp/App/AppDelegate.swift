import UIKit
import FirebaseCore
import FirebaseAnalytics

/// Owns app composition after Firebase is configured.
/// Subclasses `UIResponder` so GoogleUtilities recognizes a real UIApplicationDelegate.
@objc(SylyoAppDelegate)
final class AppDelegate: UIResponder, UIApplicationDelegate {
    /// Created only after `FirebaseApp.configure()` succeeds (or is skipped safely).
    private(set) var sharedContainer: AppContainer

    override init() {
        // Must run before Auth / Analytics / Firestore touch the default app.
        _ = FirebaseBootstrap.configureIfPossible()
        sharedContainer = AppContainer()
        super.init()
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        _ = FirebaseBootstrap.configureIfPossible()
        // Collection starts disabled in Info.plist; turn on only after configure.
        Analytics.setAnalyticsCollectionEnabled(true)
        return true
    }
}
