import SwiftUI
import FirebaseCore

@main
struct fashionappApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var container: AppContainer

    init() {
        // Adaptor constructs AppDelegate (and configures Firebase) first.
        // Keep a second call here before AppContainer touches Auth/Analytics.
        if FirebaseApp.app() == nil {
            _ = FirebaseBootstrap.configureIfPossible()
        }
        _container = StateObject(wrappedValue: AppContainer())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(container)
                // Sylyo is light-theme only.
                .preferredColorScheme(.light)
        }
    }
}
