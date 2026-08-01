import SwiftUI

@main
struct fashionappApp: App {
    @StateObject private var container: AppContainer

    init() {
        // Configure Firebase before any Auth/Firestore calls.
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
