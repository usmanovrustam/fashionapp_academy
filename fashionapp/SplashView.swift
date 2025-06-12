import SwiftUI

struct SplashView: View {
    @Binding var didFinishOnboarding: Bool
    @State private var page = 0
    private let pages = [
        ("tshirt.fill", NSLocalizedString("Welcome to FashionApp", comment: ""), NSLocalizedString("Discover and manage your wardrobe in style.", comment: "")),
        ("magnifyingglass", NSLocalizedString("Browse", comment: ""), NSLocalizedString("Find new outfits and inspiration.", comment: "")),
        ("calendar", NSLocalizedString("Calendar", comment: ""), NSLocalizedString("Plan your looks for every day.", comment: "")),
        ("person", NSLocalizedString("Profile", comment: ""), NSLocalizedString("Personalize your experience.", comment: ""))
    ]

    var body: some View {
        VStack {
            TabView(selection: $page) {
                ForEach(0..<pages.count, id: \.self) { idx in
                    VStack(spacing: 32) {
                        Spacer()
                        Image(systemName: pages[idx].0)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 120, height: 120)
                            .foregroundColor(.accentColor)
                        Text(pages[idx].1)
                            .font(.title)
                            .fontWeight(.bold)
                        Text(pages[idx].2)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .padding(.horizontal, 32)
                    .tag(idx)
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            HStack(spacing: 12) {
                ForEach(0..<pages.count, id: \.self) { idx in
                    Circle()
                        .fill(page == idx ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.vertical, 20)
                Button(action: {
                if page < pages.count - 1 {
                    withAnimation { page += 1 }
                } else {
                    didFinishOnboarding = true
                }
                }) {
                Text(page == pages.count - 1 ? NSLocalizedString("Get Started", comment: "") : NSLocalizedString("Next", comment: ""))
                        .font(.headline)
                    .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
        .background(Color(.systemBackground))
    }
} 