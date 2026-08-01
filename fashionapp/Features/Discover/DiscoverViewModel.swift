import Foundation
import SwiftUI

@MainActor
final class DiscoverViewModel: ObservableObject {
    @Published var recommendations: [OutfitRecommendation] = []
    @Published var weather: WeatherSnapshot?
    @Published var forecast: [DailyWeatherForecast] = []
    @Published var isWeatherLoading = false
    @Published var weatherError: String?
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
            forecast = (try? await weatherProvider.dailyForecast(days: 3)) ?? []
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

    func formattedWind(_ kmh: Double) -> String {
        if usesCelsius {
            return "\(Int(kmh.rounded())) km/h"
        }
        let mph = kmh * 0.621371
        return "\(Int(mph.rounded())) mph"
    }

    func formattedHumidity(_ humidity: Double) -> String {
        "\(Int((humidity * 100).rounded()))%"
    }

    func formattedRain(_ probability: Double) -> String {
        "\(Int((probability * 100).rounded()))%"
    }

    func formattedUV(_ uvIndex: Double) -> String {
        "\(Int(uvIndex.rounded()))"
    }

    func weekdayLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
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
