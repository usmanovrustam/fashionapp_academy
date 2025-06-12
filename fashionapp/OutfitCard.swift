import SwiftUI

struct OutfitCard: View {
    let outfit: Outfit
    
    var body: some View {
        VStack(spacing: 0) {
            // Image container with modern styling
            ZStack {
                if let image = outfit.image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 160, height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(.systemGray6),
                                    Color(.systemGray5)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 160, height: 200)
                        .overlay(
                            VStack(spacing: 8) {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .purple))
                                    .scaleEffect(0.8)
                                
                                Text("Loading...")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        )
                }
                
                // Gradient overlay for better text readability
                VStack {
                    Spacer()
                    LinearGradient(
                        colors: [Color.clear, Color.black.opacity(0.3)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
            .overlay(
                // Modern floating label
                VStack {
                    Spacer()
                    HStack {
                        Text(outfit.name)
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                            .shadow(radius: 2)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            )
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(
            color: Color.black.opacity(0.08),
            radius: 20,
            x: 0,
            y: 8
        )
        .scaleEffect(1.0)
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: outfit.image != nil)
    }
} 