import SwiftUI

@main
struct fashionappApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var container: AppContainer

    init() {
        // Belt-and-suspenders: AppDelegate configures first; this covers any
        // path where SwiftUI init runs before didFinishLaunching completes.
        _ = FirebaseBootstrap.configureIfPossible()
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
