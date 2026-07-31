import SwiftUI

struct OnboardingView: View {
    @Binding var didFinishOnboarding: Bool
    @State private var page = 0

    private let pages: [(icon: String, title: String, subtitle: String)] = [
        ("sparkles", "Sylyo", "Your personal AI fashion stylist."),
        ("camera.viewfinder", "Scan Your Clothes", "Photograph each piece — we remove the background and tag fabric, color, season, and style."),
        ("tshirt.fill", "Digital Wardrobe", "Every item lives in one smart closet with favorites, wear history, and confidence scores."),
        ("cloud.sun.fill", "Daily Outfits", "Weather-aware recommendations and an AI stylist that understands your plans.")
    ]

    var body: some View {
        VStack {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { idx in
                    VStack(spacing: AppSpacing.xl) {
                        Spacer()
                        Image(systemName: pages[idx].icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 110, height: 110)
                            .foregroundStyle(AppColors.primaryGradient)
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
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .padding(.horizontal, AppSpacing.xl)
                    .tag(idx)
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))

            HStack(spacing: 12) {
                ForEach(pages.indices, id: \.self) { idx in
                    Circle()
                        .fill(page == idx ? Color.purple : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                        .animation(.spring(), value: page)
                }
            }
            .padding(.vertical, 20)

            Button {
                if page < pages.count - 1 {
                    withAnimation { page += 1 }
                } else {
                    didFinishOnboarding = true
                }
            } label: {
                Text(page == pages.count - 1
                       ? NSLocalizedString("Get Started", comment: "")
                       : NSLocalizedString("Next", comment: ""))
            }
            .buttonStyle(GradientPrimaryButtonStyle())
            .padding(.horizontal, AppSpacing.xl)
            .padding(.bottom, AppSpacing.xl)
        }
        .background(SoftBackground())
    }
}
