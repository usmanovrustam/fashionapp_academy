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
        VStack {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { idx in
                    VStack(spacing: AppSpacing.xl) {
                        Spacer()
                        Image(systemName: pages[idx].icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 88, height: 88)
                            .foregroundStyle(AppColors.primaryGradient)
                            .padding(28)
                            .liquidGlass(cornerRadius: 40, tint: AppColors.brand)
                            .scaleEffect(page == idx ? 1.0 : 0.92)
                            .animation(.spring(response: 0.5, dampingFraction: 0.75), value: page)

                        if idx == 0 {
                            Text(pages[idx].title)
                                .font(.system(size: 44, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColors.primaryGradient)
                        } else {
                            Text(pages[idx].title)
                                .font(AppTypography.title)
                        }

                        Text(pages[idx].subtitle)
                            .font(AppTypography.body)
                            .foregroundStyle(.secondary)
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

            splashButtons
                .padding(.horizontal, AppSpacing.xl)
                .padding(.bottom, AppSpacing.xl)
        }
        .background(SoftBackground())
        // Prevent any system accent/blue from leaking into welcome controls.
        .tint(AppColors.brand)
    }

    private var pageIndicators: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(pages.indices, id: \.self) { idx in
                    Capsule()
                        .fill(page == idx ? AppColors.brand.opacity(0.85) : Color.secondary.opacity(0.25))
                        .frame(width: page == idx ? 22 : 8, height: 8)
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: page)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .liquidGlassCapsule(interactive: false, tint: AppColors.brand)
        }
    }

    private var splashButtons: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                if page > 0 {
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            page -= 1
                        }
                    } label: {
                        Text(NSLocalizedString("Back", comment: "Onboarding back"))
                            .frame(minWidth: 72)
                    }
                    .buttonStyle(LiquidGlassButtonStyle(prominent: false, tint: AppColors.brand))
                    .glassEffectID("splash-back", in: glassNamespace)
                }

                if !isLastPage {
                    Button {
                        withAnimation {
                            didFinishOnboarding = true
                        }
                    } label: {
                        Text(NSLocalizedString("Skip", comment: "Onboarding skip"))
                            .frame(minWidth: 64)
                    }
                    .buttonStyle(LiquidGlassButtonStyle(prominent: false, tint: AppColors.brand))
                    .glassEffectID("splash-skip", in: glassNamespace)
                }

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
                .buttonStyle(LiquidGlassButtonStyle(prominent: true, tint: AppColors.brand))
                .glassEffectID("splash-primary", in: glassNamespace)
            }
        }
    }
}
