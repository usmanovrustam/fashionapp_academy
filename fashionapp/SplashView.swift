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
            HStack(spacing: 8) {
                ForEach(0..<pages.count, id: \.self) { idx in
                    Circle()
                        .fill(idx == page ? Color.accentColor : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.vertical, 16)
            if page == pages.count - 1 {
                Button(action: {
                    didFinishOnboarding = true
                }) {
                    Text("Get Started")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            } else {
                Button(action: {
                    withAnimation { page += 1 }
                }) {
                    Text("Next")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor.opacity(0.8))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
        }
        .background(Color(.systemBackground).ignoresSafeArea())
    }
} 