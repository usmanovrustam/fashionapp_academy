import SwiftUI

struct RootView: View {
    @EnvironmentObject private var container: AppContainer
    @AppStorage("didFinishOnboarding") private var didFinishOnboarding = false
    @AppStorage("appearanceMode") private var appearanceModeRaw: String = AppAppearanceMode.light.rawValue

    private var preferredScheme: ColorScheme? {
        AppAppearanceMode.from(stored: appearanceModeRaw).colorScheme
    }

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
        .preferredColorScheme(preferredScheme)
        .task {
            _ = await container.authService.refreshSession()
        }
    }
}
