import SwiftUI

/// Shows wardrobe pieces visually similar to a given item, powered by the
/// on-device CoreML embedding (`CoreMLWardrobeImageSearch`).
struct SimilarItemsView: View {
    let item: WardrobeItem
    @ObservedObject var viewModel: WardrobeViewModel

    @State private var results: [WardrobeItem] = []
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                if isLoading {
                    LoadingRingsView(message: NSLocalizedString("Finding similar pieces...", comment: ""))
                        .padding(.top, 80)
                } else if results.isEmpty {
                    GlassCard {
                        VStack(spacing: 12) {
                            Image(systemName: "square.grid.2x2")
                                .font(.system(size: 36))
                                .foregroundStyle(AppColors.primaryGradient)
                            Text(NSLocalizedString("No similar pieces yet", comment: ""))
                                .font(AppTypography.title2)
                            Text(NSLocalizedString("Add more items to your wardrobe to get visual matches.", comment: ""))
                                .font(AppTypography.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.top, 40)
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 160), spacing: 16)],
                        spacing: 16
                    ) {
                        ForEach(results) { result in
                            NavigationLink {
                                WardrobeItemDetailView(item: result, viewModel: viewModel)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    StoredImageView(
                                        path: result.transparentImagePath ?? result.originalImagePath,
                                        storage: viewModel.imageStorageRef(),
                                        height: 160,
                                        contentMode: .fill
                                    )
                                    .frame(maxWidth: .infinity)
                                    .liquidGlass(cornerRadius: AppRadius.large)

                                    Text(result.name)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(AppColors.textPrimary)
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.top, AppSpacing.md)
            .padding(.bottom, AppSpacing.lg)
        }
        .nookSafeScreenInsets()
        .nookScreenBackground()
        .navigationTitle(NSLocalizedString("Similar items", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: item.id) {
            isLoading = true
            results = await viewModel.findSimilar(to: item)
            isLoading = false
        }
    }
}
