import SwiftUI

struct OnboardingView: View {
    @Binding var didFinishOnboarding: Bool
    @State private var page = 0
    @Namespace private var glassNamespace

    private let pages: [(icon: String, title: String, subtitle: String)] = [
        ("sparkles", "Sylyo", "Your personal AI fashion stylist."),
        ("camera.viewfinder", "Scan Your Clothes", "Photograph each piece — we remove the background and tag fabric, color, season, and style."),
        ("tshirt.fill", "Digital Wardrobe", "Every item lives in one smart closet with favorites, wear history, and confidence scores."),
        ("cloud.sun.fill", "Daily Outfits", "Weather-aware recommendations and an AI stylist that understands your plans.")
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
                        // No app logo yet — feature icons only after the welcome page.
                        if idx > 0 {
                            Image(systemName: pages[idx].icon)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 88, height: 88)
                                .foregroundStyle(AppColors.primaryGradient)
                                .padding(28)
                                .liquidGlass(cornerRadius: 40)
                                .scaleEffect(page == idx ? 1.0 : 0.92)
                                .animation(.spring(response: 0.5, dampingFraction: 0.75), value: page)
                        }

                        if idx == 0 {
                            Text(pages[idx].title)
                                .font(.system(size: 44, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppColors.textPrimary)
                        } else {
                            Text(pages[idx].title)
                                .font(AppTypography.title)
                                .foregroundStyle(AppColors.textPrimary)
                        }

                        Text(pages[idx].subtitle)
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.textSecondary)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .padding(.horizontal, AppSpacing.xl)
                    .tag(idx)
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))

            pageIndicators
                .padding(.vertical, 20)

            nextButton
                .padding(.horizontal, AppSpacing.xl)
                .padding(.bottom, AppSpacing.xl)
        }
        .background(SoftBackground())
        .tint(AppColors.buttonBlue)
        .preferredColorScheme(.light)
    }

    private var topBar: some View {
        HStack {
            Spacer()
            if !isLastPage {
                Button {
                    withAnimation {
                        didFinishOnboarding = true
                    }
                } label: {
                    Text(NSLocalizedString("Skip", comment: "Onboarding skip"))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppColors.textTertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(NSLocalizedString("Skip", comment: "Onboarding skip"))
            }
        }
        .frame(height: 44)
    }

    private var pageIndicators: some View {
        SylyoGlassContainer(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(pages.indices, id: \.self) { idx in
                    Capsule()
                        .fill(page == idx ? AppColors.textTertiary.opacity(0.85) : AppColors.textTertiary.opacity(0.22))
                        .frame(width: page == idx ? 22 : 8, height: 8)
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: page)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .liquidGlassCapsule(interactive: false)
        }
    }

    private var nextButton: some View {
        SylyoGlassContainer(spacing: 12) {
            Button {
                if isLastPage {
                    withAnimation {
                        didFinishOnboarding = true
                    }
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
            .sylyoGlassEffectID("splash-primary", in: glassNamespace)
        }
    }
}
