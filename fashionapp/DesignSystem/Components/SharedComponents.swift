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
                        .overlay(ProgressView().tint(AppColors.olive))
                        .liquidGlass(cornerRadius: AppRadius.large)
                }

                VStack {
                    Spacer()
                    Color.black.opacity(0.35)
                        .frame(height: 56)
                        .clipShape(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 0,
                                bottomLeadingRadius: AppRadius.large,
                                bottomTrailingRadius: AppRadius.large,
                                topTrailingRadius: 0,
                                style: .continuous
                            )
                        )
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

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
                .tint(AppColors.olive)
            Text(message)
                .font(AppTypography.roundedMedium)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
    }
}

struct EmptyWardrobeState: View {
    var title: String
    var subtitle: String
    var actionTitle: String
    var action: () -> Void

    var body: some View {
        NookGlassContainer(spacing: 20) {
            VStack(spacing: 25) {
                Image(systemName: "tshirt.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(AppColors.primaryGradient)
                    .padding(28)
                    .liquidGlass(cornerRadius: 36)

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
                .nookGlassProminent()
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
        .liquidGlass(cornerRadius: AppRadius.medium)
    }
}

struct StoredImageView: View {
    let path: String?
    var fallbackPath: String? = nil
    let storage: ImageStorage
    var width: CGFloat? = nil
    var height: CGFloat? = nil
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if isLoading {
                Color.clear
                    .overlay(ProgressView().tint(AppColors.olive))
                    .liquidGlass(cornerRadius: AppRadius.medium)
            } else {
                Color(.systemGray6)
                    .overlay {
                        Image(systemName: "tshirt")
                            .font(.title2)
                            .foregroundStyle(AppColors.textTertiary)
                    }
            }
        }
        .frame(width: width, height: height)
        .task(id: "\(path ?? "")|\(fallbackPath ?? "")") {
            isLoading = true
            image = await WardrobeImageLoader.load(
                primaryPath: path,
                fallbackPath: fallbackPath,
                storage: storage
            )
            isLoading = false
        }
    }
}

/// Loads wardrobe photos with cache + fallback path; never hangs the UI forever.
enum WardrobeImageLoader {
    static func load(
        primaryPath: String?,
        fallbackPath: String? = nil,
        storage: ImageStorage,
        timeoutSeconds: TimeInterval = 30
    ) async -> UIImage? {
        // Prefer unique paths; keep order (primary first).
        var paths: [String] = []
        for candidate in [primaryPath, fallbackPath] {
            guard let raw = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty,
                  !paths.contains(raw) else { continue }
            paths.append(raw)
        }

        guard !paths.isEmpty else { return nil }

        for path in paths {
            if let cached = ImageMemoryCache.image(for: path) {
                return cached
            }
        }

        for path in paths {
            do {
                let data = try await loadData(path: path, storage: storage, timeoutSeconds: timeoutSeconds)
                guard !data.isEmpty else { continue }
                let decoded = await Task.detached(priority: .userInitiated) {
                    UIImage(data: data)
                }.value
                if let decoded {
                    ImageMemoryCache.store(decoded, for: path)
                    return decoded
                }
            } catch {
                continue
            }
        }
        return nil
    }

    private static func loadData(
        path: String,
        storage: ImageStorage,
        timeoutSeconds: TimeInterval
    ) async throws -> Data {
        try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                try await storage.loadImageData(at: path)
            }
            group.addTask {
                let nanos = UInt64(timeoutSeconds * 1_000_000_000)
                try await Task.sleep(nanoseconds: nanos)
                throw DomainError.storageFailed("Image load timed out.")
            }
            let data = try await group.next()!
            group.cancelAll()
            return data
        }
    }
}
