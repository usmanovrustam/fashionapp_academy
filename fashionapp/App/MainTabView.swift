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
                    // TabView forces `.fill` on every tab icon; clear it, then pick outline/fill ourselves.
                    Label {
                        Text(tab.title)
                    } icon: {
                        Image(systemName: tab.symbolName(selected: isSelected))
                    }
                    .environment(\.symbolVariants, isSelected ? .fill : .none)
                }
            }
        }
        .tint(AppColors.buttonBlue)
        .preferredColorScheme(.light)
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

    /// Unselected = gray; selected = blue tint (HIG Tab Bars).
    private func applyTabBarChrome() {
        let gray = UIColor(AppColors.textTertiary)
        let blue = UIColor(AppColors.buttonBlue)

        let item = UITabBarItemAppearance()
        item.normal.iconColor = gray
        item.normal.titleTextAttributes = [.foregroundColor: gray]
        item.selected.iconColor = blue
        item.selected.titleTextAttributes = [.foregroundColor: blue]

        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.stackedLayoutAppearance = item
        appearance.inlineLayoutAppearance = item
        appearance.compactInlineLayoutAppearance = item

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        UITabBar.appearance().unselectedItemTintColor = gray
        UITabBar.appearance().tintColor = blue

        // Apply to any already-visible tab bars (appearance proxy alone can miss the live bar).
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                apply(appearance, gray: gray, blue: blue, in: window)
            }
        }
    }

    private func apply(
        _ appearance: UITabBarAppearance,
        gray: UIColor,
        blue: UIColor,
        in view: UIView
    ) {
        if let tabBar = view as? UITabBar {
            tabBar.standardAppearance = appearance
            tabBar.scrollEdgeAppearance = appearance
            tabBar.unselectedItemTintColor = gray
            tabBar.tintColor = blue
        }
        for child in view.subviews {
            apply(appearance, gray: gray, blue: blue, in: child)
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

    /// Base SF Symbol names (no `.fill` suffix). Fill comes from `symbolVariants` when selected.
    func symbolName(selected: Bool) -> String {
        switch self {
        case .discover:
            // No reliable fill pair — denser glyph when selected.
            return selected ? "sparkles" : "sparkle"
        case .wardrobe:
            return "tshirt"
        case .calendar:
            return "calendar"
        case .profile:
            return "person"
        }
    }
}
