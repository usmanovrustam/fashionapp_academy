import SwiftUI

@main
struct fashionappApp: App {
    @StateObject private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(container)
                .preferredColorScheme(.light)
        }
    }
}
