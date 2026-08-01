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

            Tab(NSLocalizedString("Wardrobe", comment: ""), systemImage: "tshirt.fill", value: 1) {
                WardrobeFeatureView(container: container)
            }

            Tab(NSLocalizedString("Calendar", comment: ""), systemImage: "calendar", value: 2) {
                CalendarFeatureView(container: container)
            }

            Tab(NSLocalizedString("Profile", comment: ""), systemImage: "person", value: 3) {
                ProfileFeatureView(container: container, didFinishOnboarding: $didFinishOnboarding)
            }
        }
        .tint(AppColors.buttonBlue)
        .preferredColorScheme(.light)
        // System tab bar adopts Liquid Glass on iOS 26/27 automatically.
    }
}
