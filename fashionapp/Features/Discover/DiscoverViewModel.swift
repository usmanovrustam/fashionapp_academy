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

    init(container: AppContainer) {
        self.recommendationsUseCase = container.dailyRecommendationsUseCase
        self.weatherProvider = container.weatherProvider
        self.wardrobeRepository = container.wardrobeRepository
        self.imageStorage = container.imageStorage
        self.settings = container.settings
    }

    var usesCelsius: Bool { settings.usesCelsius }

    func load() async {
        isLoading = true
        errorMessage = nil
        topIndex = 0

        do {
            weather = try await weatherProvider.currentWeather()
        } catch {
            weather = nil
        }

        do {
            recommendations = try await recommendationsUseCase.execute(limit: 8)
            if recommendations.isEmpty {
                let items = try await wardrobeRepository.fetchAll()
                recommendations = items.prefix(8).map { item in
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
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func formattedTemperature(_ celsius: Double) -> String {
        if usesCelsius {
            return "\(Int(celsius.rounded()))°"
        }
        let f = celsius * 9 / 5 + 32
        return "\(Int(f.rounded()))°"
    }

    func advance() {
        guard topIndex < recommendations.count else { return }
        topIndex += 1
    }
}
