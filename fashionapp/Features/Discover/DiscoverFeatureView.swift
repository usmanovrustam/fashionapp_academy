import SwiftUI

struct DiscoverFeatureView: View {
    private let container: AppContainer
    @StateObject private var viewModel: DiscoverViewModel
    @State private var dragOffset: CGSize = .zero
    @State private var selectedRecommendation: OutfitRecommendation?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let cardStackOffset: CGFloat = 12
    private let cardStackScale: CGFloat = 0.04
    private let maxVisibleCards = 3

    init(container: AppContainer) {
        self.container = container
        _viewModel = StateObject(wrappedValue: DiscoverViewModel(container: container))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    weatherCard
                    mainContent
                }
                .padding(.horizontal)
                .padding(.top, AppSpacing.sm)
                .padding(.bottom, AppSpacing.lg)
            }
            .nookSafeScreenInsets()
            .nookScreenBackground()
            .navigationTitle(NSLocalizedString("Discover", comment: ""))
            .sheet(item: $selectedRecommendation) { rec in
                RecommendationDetailView(recommendation: rec, storage: viewModel.imageStorage)
            }
            .task { await viewModel.load() }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if viewModel.isLoading {
            LoadingRingsView(message: NSLocalizedString("Loading Outfits...", comment: ""))
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.xl)
        } else if viewModel.recommendations.isEmpty {
            emptyState
                .frame(maxWidth: .infinity)
        } else if viewModel.topIndex < viewModel.recommendations.count {
            ZStack {
                cardStack
            }
            .frame(height: 520)
            .frame(maxWidth: .infinity)
        } else {
            refreshState
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.xl)
        }
    }

    private var weatherCard: some View {
        GlassCard {
            if let weather = viewModel.weather {
                weatherContent(weather)
            } else if let error = viewModel.weatherError {
                weatherErrorContent(error)
            } else {
                HStack(spacing: 12) {
                    ProgressView()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("Loading weather...", comment: ""))
                            .font(.subheadline.weight(.medium))
                        Text("Using your current location")
                            .font(.caption)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    Spacer()
                }
            }
        }
    }

    private func weatherContent(_ weather: WeatherSnapshot) -> some View {
        HStack(spacing: 14) {
            Image(systemName: weather.conditionSymbol)
                .font(.system(size: 36, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(AppColors.primaryGradient)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(weather.locationName)
                    .font(.headline)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)

                Text(weather.conditionDescription)
                    .font(.subheadline)
                    .foregroundStyle(AppColors.textSecondary)

                Label(viewModel.windSummary(weather.windSpeedKmh), systemImage: "wind")
                    .font(.caption)
                    .foregroundStyle(AppColors.textTertiary)
                    .labelStyle(.titleAndIcon)
            }

            Spacer(minLength: 8)

            Text(viewModel.formattedTemperature(weather.temperatureCelsius))
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.primaryGradient)
                .accessibilityLabel(
                    "\(viewModel.formattedTemperatureValue(weather.temperatureCelsius)) degrees \(viewModel.temperatureUnitLabel())"
                )
        }
        .accessibilityElement(children: .combine)
    }

    private func weatherErrorContent(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(AppColors.textTertiary)
            VStack(alignment: .leading, spacing: 4) {
                Text("Weather unavailable")
                    .font(.headline)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
            Button("Retry") {
                Task { await viewModel.refreshWeather() }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppColors.accent)
            .disabled(viewModel.isWeatherLoading)
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
                                let accepted = value.translation.width > 0
                                swipe(accepted ? 1 : -1, accepted: accepted)
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
                Task { await viewModel.load(force: true) }
            }
            .nookGlassProminent()
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
                Task { await viewModel.load(force: true) }
            }
            .nookGlassProminent()
        }
    }

    private func swipe(_ direction: Int, accepted: Bool) {
        viewModel.trackRecommendationView(at: viewModel.topIndex)
        if reduceMotion {
            viewModel.advance(accepted: accepted)
            dragOffset = .zero
            return
        }
        withAnimation(.easeOut(duration: 0.2)) {
            dragOffset = CGSize(width: CGFloat(direction) * 500, height: 0)
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            viewModel.advance(accepted: accepted)
            dragOffset = .zero
        }
    }
}

private struct RecommendationCardView: View {
    let recommendation: OutfitRecommendation
    let storage: ImageStorage
    let onNope: () -> Void
    let onYeah: () -> Void
    @State private var image: UIImage?
    @State private var isLoadingImage = true

    var body: some View {
        VStack(spacing: 20) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else if isLoadingImage {
                    Color(.systemGray6)
                        .overlay(ProgressView().tint(AppColors.olive))
                } else {
                    Color(.systemGray6)
                        .overlay {
                            Image(systemName: "tshirt.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(AppColors.textTertiary)
                        }
                }
            }
            .frame(height: 180)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.xLarge, style: .continuous))
            .shadow(color: image == nil ? .clear : .black.opacity(0.08), radius: 8, y: 4)

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

            HStack(spacing: 16) {
                Button(action: onNope) {
                    HStack {
                        Image(systemName: "xmark")
                        Text("Nope")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(LiquidGlassButtonStyle(prominent: false))

                Button(action: onYeah) {
                    HStack {
                        Image(systemName: "checkmark")
                        Text("Yeah")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(LiquidGlassButtonStyle(prominent: true))
            }
        }
        .padding(.vertical, 32)
        .padding(.horizontal, 20)
        .liquidGlass(cornerRadius: AppRadius.xxLarge)
        .task(id: recommendation.id) {
            isLoadingImage = true
            let item = recommendation.items.first
            image = await WardrobeImageLoader.load(
                primaryPath: item?.originalImagePath,
                fallbackPath: item?.transparentImagePath,
                storage: storage
            )
            isLoadingImage = false
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
                                path: item.originalImagePath,
                                fallbackPath: item.transparentImagePath,
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
            .nookSafeScreenInsets()
            .nookScreenBackground()
            .navigationTitle(NSLocalizedString("Outfit Details", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
