import SwiftUI

struct WardrobeFeatureView: View {
    private let container: AppContainer
    @StateObject private var viewModel: WardrobeViewModel
    @State private var showScanner = false

    init(container: AppContainer) {
        self.container = container
        _viewModel = StateObject(wrappedValue: WardrobeViewModel(container: container))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SoftBackground()

                ScrollView {
                    VStack(spacing: AppSpacing.lg) {
                        filterBar

                        if viewModel.isLoading && viewModel.items.isEmpty {
                            LoadingRingsView(message: "Loading your wardrobe...")
                                .padding(.top, 80)
                        } else if let error = viewModel.errorMessage, viewModel.items.isEmpty {
                            errorCard(error)
                        } else if viewModel.filteredItems.isEmpty {
                            EmptyWardrobeState(
                                title: NSLocalizedString("Your wardrobe is empty!", comment: ""),
                                subtitle: NSLocalizedString("Start building your wardrobe by adding your first outfit.", comment: ""),
                                actionTitle: NSLocalizedString("Add Outfit", comment: "")
                            ) {
                                showScanner = true
                            }
                            .padding(.top, 40)
                        } else {
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 160), spacing: 16)],
                                spacing: 16
                            ) {
                                ForEach(viewModel.filteredItems) { item in
                                    NavigationLink {
                                        WardrobeItemDetailView(item: item, viewModel: viewModel)
                                    } label: {
                                        StoredWardrobeCard(
                                            item: item,
                                            storage: viewModel.imageStorageRef()
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.top, AppSpacing.md)
                }
                .refreshable { await viewModel.load() }
            }
            .navigationTitle(NSLocalizedString("Wardrobe", comment: ""))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showScanner = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(AppColors.primaryGradient)
                    }
                }
            }
            .sheet(isPresented: $showScanner) {
                ScannerFeatureView(container: container)
            }
            .task { await viewModel.load() }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                FilterChip(title: "All", selected: viewModel.filterCategory == nil && !viewModel.showFavoritesOnly) {
                    viewModel.filterCategory = nil
                    viewModel.showFavoritesOnly = false
                }
                FilterChip(title: "Favorites", selected: viewModel.showFavoritesOnly) {
                    viewModel.showFavoritesOnly = true
                    viewModel.filterCategory = nil
                }
                ForEach([ClothingCategory.top, .bottom, .dress, .shoes, .jacket, .coat, .accessories], id: \.self) { category in
                    FilterChip(title: category.displayName, selected: viewModel.filterCategory == category) {
                        viewModel.filterCategory = category
                        viewModel.showFavoritesOnly = false
                    }
                }
            }
        }
    }

    private func errorCard(_ message: String) -> some View {
        GlassCard {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.orange)
                Text("Error Loading Wardrobe")
                    .font(AppTypography.title2)
                Text(message)
                    .font(AppTypography.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Button("Try Again") {
                    Task { await viewModel.load() }
                }
                .sylyoGlassProminent()
            }
        }
    }
}

private struct FilterChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(selected ? .white : AppColors.brand)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background {
                    if selected {
                        Capsule().fill(AppColors.primaryGradient)
                    }
                }
                .liquidGlassCapsule(interactive: true, tint: selected ? AppColors.accent : AppColors.brand)
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

private struct StoredWardrobeCard: View {
    let item: WardrobeItem
    let storage: ImageStorage
    @State private var image: UIImage?

    var body: some View {
        WardrobeItemCard(name: item.name, image: image)
            .overlay(alignment: .topTrailing) {
                if item.isFavorite {
                    Image(systemName: "heart.fill")
                        .foregroundColor(AppColors.accent)
                        .padding(10)
                }
            }
            .task {
                let path = item.transparentImagePath ?? item.originalImagePath
                image = UIImage(data: (try? await storage.loadImageData(at: path)) ?? Data())
            }
    }
}

struct WardrobeItemDetailView: View {
    let item: WardrobeItem
    @ObservedObject var viewModel: WardrobeViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                StoredImageView(
                    path: item.transparentImagePath ?? item.originalImagePath,
                    storage: viewModel.imageStorageRef(),
                    height: 320,
                    contentMode: .fit
                )
                .frame(maxWidth: .infinity)
                .liquidGlass(cornerRadius: AppRadius.xLarge, tint: AppColors.brand)

                Text(item.name)
                    .font(AppTypography.title)

                metadataGrid

                HStack {
                    Button {
                        Task { await viewModel.toggleFavorite(item) }
                    } label: {
                        Label(
                            item.isFavorite ? "Unfavorite" : "Favorite",
                            systemImage: item.isFavorite ? "heart.fill" : "heart"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .sylyoGlassProminent()

                    Button(role: .destructive) {
                        Task { await viewModel.delete(item) }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.glass)
                    .tint(.red)
                    .controlSize(.large)
                    .buttonBorderShape(.circle)
                }
            }
            .padding()
        }
        .background(SoftBackground())
        .navigationTitle(item.category.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var metadataGrid: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                metaRow("Category", item.category.displayName)
                if let sub = item.subcategory { metaRow("Type", sub) }
                metaRow("Material", item.material.displayName)
                metaRow("Colors", ([item.dominantColor].compactMap { $0 } + item.colorPalette).prefix(4).joined(separator: ", "))
                metaRow("Season", item.seasons.map(\.displayName).joined(separator: ", "))
                metaRow("Style", item.styleTags.prefix(4).map(\.displayName).joined(separator: ", "))
                metaRow("Formality", "\(Int(item.formalityScore * 100))%")
                metaRow("AI Confidence", "\(Int(item.aiConfidence * 100))%")
                metaRow("Worn", "\(item.wornCount)×")
            }
        }
    }

    private func metaRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundColor(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }
}
