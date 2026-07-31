import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var container: AppContainer
    @Binding var didFinishOnboarding: Bool
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab(NSLocalizedString("Discover", comment: ""), systemImage: "safari", value: 0) {
                DiscoverFeatureView(container: container)
            }

            Tab(NSLocalizedString("Add", comment: ""), systemImage: "plus.circle", value: 1) {
                ScannerFeatureView(container: container, isPresentedModally: false)
            }

            Tab(NSLocalizedString("Wardrobe", comment: ""), systemImage: "tshirt.fill", value: 2) {
                WardrobeFeatureView(container: container)
            }

            Tab(NSLocalizedString("Calendar", comment: ""), systemImage: "calendar", value: 3) {
                CalendarFeatureView(container: container)
            }

            Tab(NSLocalizedString("Profile", comment: ""), systemImage: "person", value: 4) {
                ProfileFeatureView(container: container, didFinishOnboarding: $didFinishOnboarding)
            }
        }
        .tint(.purple)
        // System tab bar adopts Liquid Glass on iOS 26/27 automatically.
    }
}
