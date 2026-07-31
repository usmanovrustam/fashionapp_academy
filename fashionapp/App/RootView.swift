import SwiftUI

struct RootView: View {
    @EnvironmentObject private var container: AppContainer
    @AppStorage("didFinishOnboarding") private var didFinishOnboarding = false
    @AppStorage("selectedLanguage") private var selectedLanguage: String = Locale.current.language.languageCode?.identifier ?? "en"

    var body: some View {
        Group {
            if !didFinishOnboarding {
                OnboardingView(didFinishOnboarding: $didFinishOnboarding)
            } else {
                MainTabView(didFinishOnboarding: $didFinishOnboarding)
            }
        }
        .environment(\.locale, Locale(identifier: selectedLanguage))
        .task {
            _ = await container.accountStatus.refresh()
        }
    }
}
