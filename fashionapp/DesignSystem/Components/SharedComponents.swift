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
                        .fill(Color(.systemGray5).opacity(0.5))
                        .frame(width: width, height: height)
                        .overlay(ProgressView().tint(AppColors.brand))
                        .liquidGlass(cornerRadius: AppRadius.large)
                }

                VStack {
                    Spacer()
                    LinearGradient(
                        colors: [Color.clear, Color.black.opacity(0.4)],
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
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.xLarge, style: .continuous))
        .liquidGlass(cornerRadius: AppRadius.xLarge)
    }
}

struct LoadingRingsView: View {
    var message: String = "Loading..."
    @State private var spinning = false

    var body: some View {
        SylyoGlassContainer(spacing: 24) {
            VStack(spacing: 20) {
                ZStack {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [AppColors.brand.opacity(0.7), AppColors.accent.opacity(0.7)],
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
                .padding(28)
                .liquidGlass(cornerRadius: 40, tint: AppColors.brand)

                Text(message)
                    .font(AppTypography.roundedMedium)
                    .foregroundColor(.primary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .liquidGlassCapsule(tint: AppColors.accent)
            }
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
        SylyoGlassContainer(spacing: 20) {
            VStack(spacing: 25) {
                Image(systemName: "tshirt.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(AppColors.primaryGradient)
                    .padding(28)
                    .liquidGlass(cornerRadius: 36, tint: AppColors.brand)

                Text(title)
                    .font(AppTypography.title2)

                Text(subtitle)
                    .font(AppTypography.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Button(action: action) {
                    Text(actionTitle)
                        .font(AppTypography.headline)
                        .padding(.horizontal, 30)
                        .padding(.vertical, 4)
                }
                .sylyoGlassProminent()
            }
            .padding()
            .liquidGlass(cornerRadius: AppRadius.xxLarge)
        }
    }
}

struct GlassCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding()
            .liquidGlass(cornerRadius: AppRadius.large)
    }
}

struct SettingsRow: View {
    let icon: String
    let title: String
    var tint: Color = AppColors.brand

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
        .liquidGlass(cornerRadius: AppRadius.medium, tint: AppColors.brand)
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
                Color.clear
                    .overlay(ProgressView().tint(AppColors.brand))
                    .liquidGlass(cornerRadius: AppRadius.medium)
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
