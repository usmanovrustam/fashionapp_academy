import Foundation
import SwiftUI

/// Matches app pastel sky-blue brand.
enum WidgetBrand {
    static let sky = Color(red: 0.52, green: 0.74, blue: 0.94)
    static let powder = Color(red: 0.72, green: 0.86, blue: 0.96)
}

enum WidgetAppGroup {
    static let identifier = "group.apple.academy.stylo"
    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}

struct TodayOutfitSnapshot: Codable, Equatable {
    var outfitName: String
    var occasion: String
    var confidence: Double
    var rationale: String
    var weatherSummary: String?
    var temperatureText: String?
    var wardrobeCount: Int
    var updatedAt: Date

    static var placeholder: TodayOutfitSnapshot {
        TodayOutfitSnapshot(
            outfitName: "Quiet Luxury Look",
            occasion: "Office",
            confidence: 0.86,
            rationale: "Polished layers for a cool weekday.",
            weatherSummary: "Partly Cloudy · Milan",
            temperatureText: "18°C",
            wardrobeCount: 24,
            updatedAt: Date()
        )
    }

    static func load() -> TodayOutfitSnapshot? {
        guard let data = WidgetAppGroup.defaults.data(forKey: "widget.todayOutfit.snapshot") else {
            return nil
        }
        return try? JSONDecoder().decode(TodayOutfitSnapshot.self, from: data)
    }
}
