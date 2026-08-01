import Foundation
import WidgetKit

/// Publishes glanceable outfit data to the App Group for iOS 27 widgets.
enum WidgetSnapshotStore {
    private static let key = "widget.todayOutfit.snapshot"

    struct Snapshot: Codable, Equatable {
        var outfitName: String
        var occasion: String
        var confidence: Double
        var rationale: String
        var weatherSummary: String?
        var temperatureText: String?
        var wardrobeCount: Int
        var updatedAt: Date
    }

    static func save(_ snapshot: Snapshot) {
        if let existing = load(),
           existing.outfitName == snapshot.outfitName,
           existing.occasion == snapshot.occasion,
           existing.confidence == snapshot.confidence,
           existing.rationale == snapshot.rationale,
           existing.weatherSummary == snapshot.weatherSummary,
           existing.temperatureText == snapshot.temperatureText,
           existing.wardrobeCount == snapshot.wardrobeCount {
            return
        }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        AppGroupConfig.defaults.set(data, forKey: key)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func load() -> Snapshot? {
        guard let data = AppGroupConfig.defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    static func publish(
        recommendation: OutfitRecommendation?,
        weather: WeatherSnapshot?,
        wardrobeCount: Int,
        usesCelsius: Bool
    ) {
        let temperatureText: String?
        if let weather {
            if usesCelsius {
                temperatureText = "\(Int(weather.temperatureCelsius.rounded()))°C"
            } else {
                let f = weather.temperatureCelsius * 9 / 5 + 32
                temperatureText = "\(Int(f.rounded()))°F"
            }
        } else {
            temperatureText = nil
        }

        let snapshot = Snapshot(
            outfitName: recommendation?.displayName ?? "Scan your first piece",
            occasion: recommendation?.occasion.displayName ?? "Wardrobe",
            confidence: recommendation?.confidence ?? 0,
            rationale: recommendation?.rationale
                ?? "Add clothes to get daily AI outfit ideas.",
            weatherSummary: weather.map { "\($0.conditionDescription) · \($0.locationName)" },
            temperatureText: temperatureText,
            wardrobeCount: wardrobeCount,
            updatedAt: Date()
        )
        save(snapshot)
    }
}
