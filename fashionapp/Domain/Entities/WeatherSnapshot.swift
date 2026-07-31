import Foundation

struct WeatherSnapshot: Codable, Equatable, Hashable {
    var temperatureCelsius: Double
    var apparentTemperatureCelsius: Double
    var humidity: Double
    var windSpeedKmh: Double
    var rainProbability: Double
    var uvIndex: Double
    var airQualityIndex: Double?
    var conditionSymbol: String
    var conditionDescription: String
    var locationName: String
    var fetchedAt: Date

    var temperatureBand: TemperatureBand {
        TemperatureBand.from(celsius: temperatureCelsius)
    }

    var isRainy: Bool { rainProbability >= 0.45 || conditionDescription.lowercased().contains("rain") }
    var isSnowy: Bool { conditionDescription.lowercased().contains("snow") }
}

struct DailyWeatherForecast: Identifiable, Codable, Equatable, Hashable {
    var id: Date { date }
    var date: Date
    var highCelsius: Double
    var lowCelsius: Double
    var symbolName: String
    var conditionDescription: String
}

struct CalendarEvent: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var title: String
    var startDate: Date
    var endDate: Date
    var location: String?
    var dressCode: String?
    var isAllDay: Bool
}

struct WardrobeStatistics: Codable, Equatable, Hashable {
    var totalItems: Int
    var favoritesCount: Int
    var wornThisWeek: Int
    var categoryCounts: [ClothingCategory: Int]
    var mostWornItemID: UUID?
    var leastWornItemID: UUID?
    var averageFormality: Double
}
