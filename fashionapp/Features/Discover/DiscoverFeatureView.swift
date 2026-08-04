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
        } else if viewModel.needsWardrobePieces {
            wardrobeGapState
                .frame(maxWidth: .infinity)
        } else if viewModel.recommendations.isEmpty {
            emptyState
                .frame(maxWidth: .infinity)
        } else if viewModel.topIndex < viewModel.recommendations.count {
            ZStack {
                cardStack
            }
            .frame(height: 560)
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
                        Text(NSLocalizedString("Using your current location", comment: ""))
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
                    String(
                        format: NSLocalizedString("%@ degrees %@", comment: "Weather temperature accessibility"),
                        viewModel.formattedTemperatureValue(weather.temperatureCelsius),
                        viewModel.temperatureUnitLabel()
                    )
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
                Text(NSLocalizedString("Weather unavailable", comment: ""))
                    .font(.headline)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
            Button(NSLocalizedString("Retry", comment: "")) {
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

    private var wardrobeGapState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tshirt.circle")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.primaryGradient)
            Text(NSLocalizedString("Build a full outfit", comment: "Discover gap title"))
                .font(AppTypography.title2)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(viewModel.wardrobeCoverage.missingMessages, id: \.self) { line in
                    Label(line, systemImage: "plus.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)

            Text(NSLocalizedString(
                "A daily look needs top + bottom + shoes — or a dress + shoes.",
                comment: "Discover gap rule summary"
            ))
            .font(.caption)
            .foregroundStyle(AppColors.textTertiary)
            .multilineTextAlignment(.center)

            Button(NSLocalizedString("Refresh", comment: "")) {
                Task { await viewModel.load(force: true) }
            }
            .nookGlassProminent()
        }
        .padding()
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.primaryGradient)
            Text(NSLocalizedString("No full outfits yet", comment: ""))
                .font(AppTypography.title2)
            Text(NSLocalizedString(
                "Try refreshing after you add more tops, bottoms, shoes, or a dress.",
                comment: ""
            ))
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            Button(NSLocalizedString("Refresh", comment: "")) {
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
            Text(NSLocalizedString("You're all caught up", comment: ""))
                .font(AppTypography.title2)
            Button(NSLocalizedString("Refresh", comment: "")) {
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

// MARK: - Card

private struct RecommendationCardView: View {
    let recommendation: OutfitRecommendation
    let storage: ImageStorage
    let onNope: () -> Void
    let onYeah: () -> Void

    private var slots: OutfitSlotAssignment { recommendation.slots }

    var body: some View {
        VStack(spacing: 16) {
            FullOutfitPreview(slots: slots, storage: storage)
                .frame(height: 220)
                .frame(maxWidth: .infinity)

            Text(recommendation.displayName)
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            Text(recommendation.rationale)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)

            HStack(spacing: 8) {
                slotChip(
                    slots.isDressLook
                        ? NSLocalizedString("Dress + shoes", comment: "Outfit type chip")
                        : NSLocalizedString("Full look", comment: "Outfit type chip")
                )
                Text(String(
                    format: NSLocalizedString("%d%% match · %@", comment: "Outfit card confidence and occasion"),
                    Int(recommendation.confidence * 100),
                    recommendation.occasion.displayName
                ))
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.primaryGradient)
            }

            HStack(spacing: 16) {
                Button(action: onNope) {
                    HStack {
                        Image(systemName: "xmark")
                        Text(NSLocalizedString("Nope", comment: ""))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(LiquidGlassButtonStyle(prominent: false))

                Button(action: onYeah) {
                    HStack {
                        Image(systemName: "checkmark")
                        Text(NSLocalizedString("Yeah", comment: ""))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(LiquidGlassButtonStyle(prominent: true))
            }
        }
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
        .liquidGlass(cornerRadius: AppRadius.xxLarge)
    }

    private func slotChip(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppColors.olive.opacity(0.12), in: Capsule())
            .foregroundStyle(AppColors.olive)
    }
}

/// Stacked / collage preview for a full daily outfit (hides bottom for dresses).
private struct FullOutfitPreview: View {
    let slots: OutfitSlotAssignment
    let storage: ImageStorage

    var body: some View {
        Group {
            if slots.isDressLook {
                dressLayout
            } else {
                separatesLayout
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.xLarge, style: .continuous))
    }

    private var dressLayout: some View {
        VStack(spacing: 6) {
            slotImage(slots.body, label: OutfitWearSlot.body.displayName, height: 150)
            slotImage(slots.shoes, label: OutfitWearSlot.shoes.displayName, height: 64)
        }
    }

    private var separatesLayout: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                slotImage(slots.top, label: OutfitWearSlot.top.displayName, height: 100)
                slotImage(slots.bottom, label: OutfitWearSlot.bottom.displayName, height: 100)
            }
            slotImage(slots.shoes, label: OutfitWearSlot.shoes.displayName, height: 64)
        }
    }

    @ViewBuilder
    private func slotImage(_ item: WardrobeItem?, label: String, height: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let item {
                StoredImageView(
                    path: item.transparentImagePath ?? item.originalImagePath,
                    fallbackPath: item.originalImagePath,
                    storage: storage,
                    height: height,
                    contentMode: .fit
                )
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(Color(.systemGray6))
            } else {
                Color(.systemGray6)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .overlay {
                        Image(systemName: "tshirt")
                            .foregroundStyle(AppColors.textTertiary)
                    }
            }

            Text(label)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(6)
        }
    }
}

struct RecommendationDetailView: View {
    let recommendation: OutfitRecommendation
    let storage: ImageStorage

    private var slots: OutfitSlotAssignment { recommendation.slots }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    FullOutfitPreview(slots: slots, storage: storage)
                        .frame(height: 260)

                    Text(recommendation.displayName)
                        .font(AppTypography.title)
                    Text(recommendation.rationale)
                        .foregroundColor(.secondary)
                    if let weather = recommendation.weatherSummary {
                        Label(weather, systemImage: "cloud.sun.fill")
                            .foregroundStyle(AppColors.primaryGradient)
                    }
                    Text(String(
                        format: NSLocalizedString("Confidence %d%%", comment: ""),
                        Int(recommendation.confidence * 100)
                    ))
                        .font(.headline)

                    Text(NSLocalizedString("Pieces", comment: "Outfit detail section"))
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
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name).font(.headline)
                                Text(item.category.displayName).foregroundColor(.secondary)
                                if let slot = OutfitWearSlot.slot(for: item.category) {
                                    Text(slot.displayName)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(AppColors.olive)
                                }
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
