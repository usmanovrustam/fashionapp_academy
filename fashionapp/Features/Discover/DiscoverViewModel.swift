import Foundation
import SwiftUI

@MainActor
final class DiscoverViewModel: ObservableObject {
    @Published var recommendations: [OutfitRecommendation] = []
    @Published var weather: WeatherSnapshot?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var topIndex = 0
    @Published var showAssistant = false

    private let recommendationsUseCase: GenerateDailyRecommendationsUseCase
    private let weatherProvider: WeatherProviding
    private let wardrobeRepository: WardrobeRepository
    let imageStorage: ImageStorage
    private let settings: AppSettingsProviding
    private let analytics: AnalyticsTracking
    private var wardrobeCount = 0
    private var didLoadOnce = false

    init(container: AppContainer) {
        self.recommendationsUseCase = container.dailyRecommendationsUseCase
        self.weatherProvider = container.weatherProvider
        self.wardrobeRepository = container.wardrobeRepository
        self.imageStorage = container.imageStorage
        self.settings = container.settings
        self.analytics = container.analytics
    }

    var usesCelsius: Bool { settings.usesCelsius }

    func load(force: Bool = false) async {
        // Keep returning to Discover snappy — skip duplicate network unless forced / empty.
        if didLoadOnce && !force && !recommendations.isEmpty {
            return
        }

        let showSpinner = recommendations.isEmpty
        if showSpinner { isLoading = true }
        errorMessage = nil
        topIndex = 0
        analytics.track(.screenView, parameters: ["screen_name": "discover"])

        do {
            weather = try await weatherProvider.currentWeather()
            if let weather {
                analytics.track(.weatherLoaded, parameters: [
                    "condition": weather.conditionDescription,
                    "temp_c": String(Int(weather.temperatureCelsius))
                ])
            }
        } catch {
            weather = nil
        }

        do {
            let result = try await recommendationsUseCase.execute(
                limit: 8,
                prefetchedWeather: weather
            )
            wardrobeCount = result.wardrobeItems.count
            if weather == nil { weather = result.weather }

            if result.recommendations.isEmpty {
                recommendations = result.wardrobeItems.prefix(8).map { item in
                    OutfitRecommendation(
                        id: UUID(),
                        outfit: Outfit(
                            id: UUID(),
                            name: item.name,
                            itemIDs: [item.id],
                            occasion: .casual,
                            styleTags: item.styleTags,
                            isFavorite: item.isFavorite,
                            wornCount: 0,
                            lastWornAt: nil,
                            plannedDate: nil,
                            notes: nil,
                            createdAt: Date(),
                            updatedAt: Date()
                        ),
                        items: [item],
                        occasion: .casual,
                        confidence: item.aiConfidence,
                        rationale: "From your wardrobe.",
                        weatherSummary: nil,
                        generatedAt: Date()
                    )
                }
            } else {
                recommendations = result.recommendations
            }
            didLoadOnce = true
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false

        WidgetSnapshotStore.publish(
            recommendation: recommendations.first,
            weather: weather,
            wardrobeCount: wardrobeCount,
            usesCelsius: usesCelsius
        )
    }

    func formattedTemperature(_ celsius: Double) -> String {
        if usesCelsius {
            return "\(Int(celsius.rounded()))°"
        }
        let f = celsius * 9 / 5 + 32
        return "\(Int(f.rounded()))°"
    }

    func advance(accepted: Bool) {
        if topIndex < recommendations.count {
            let rec = recommendations[topIndex]
            analytics.track(
                accepted ? .recommendationAccepted : .recommendationRejected,
                parameters: [
                    "occasion": rec.occasion.rawValue,
                    "confidence": String(format: "%.2f", rec.confidence)
                ]
            )
        }
        guard topIndex < recommendations.count else { return }
        topIndex += 1
    }

    func trackRecommendationView(at index: Int) {
        guard recommendations.indices.contains(index) else { return }
        let rec = recommendations[index]
        analytics.track(.recommendationViewed, parameters: [
            "occasion": rec.occasion.rawValue,
            "confidence": String(format: "%.2f", rec.confidence)
        ])
    }
}
