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
                    let isSelected = selectedTab == tab
                    // TabView can force `.fill`; pin variants off and swap explicit outline/fill glyphs.
                    Label {
                        Text(tab.title)
                    } icon: {
                        Image(systemName: tab.symbolName(selected: isSelected))
                    }
                    .environment(\.symbolVariants, .none)
                }
            }
        }
        .tint(AppColors.olive)
        .onAppear(perform: applyTabBarChrome)
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

    /// Unselected = warm gray; selected = olive tint (HIG Tab Bars).
    private func applyTabBarChrome() {
        let gray = UIColor(AppColors.textTertiary)
        let selected = UIColor(AppColors.olive)

        let item = UITabBarItemAppearance()
        item.normal.iconColor = gray
        item.normal.titleTextAttributes = [.foregroundColor: gray]
        item.selected.iconColor = selected
        item.selected.titleTextAttributes = [.foregroundColor: selected]

        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.stackedLayoutAppearance = item
        appearance.inlineLayoutAppearance = item
        appearance.compactInlineLayoutAppearance = item

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        UITabBar.appearance().unselectedItemTintColor = gray
        UITabBar.appearance().tintColor = selected

        // Apply to any already-visible tab bars (appearance proxy alone can miss the live bar).
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                apply(appearance, gray: gray, selected: selected, in: window)
            }
        }
    }

    private func apply(
        _ appearance: UITabBarAppearance,
        gray: UIColor,
        selected: UIColor,
        in view: UIView
    ) {
        if let tabBar = view as? UITabBar {
            tabBar.standardAppearance = appearance
            tabBar.scrollEdgeAppearance = appearance
            tabBar.unselectedItemTintColor = gray
            tabBar.tintColor = selected
        }
        for child in view.subviews {
            apply(appearance, gray: gray, selected: selected, in: child)
        }
    }
}

/// Outline when idle, filled when selected (HIG Tab Bars + SF Symbols).
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

    /// Outline when idle, filled when selected (explicit glyph pairs — HIG Tab Bars).
    func symbolName(selected: Bool) -> String {
        switch self {
        case .discover:
            // Explore / ideas — clear outline ↔ fill pair (replaces sparkle/sparkles).
            return selected ? "binoculars.fill" : "binoculars"
        case .wardrobe:
            return selected ? "tshirt.fill" : "tshirt"
        case .calendar:
            // Day planner — circle calendar reads clearer in the tab bar than plain `calendar`.
            return selected ? "calendar.circle.fill" : "calendar.circle"
        case .profile:
            return selected ? "person.fill" : "person"
        }
    }
}
