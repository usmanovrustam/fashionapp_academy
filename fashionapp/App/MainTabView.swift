import SwiftUI
import UIKit

struct MainTabView: View {
    @EnvironmentObject private var container: AppContainer
    @Binding var didFinishOnboarding: Bool
    @State private var selectedTab: AppTab = .discover

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(AppTab.allCases) { tab in
                Tab(value: tab) {
                    tabRoot(tab)
                } label: {
                    Label(tab.title, systemImage: tab.symbolName(selected: selectedTab == tab))
                }
            }
        }
        .tint(AppColors.buttonBlue)
        .preferredColorScheme(.light)
        .onAppear(perform: configureTabBarAppearance)
        .onChange(of: selectedTab) { _, _ in
            configureTabBarAppearance()
        }
    }

    @ViewBuilder
    private func tabRoot(_ tab: AppTab) -> some View {
        switch tab {
        case .discover:
            DiscoverFeatureView(container: container)
        case .wardrobe:
            WardrobeFeatureView(container: container)
        case .calendar:
            CalendarFeatureView(container: container)
        case .profile:
            ProfileFeatureView(container: container, didFinishOnboarding: $didFinishOnboarding)
        }
    }

    /// HIG Tab Bars: unselected items stay neutral gray; selected use the tint.
    private func configureTabBarAppearance() {
        let gray = UIColor(AppColors.textTertiary)

        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()

        let item = UITabBarItemAppearance()
        let grayAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: gray
        ]
        item.normal.iconColor = gray
        item.normal.titleTextAttributes = grayAttrs
        item.selected.iconColor = UIColor(AppColors.buttonBlue)
        item.selected.titleTextAttributes = [
            .foregroundColor: UIColor(AppColors.buttonBlue)
        ]

        appearance.stackedLayoutAppearance = item
        appearance.inlineLayoutAppearance = item
        appearance.compactInlineLayoutAppearance = item

        let tabBar = UITabBar.appearance()
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
        tabBar.unselectedItemTintColor = gray
        tabBar.tintColor = UIColor(AppColors.buttonBlue)
    }
}

/// Tab destinations with outline (unselected) / fill (selected) SF Symbol pairs — HIG Tab Bars + SF Symbols.
private enum AppTab: Int, CaseIterable, Identifiable, Hashable {
    case discover
    case wardrobe
    case calendar
    case profile

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .discover: return NSLocalizedString("Discover", comment: "Tab")
        case .wardrobe: return NSLocalizedString("Wardrobe", comment: "Tab")
        case .calendar: return NSLocalizedString("Calendar", comment: "Tab")
        case .profile: return NSLocalizedString("Profile", comment: "Tab")
        }
    }

    func symbolName(selected: Bool) -> String {
        switch self {
        case .discover:
            // Prefer outline → denser/fill-like glyph (no `sparkles.fill` in SF Symbols).
            return selected ? "sparkles" : "sparkle"
        case .wardrobe:
            return selected ? "tshirt.fill" : "tshirt"
        case .calendar:
            return selected ? "calendar.circle.fill" : "calendar"
        case .profile:
            return selected ? "person.fill" : "person"
        }
    }
}
