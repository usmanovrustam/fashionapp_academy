import SwiftUI

@main
struct fashionappApp: App {
    /// Instantiates `AppDelegate` (Firebase configure + AppContainer) before the scene.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Belt-and-suspenders: configure as early as the App entry point runs.
        _ = FirebaseBootstrap.configureIfPossible()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appDelegate.sharedContainer)
        }
    }
}
