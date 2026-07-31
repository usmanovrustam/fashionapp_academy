import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var container: AppContainer
    @Binding var didFinishOnboarding: Bool
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            DiscoverFeatureView(container: container)
                .tabItem {
                    Image(systemName: "safari")
                    Text(NSLocalizedString("Discover", comment: ""))
                }
                .tag(0)

            ScannerFeatureView(container: container, isPresentedModally: false)
                .tabItem {
                    Image(systemName: "plus.circle")
                    Text(NSLocalizedString("Add", comment: ""))
                }
                .tag(1)

            WardrobeFeatureView(container: container)
                .tabItem {
                    Image(systemName: "tshirt.fill")
                    Text(NSLocalizedString("Wardrobe", comment: ""))
                }
                .tag(2)

            CalendarFeatureView(container: container)
                .tabItem {
                    Image(systemName: "calendar")
                    Text(NSLocalizedString("Calendar", comment: ""))
                }
                .tag(3)

            ProfileFeatureView(container: container, didFinishOnboarding: $didFinishOnboarding)
                .tabItem {
                    Image(systemName: "person")
                    Text(NSLocalizedString("Profile", comment: ""))
                }
                .tag(4)
        }
        .tint(.purple)
    }
}
