import UIKit
import FirebaseCore
import FirebaseAnalytics

/// Owns app composition after Firebase is configured.
///
/// Important: do **not** mark this class `@MainActor`. GoogleUtilities checks
/// `conforms(to: UIApplicationDelegate.self)` via the ObjC runtime; `@MainActor`
/// on the class breaks that check and logs I-SWZ001014.
@objc(NookAppDelegate)
final class AppDelegate: UIResponder, UIApplicationDelegate {
    /// Created only after `FirebaseApp.configure()` succeeds (or is skipped safely).
    private(set) var sharedContainer: AppContainer

    override init() {
        _ = FirebaseBootstrap.configureIfPossible()
        // `AppContainer` is `@MainActor`. App launch is on the main thread — build it there
        // without loading Core ML models (those are lazy on first scan).
        if Thread.isMainThread {
            sharedContainer = MainActor.assumeIsolated { AppContainer() }
        } else {
            sharedContainer = DispatchQueue.main.sync {
                MainActor.assumeIsolated { AppContainer() }
            }
        }
        super.init()
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        _ = FirebaseBootstrap.configureIfPossible()
        // Collection starts disabled in Info.plist; enable only after configure.
        if FirebaseBootstrap.isConfigured {
            Analytics.setAnalyticsCollectionEnabled(true)
        }
        return true
    }
}
