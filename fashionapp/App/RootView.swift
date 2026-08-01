import SwiftUI

struct RootView: View {
    @EnvironmentObject private var container: AppContainer
    @AppStorage("didFinishOnboarding") private var didFinishOnboarding = false
    @AppStorage("selectedLanguage") private var selectedLanguage: String = Locale.current.language.languageCode?.identifier ?? "en"

    var body: some View {
        Group {
            if !container.isFirebaseConfigured {
                FirebaseSetupView()
            } else if !didFinishOnboarding {
                OnboardingView(didFinishOnboarding: $didFinishOnboarding)
                    .onChange(of: didFinishOnboarding) { _, finished in
                        if finished {
                            container.analytics.track(.onboardingCompleted)
                        }
                    }
            } else if !container.isSignedIn {
                AuthFeatureView(auth: container.authService, analytics: container.analytics)
            } else {
                MainTabView(didFinishOnboarding: $didFinishOnboarding)
            }
        }
        .environment(\.locale, Locale(identifier: selectedLanguage))
        .preferredColorScheme(.light)
        .task {
            _ = await container.authService.refreshSession()
        }
    }
}
