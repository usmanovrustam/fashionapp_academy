import SwiftUI

@main
struct fashionappApp: App {
    /// Instantiates `AppDelegate` (Firebase configure + AppContainer) before the scene.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appDelegate.sharedContainer)
                .preferredColorScheme(.light)
        }
    }
}
