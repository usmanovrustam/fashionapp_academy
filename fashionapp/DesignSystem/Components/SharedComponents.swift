import SwiftUI
import UIKit

struct WardrobeItemCard: View {
    let name: String
    let image: UIImage?
    var width: CGFloat = 160
    var height: CGFloat = 200

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: width, height: height)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(.systemGray6), Color(.systemGray5)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: width, height: height)
                        .overlay(
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .purple))
                        )
                }

                VStack {
                    Spacer()
                    LinearGradient(
                        colors: [Color.clear, Color.black.opacity(0.35)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
                }

                VStack {
                    Spacer()
                    HStack {
                        Text(name)
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                            .shadow(radius: 2)
                            .lineLimit(2)
                        Spacer()
                    }
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.bottom, AppSpacing.md)
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.xLarge, style: .continuous))
        .shadow(color: AppColors.cardShadow, radius: 20, x: 0, y: 8)
    }
}

struct LoadingRingsView: View {
    var message: String = "Loading..."
    @State private var spinning = false

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [Color.purple.opacity(0.6), Color.pink.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 4
                        )
                        .frame(width: 60 + CGFloat(index * 20), height: 60 + CGFloat(index * 20))
                        .rotationEffect(.degrees(spinning ? 360 : 0))
                        .animation(
                            .linear(duration: 1.5)
                                .repeatForever(autoreverses: false)
                                .delay(Double(index) * 0.2),
                            value: spinning
                        )
                }
            }
            Text(message)
                .font(AppTypography.roundedMedium)
                .foregroundColor(.purple.opacity(0.8))
        }
        .onAppear { spinning = true }
    }
}

struct EmptyWardrobeState: View {
    var title: String
    var subtitle: String
    var actionTitle: String
    var action: () -> Void

    var body: some View {
        VStack(spacing: 25) {
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.purple.opacity(0.1), Color.pink.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100 + CGFloat(index * 50), height: 100 + CGFloat(index * 50))
                        .offset(x: CGFloat(index * 20), y: CGFloat(index * -10))
                }
            }

            Image(systemName: "tshirt.fill")
                .font(.system(size: 60))
                .foregroundColor(.purple.opacity(0.8))

            Text(title)
                .font(AppTypography.title2)

            Text(subtitle)
                .font(AppTypography.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button(action: action) {
                Text(actionTitle)
                    .font(AppTypography.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 12)
                    .background(AppColors.primaryGradient)
                    .clipShape(Capsule())
            }
            .buttonStyle(ScaleButtonStyle())
        }
    }
}

struct GlassCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding()
            .background(
                RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 5)
            )
    }
}

struct SettingsRow: View {
    let icon: String
    let title: String
    var tint: Color = .purple

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .foregroundStyle(AppColors.primaryGradient)
                .frame(width: 28)
            Text(title)
                .foregroundColor(.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 10)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(AppColors.primaryGradient)
            Text(value)
                .font(.title.bold())
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
    }
}

@MainActor
final class ImageLoader: ObservableObject {
    @Published var image: UIImage?
    private let storage: ImageStorage

    init(storage: ImageStorage) {
        self.storage = storage
    }

    func load(path: String?) async {
        guard let path, !path.isEmpty else {
            image = nil
            return
        }
        do {
            let data = try await storage.loadImageData(at: path)
            image = UIImage(data: data)
        } catch {
            image = nil
        }
    }
}

struct StoredImageView: View {
    let path: String?
    let storage: ImageStorage
    var width: CGFloat? = nil
    var height: CGFloat? = nil
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Color(.systemGray6)
                    .overlay(ProgressView().tint(.purple))
            }
        }
        .frame(width: width, height: height)
        .task(id: path) {
            guard let path, !path.isEmpty else {
                image = nil
                return
            }
            image = UIImage(data: (try? await storage.loadImageData(at: path)) ?? Data())
        }
    }
}
