import SwiftUI

struct OnboardingView: View {
    @Binding var didFinishOnboarding: Bool
    @State private var page = 0
    @Namespace private var glassNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let pages: [(icon: String, title: String, subtitle: String)] = [
        ("sparkles", "Nook: Private wardrobe", "Help choosing what to wear, based on your clothes and the weather."),
        ("camera.viewfinder", "Add Your Clothes", "Take a photo or pick one from your library. Nook tags type, color, and season for you."),
        ("tshirt.fill", "Your Wardrobe", "Keep everything in one place — favorites, wear history, and simple style notes."),
        ("cloud.sun.fill", "Daily Ideas", "See outfit ideas that match today’s weather and what you already own.")
    ]

    private var isLastPage: Bool { page == pages.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.sm)

            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { idx in
                    VStack(spacing: AppSpacing.xl) {
                        Spacer()
                        if idx > 0 {
                            Image(systemName: pages[idx].icon)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 88, height: 88)
                                .foregroundStyle(AppColors.primaryGradient)
                                .padding(28)
                                .liquidGlass(cornerRadius: 40)
                                .nookDecorativeSymbol()
                                .scaleEffect(reduceMotion ? 1 : (page == idx ? 1.0 : 0.92))
                                .animation(
                                    reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.75),
                                    value: page
                                )
                        }

                        if idx == 0 {
                            Text(pages[idx].title)
                                .font(AppTypography.brandHero)
                                .foregroundStyle(AppColors.textPrimary)
                                .accessibilityAddTraits(.isHeader)
                        } else {
                            Text(pages[idx].title)
                                .font(AppTypography.title)
                                .foregroundStyle(AppColors.textPrimary)
                                .accessibilityAddTraits(.isHeader)
                        }

                        Text(pages[idx].subtitle)
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }
                    .padding(.horizontal, AppSpacing.xl)
                    .tag(idx)
                    .accessibilityElement(children: .combine)
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))

            pageIndicators
                .padding(.vertical, 20)

            nextButton
                .padding(.horizontal, AppSpacing.xl)
                .padding(.bottom, AppSpacing.xl)
        }
        .nookSafeScreenInsets()
        .nookScreenBackground()
        .tint(AppColors.buttonBlue)
        .preferredColorScheme(.light)
    }

    private var topBar: some View {
        HStack {
            Spacer()
            if !isLastPage {
                Button {
                    finishOnboarding()
                } label: {
                    Text(NSLocalizedString("Skip", comment: "Onboarding skip"))
                        .font(AppTypography.roundedMedium)
                        .foregroundStyle(AppColors.textTertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(NSLocalizedString("Skip introduction", comment: ""))
            }
        }
        .frame(height: 44)
    }

    private var pageIndicators: some View {
        NookGlassContainer(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(pages.indices, id: \.self) { idx in
                    Capsule()
                        .fill(page == idx ? AppColors.textTertiary.opacity(0.85) : AppColors.textTertiary.opacity(0.22))
                        .frame(width: page == idx ? 22 : 8, height: 8)
                        .animation(
                            reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8),
                            value: page
                        )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .liquidGlassCapsule(interactive: false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Page \(page + 1) of \(pages.count)")
        }
    }

    private var nextButton: some View {
        NookGlassContainer(spacing: 12) {
            Button {
                if isLastPage {
                    finishOnboarding()
                } else if reduceMotion {
                    page += 1
                } else {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        page += 1
                    }
                }
            } label: {
                Text(isLastPage
                       ? NSLocalizedString("Get Started", comment: "")
                       : NSLocalizedString("Next", comment: ""))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(LiquidGlassButtonStyle(prominent: true))
            .nookGlassEffectID("splash-primary", in: glassNamespace)
        }
    }

    private func finishOnboarding() {
        if reduceMotion {
            didFinishOnboarding = true
        } else {
            withAnimation {
                didFinishOnboarding = true
            }
        }
    }
}
