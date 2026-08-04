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
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    filterBar

                    if viewModel.isLoading && viewModel.items.isEmpty {
                        LoadingRingsView(message: NSLocalizedString("Loading your wardrobe...", comment: ""))
                            .padding(.top, 80)
                    } else if let error = viewModel.errorMessage, viewModel.items.isEmpty {
                        errorCard(error)
                    } else if viewModel.filteredItems.isEmpty {
                        if viewModel.showLaundryOnly {
                            EmptyWardrobeState(
                                title: NSLocalizedString("Nothing needs a wash", comment: ""),
                                subtitle: NSLocalizedString("When you mark laundry on the calendar, those pieces show up here.", comment: ""),
                                actionTitle: NSLocalizedString("Show all", comment: "")
                            ) {
                                viewModel.showLaundryOnly = false
                            }
                            .padding(.top, 40)
                        } else {
                            EmptyWardrobeState(
                                title: NSLocalizedString("Your wardrobe is empty!", comment: ""),
                                subtitle: NSLocalizedString("Start building your wardrobe by adding your first outfit.", comment: ""),
                                actionTitle: NSLocalizedString("Add Outfit", comment: "")
                            ) {
                                showScanner = true
                            }
                            .padding(.top, 40)
                        }
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
                .padding(.bottom, AppSpacing.lg)
            }
            .refreshable { await viewModel.load(force: true) }
            .nookSafeScreenInsets()
            .nookScreenBackground()
            .navigationTitle(NSLocalizedString("Wardrobe", comment: ""))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showScanner = true
                    } label: {
                        Label(NSLocalizedString("Add", comment: ""), systemImage: "plus.circle.fill")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(AppColors.primaryGradient)
                    }
                    .accessibilityLabel(NSLocalizedString("Add Outfit", comment: ""))
                }
            }
            .sheet(isPresented: $showScanner) {
                ScannerFeatureView(container: container)
            }
            .task { await viewModel.load() }
            .onChange(of: showScanner) { _, isShowing in
                if !isShowing {
                    Task { await viewModel.load(force: true) }
                }
            }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                FilterChip(
                    title: NSLocalizedString("All", comment: ""),
                    selected: viewModel.filterCategory == nil && !viewModel.showFavoritesOnly && !viewModel.showLaundryOnly
                ) {
                    viewModel.filterCategory = nil
                    viewModel.showFavoritesOnly = false
                    viewModel.showLaundryOnly = false
                }
                FilterChip(title: NSLocalizedString("Favorites", comment: ""), selected: viewModel.showFavoritesOnly) {
                    viewModel.showFavoritesOnly = true
                    viewModel.showLaundryOnly = false
                    viewModel.filterCategory = nil
                }
                FilterChip(
                    title: viewModel.laundryCount > 0
                        ? String(format: NSLocalizedString("Needs wash (%d)", comment: ""), viewModel.laundryCount)
                        : NSLocalizedString("Needs wash", comment: ""),
                    selected: viewModel.showLaundryOnly
                ) {
                    viewModel.showLaundryOnly = true
                    viewModel.showFavoritesOnly = false
                    viewModel.filterCategory = nil
                }
                ForEach([ClothingCategory.top, .bottom, .dress, .shoes, .jacket, .coat, .accessories], id: \.self) { category in
                    FilterChip(title: category.displayName, selected: viewModel.filterCategory == category) {
                        viewModel.filterCategory = category
                        viewModel.showFavoritesOnly = false
                        viewModel.showLaundryOnly = false
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
                Text(NSLocalizedString("Error Loading Wardrobe", comment: ""))
                    .font(AppTypography.title2)
                Text(message)
                    .font(AppTypography.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Button(NSLocalizedString("Try Again", comment: "")) {
                    Task { await viewModel.load() }
                }
                .nookGlassProminent()
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
                .foregroundColor(selected ? AppColors.textPrimary : AppColors.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .liquidGlassCapsule(interactive: true)
                .opacity(selected ? 1 : 0.72)
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
                HStack(spacing: 6) {
                    if item.isInLaundry {
                        Image(systemName: "washer.fill")
                            .foregroundColor(AppColors.olive)
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    if item.isFavorite {
                        Image(systemName: "heart.fill")
                            .foregroundColor(AppColors.accent)
                            .padding(10)
                    }
                }
            }
            .task(id: item.id) {
                let path = item.transparentImagePath ?? item.originalImagePath
                if let cached = ImageMemoryCache.image(for: path) {
                    image = cached
                    return
                }
                let data = (try? await storage.loadImageData(at: path)) ?? Data()
                let decoded = await Task.detached(priority: .userInitiated) {
                    UIImage(data: data)
                }.value
                if let decoded {
                    ImageMemoryCache.store(decoded, for: path)
                }
                image = decoded
            }
    }
}

struct WardrobeItemDetailView: View {
    let item: WardrobeItem
    @ObservedObject var viewModel: WardrobeViewModel

    private var liveItem: WardrobeItem {
        viewModel.items.first(where: { $0.id == item.id }) ?? item
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                StoredImageView(
                    path: liveItem.transparentImagePath ?? liveItem.originalImagePath,
                    storage: viewModel.imageStorageRef(),
                    height: 320,
                    contentMode: .fit
                )
                .frame(maxWidth: .infinity)
                .liquidGlass(cornerRadius: AppRadius.xLarge)

                Text(liveItem.name)
                    .font(AppTypography.title)

                metadataGrid

                if liveItem.isInLaundry {
                    Button {
                        Task { await viewModel.markWashed(liveItem) }
                    } label: {
                        Label(NSLocalizedString("Mark washed", comment: ""), systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .nookGlassProminent()
                }

                HStack {
                    Button {
                        Task { await viewModel.toggleFavorite(liveItem) }
                    } label: {
                        Label(
                            liveItem.isFavorite
                                ? NSLocalizedString("Unfavorite", comment: "")
                                : NSLocalizedString("Favorite", comment: ""),
                            systemImage: liveItem.isFavorite ? "heart.fill" : "heart"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .nookGlassProminent()

                    Button(role: .destructive) {
                        Task { await viewModel.delete(liveItem) }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(LiquidGlassButtonStyle(prominent: false, tint: .red))
                    .controlSize(.large)
                    .buttonBorderShape(.circle)
                }
            }
            .padding()
        }
        .nookSafeScreenInsets()
        .nookScreenBackground()
        .navigationTitle(liveItem.category.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var metadataGrid: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                metaRow(NSLocalizedString("Category", comment: ""), liveItem.category.displayName)
                if let sub = liveItem.subcategory { metaRow(NSLocalizedString("Type", comment: ""), sub) }
                metaRow(NSLocalizedString("Material", comment: ""), liveItem.material.displayName)
                metaRow(NSLocalizedString("Colors", comment: ""), ([liveItem.dominantColor].compactMap { $0 } + liveItem.colorPalette).prefix(4).joined(separator: ", "))
                metaRow(NSLocalizedString("Season", comment: ""), liveItem.seasons.map(\.displayName).joined(separator: ", "))
                metaRow(NSLocalizedString("Style", comment: ""), liveItem.styleTags.prefix(4).map(\.displayName).joined(separator: ", "))
                metaRow(NSLocalizedString("Formality", comment: ""), String(format: NSLocalizedString("%d%%", comment: "Percentage value"), Int(liveItem.formalityScore * 100)))
                metaRow(NSLocalizedString("AI Confidence", comment: ""), String(format: NSLocalizedString("%d%%", comment: "Percentage value"), Int(liveItem.aiConfidence * 100)))
                metaRow(NSLocalizedString("Worn", comment: ""), String(format: NSLocalizedString("%d×", comment: "Worn count"), liveItem.wornCount))
                if liveItem.isInLaundry {
                    metaRow(NSLocalizedString("Status", comment: ""), NSLocalizedString("Needs wash", comment: ""))
                }
                if liveItem.isListedForDonate {
                    metaRow(NSLocalizedString("Status", comment: ""), NSLocalizedString("Marked for donate", comment: ""))
                }
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
