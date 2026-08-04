import SwiftUI

struct RootView: View {
    @EnvironmentObject private var container: AppContainer
    @AppStorage("didFinishOnboarding") private var didFinishOnboarding = false
    @AppStorage("appearanceMode") private var appearanceModeRaw: String = AppAppearanceMode.light.rawValue

    /// Gender is required — main app shows with a liquid-glass dialog until set.
    @State private var isCheckingGender = false
    @State private var hasRequiredGender = false

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
                AuthFeatureView(
                    auth: container.authService,
                    analytics: container.analytics,
                    profileRepository: container.profileRepository
                )
                .onAppear {
                    hasRequiredGender = false
                    isCheckingGender = false
                }
            } else if isCheckingGender {
                ProgressView()
                    .tint(AppColors.olive)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .nookScreenBackground()
            } else {
                ZStack {
                    MainTabView(didFinishOnboarding: $didFinishOnboarding)

                    if !hasRequiredGender {
                        GenderRequiredDialogOverlay { gender in
                            try await saveRequiredGender(gender)
                            withAnimation(.easeOut(duration: 0.2)) {
                                hasRequiredGender = true
                            }
                        }
                        .zIndex(10)
                    }
                }
            }
        }
        .preferredColorScheme(preferredScheme)
        .task {
            _ = await container.authService.refreshSession()
        }
        .task(id: container.isSignedIn) {
            await refreshGenderGate()
        }
    }

    private func refreshGenderGate() async {
        guard container.isSignedIn else {
            hasRequiredGender = false
            isCheckingGender = false
            return
        }

        isCheckingGender = true
        defer { isCheckingGender = false }

        do {
            let profile = try await container.profileRepository.load()
            hasRequiredGender = profile.hasGenderSet
        } catch {
            // Fail closed — require gender before using wardrobe features.
            hasRequiredGender = false
        }
    }

    private func saveRequiredGender(_ gender: UserGender) async throws {
        var profile = try await container.profileRepository.load()
        profile.gender = gender
        try await container.profileRepository.save(profile)
        container.analytics.track(.profileUpdated, parameters: [
            "action": "set_gender_required",
            "gender": gender.rawValue
        ])
    }
}
