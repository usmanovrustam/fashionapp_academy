import SwiftUI

struct DiscoverFeatureView: View {
    private let container: AppContainer
    @StateObject private var viewModel: DiscoverViewModel
    @State private var dragOffset: CGSize = .zero
    @State private var selectedRecommendation: OutfitRecommendation?

    private let cardStackOffset: CGFloat = 12
    private let cardStackScale: CGFloat = 0.04
    private let maxVisibleCards = 3

    init(container: AppContainer) {
        self.container = container
        _viewModel = StateObject(wrappedValue: DiscoverViewModel(container: container))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SoftBackground()

                VStack(spacing: AppSpacing.lg) {
                    weatherCard
                        .padding(.horizontal)

                    ZStack {
                        if viewModel.isLoading {
                            LoadingRingsView(message: NSLocalizedString("Loading Outfits...", comment: ""))
                        } else if viewModel.recommendations.isEmpty {
                            emptyState
                        } else if viewModel.topIndex < viewModel.recommendations.count {
                            cardStack
                        } else {
                            refreshState
                        }
                    }
                    .frame(height: 520)
                    .padding(.horizontal)

                    Button {
                        viewModel.showAssistant = true
                    } label: {
                        Label("Ask AI Stylist", systemImage: "bubble.left.and.bubble.right.fill")
                            .font(AppTypography.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(AppColors.primaryGradient)
                            .clipShape(Capsule())
                    }
                    .padding(.horizontal)
                    .buttonStyle(ScaleButtonStyle())
                }
                .padding(.vertical)
            }
            .navigationTitle(NSLocalizedString("Discover", comment: ""))
            .sheet(item: $selectedRecommendation) { rec in
                RecommendationDetailView(recommendation: rec, storage: viewModel.imageStorage)
            }
            .sheet(isPresented: $viewModel.showAssistant) {
                AssistantFeatureView(container: container)
            }
            .task { await viewModel.load() }
        }
    }

    private var weatherCard: some View {
        GlassCard {
            if let weather = viewModel.weather {
                HStack(spacing: 16) {
                    Image(systemName: weather.conditionSymbol)
                        .font(.system(size: 36))
                        .foregroundStyle(AppColors.primaryGradient)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(weather.locationName)
                            .font(.headline)
                        Text(weather.conditionDescription)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(viewModel.formattedTemperature(weather.temperatureCelsius))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.primaryGradient)
                }
            } else {
                HStack {
                    ProgressView()
                    Text(NSLocalizedString("Loading weather...", comment: ""))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
    }

    private var cardStack: some View {
        ForEach(Array(viewModel.recommendations.enumerated()), id: \.element.id) { idx, recommendation in
            if idx >= viewModel.topIndex && idx < viewModel.topIndex + maxVisibleCards {
                RecommendationCardView(
                    recommendation: recommendation,
                    storage: viewModel.imageStorage,
                    onNope: { swipe(-1, accepted: false) },
                    onYeah: { swipe(1, accepted: true) }
                )
                .offset(y: CGFloat(idx - viewModel.topIndex) * cardStackOffset)
                .scaleEffect(1 - CGFloat(idx - viewModel.topIndex) * cardStackScale)
                .opacity(idx == viewModel.topIndex ? 1 : 0.9)
                .zIndex(Double(viewModel.recommendations.count - idx))
                .offset(idx == viewModel.topIndex ? dragOffset : .zero)
                .rotationEffect(.degrees(idx == viewModel.topIndex ? Double(dragOffset.width / 20) : 0))
                .gesture(
                    idx == viewModel.topIndex
                    ? DragGesture()
                        .onChanged { dragOffset = $0.translation }
                        .onEnded { value in
                            if abs(value.translation.width) > 100 {
                                swipe(value.translation.width > 0 ? 1 : -1)
                            } else {
                                dragOffset = .zero
                            }
                        }
                    : nil
                )
                .onTapGesture {
                    if idx == viewModel.topIndex {
                        selectedRecommendation = recommendation
                    }
                }
                .animation(.spring(), value: dragOffset)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.primaryGradient)
            Text(NSLocalizedString("Your wardrobe is empty!", comment: ""))
                .font(AppTypography.title2)
            Text("Scan a few clothing items to get personalized outfit ideas.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Refresh") {
                Task { await viewModel.load() }
            }
            .buttonStyle(GradientPrimaryButtonStyle())
        }
        .padding()
    }

    private var refreshState: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.primaryGradient)
            Text("You're all caught up")
                .font(AppTypography.title2)
            Button("Refresh") {
                Task { await viewModel.load() }
            }
            .buttonStyle(GradientPrimaryButtonStyle())
        }
    }

    private func swipe(_ direction: Int, accepted: Bool) {
        viewModel.trackRecommendationView(at: viewModel.topIndex)
        withAnimation {
            dragOffset = CGSize(width: CGFloat(direction) * 500, height: 0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation {
                viewModel.advance(accepted: accepted)
                dragOffset = .zero
            }
        }
    }
}

private struct RecommendationCardView: View {
    let recommendation: OutfitRecommendation
    let storage: ImageStorage
    let onNope: () -> Void
    let onYeah: () -> Void
    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 20) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.xLarge, style: .continuous))
                    .shadow(radius: 8, y: 4)
            } else {
                RoundedRectangle(cornerRadius: AppRadius.xLarge, style: .continuous)
                    .fill(Color(.systemGray6))
                    .frame(height: 180)
                    .overlay(ProgressView())
            }

            Text(recommendation.displayName)
                .font(.title2.bold())

            Text(recommendation.rationale)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)

            Text("\(Int(recommendation.confidence * 100))% match · \(recommendation.occasion.displayName)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.primaryGradient)

            HStack(spacing: 24) {
                GlassEffectContainer(spacing: 16) {
                    HStack(spacing: 24) {
                        Button(action: onNope) {
                            HStack {
                                Image(systemName: "xmark")
                                Text("Nope")
                            }
                            .font(.headline)
                            .foregroundColor(.purple)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 14)
                        }
                        .liquidGlassCapsule(tint: .purple)

                        Button(action: onYeah) {
                            HStack {
                                Image(systemName: "checkmark")
                                Text("Yeah")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 14)
                        }
                        .liquidGlassCapsule(tint: .pink)
                    }
                }
            }
        }
        .padding(.vertical, 32)
        .padding(.horizontal, 20)
        .liquidGlass(cornerRadius: AppRadius.xxLarge, tint: .purple)
        .task {
            if let path = recommendation.items.first?.transparentImagePath
                ?? recommendation.items.first?.originalImagePath {
                image = UIImage(data: (try? await storage.loadImageData(at: path)) ?? Data())
            }
        }
    }
}

struct RecommendationDetailView: View {
    let recommendation: OutfitRecommendation
    let storage: ImageStorage

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    Text(recommendation.displayName)
                        .font(AppTypography.title)
                    Text(recommendation.rationale)
                        .foregroundColor(.secondary)
                    if let weather = recommendation.weatherSummary {
                        Label(weather, systemImage: "cloud.sun.fill")
                            .foregroundStyle(AppColors.primaryGradient)
                    }
                    Text("Confidence \(Int(recommendation.confidence * 100))%")
                        .font(.headline)

                    ForEach(recommendation.items) { item in
                        HStack(spacing: 12) {
                            StoredImageView(
                                path: item.transparentImagePath ?? item.originalImagePath,
                                storage: storage,
                                width: 72,
                                height: 90,
                                contentMode: .fill
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            VStack(alignment: .leading) {
                                Text(item.name).font(.headline)
                                Text(item.category.displayName).foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding()
                        .liquidGlass(cornerRadius: AppRadius.medium)
                    }
                }
                .padding()
            }
            .background(SoftBackground())
            .navigationTitle(NSLocalizedString("Outfit Details", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
