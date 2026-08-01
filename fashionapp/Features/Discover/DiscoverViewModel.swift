import Foundation
import SwiftUI

@MainActor
final class DiscoverViewModel: ObservableObject {
    @Published var recommendations: [OutfitRecommendation] = []
    @Published var weather: WeatherSnapshot?
    @Published var isWeatherLoading = false
    @Published var weatherError: String?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var topIndex = 0

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

        await refreshWeather()

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

    func refreshWeather() async {
        isWeatherLoading = true
        weatherError = nil

        do {
            let snapshot = try await weatherProvider.currentWeather()
            weather = snapshot
            analytics.track(.weatherLoaded, parameters: [
                "condition": snapshot.conditionDescription,
                "temp_c": String(Int(snapshot.temperatureCelsius)),
                "location": String(snapshot.locationName.prefix(40))
            ])
        } catch {
            if weather == nil {
                weatherError = error.localizedDescription
            }
        }

        isWeatherLoading = false
    }

    func formattedTemperature(_ celsius: Double) -> String {
        "\(Int(converted(celsius).rounded()))°"
    }

    func formattedTemperatureValue(_ celsius: Double) -> String {
        "\(Int(converted(celsius).rounded()))"
    }

    func temperatureUnitLabel() -> String {
        usesCelsius ? "C" : "F"
    }

    /// Compact wind line for the weather card (outfit-relevant without extra metrics).
    func windSummary(_ kmh: Double) -> String {
        let speed = usesCelsius ? kmh : kmh * 0.621371
        let unit = usesCelsius ? "km/h" : "mph"
        let value = Int(speed.rounded())
        switch kmh {
        case ..<12:
            return "Light wind · \(value) \(unit)"
        case 12..<25:
            return "Breezy · \(value) \(unit)"
        case 25..<40:
            return "Windy · \(value) \(unit)"
        default:
            return "Strong wind · \(value) \(unit)"
        }
    }

    private func converted(_ celsius: Double) -> Double {
        usesCelsius ? celsius : celsius * 9 / 5 + 32
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
