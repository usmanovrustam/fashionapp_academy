import Foundation

/// Suggests wardrobe pieces to pack from destination season + forecast.
enum TravelPackingAdvisor {
    struct Result: Equatable {
        var season: Season
        var weatherSummary: String
        var suggestedItems: [WardrobeItem]
        var packingTips: [String]
    }

    static func analyze(
        wardrobe: [WardrobeItem],
        forecasts: [DailyWeatherForecast],
        tripStart: Date,
        tripEnd: Date,
        destinationName: String
    ) -> Result {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: tripStart)
        let end = calendar.startOfDay(for: tripEnd)

        let tripDays = forecasts.filter { day in
            let d = calendar.startOfDay(for: day.date)
            return d >= start && d <= end
        }
        let relevant = tripDays.isEmpty ? forecasts : tripDays

        let avgHigh = relevant.map(\.highCelsius).average ?? 20
        let avgLow = relevant.map(\.lowCelsius).average ?? 12
        let rainyDays = relevant.filter {
            $0.conditionDescription.lowercased().contains("rain")
                || $0.conditionDescription.lowercased().contains("drizzle")
                || $0.conditionDescription.lowercased().contains("thunder")
        }.count
        let snowy = relevant.contains { $0.conditionDescription.lowercased().contains("snow") }

        let season = season(for: tripStart, averageCelsius: (avgHigh + avgLow) / 2)
        let band = TemperatureBand.from(celsius: (avgHigh + avgLow) / 2)

        var tips: [String] = []
        tips.append("Expect highs around \(Int(avgHigh))°C and lows around \(Int(avgLow))°C.")
        tips.append("\(destinationName) looks like \(season.displayName.lowercased()) packing weather.")
        if rainyDays > 0 {
            tips.append("Rain possible on \(rainyDays) day(s) — pack a jacket or water-resistant layer.")
        }
        if snowy {
            tips.append("Snow is in the forecast — prioritize warm layers and sturdy shoes.")
        }
        if band == .hot || band == .warm {
            tips.append("Keep looks light and breathable; skip heavy coats.")
        }
        if band == .cold || band == .freezing {
            tips.append("Layer knits and a coat; leave summer pieces at home.")
        }

        let available = wardrobe.filter(\.isAvailableToWear)
        let scored = available.map { item -> (WardrobeItem, Double) in
            (item, score(item: item, season: season, band: band, rainy: rainyDays > 0, snowy: snowy))
        }
        .filter { $0.1 > 0.2 }
        .sorted { $0.1 > $1.1 }

        var selected: [WardrobeItem] = []
        var usedCategories = Set<ClothingCategory>()

        // Diversify categories first, then fill remaining slots.
        for (item, _) in scored {
            if selected.count >= 12 { break }
            if usedCategories.contains(item.category), selected.count < 6 { continue }
            selected.append(item)
            usedCategories.insert(item.category)
        }
        if selected.count < 8 {
            for (item, _) in scored where !selected.contains(where: { $0.id == item.id }) {
                selected.append(item)
                if selected.count >= 10 { break }
            }
        }

        let summaryParts = [
            "\(destinationName)",
            "\(season.displayName)",
            "\(Int(avgLow))–\(Int(avgHigh))°C"
        ]
        if rainyDays > 0 { /* keep tips separate */ }

        return Result(
            season: season,
            weatherSummary: summaryParts.joined(separator: " · "),
            suggestedItems: selected,
            packingTips: tips
        )
    }

    static func season(for date: Date, averageCelsius: Double) -> Season {
        let month = Calendar.current.component(.month, from: date)
        let hemispheric: Season
        switch month {
        case 12, 1, 2: hemispheric = .winter
        case 3, 4, 5: hemispheric = .spring
        case 6, 7, 8: hemispheric = .summer
        default: hemispheric = .autumn
        }

        // Prefer temperature when it clearly contradicts calendar season (e.g. southern hemisphere).
        switch averageCelsius {
        case ..<5: return .winter
        case ..<12: return hemispheric == .summer ? .spring : (hemispheric == .winter ? .winter : .autumn)
        case ..<20: return hemispheric == .winter ? .spring : hemispheric
        case ..<28: return averageCelsius >= 22 ? .summer : hemispheric
        default: return .summer
        }
    }

    private static func score(
        item: WardrobeItem,
        season: Season,
        band: TemperatureBand,
        rainy: Bool,
        snowy: Bool
    ) -> Double {
        var value = 0.25
        if item.seasons.contains(season) || item.seasons.contains(.allSeason) {
            value += 0.35
        }
        if item.temperatureBands.contains(band) {
            value += 0.3
        }
        if rainy && (item.category == .jacket || item.category == .coat || item.styleTags.contains(.rainy)) {
            value += 0.2
        }
        if snowy && (item.category == .coat || item.styleTags.contains(.snow) || item.styleTags.contains(.winter)) {
            value += 0.25
        }
        if item.styleTags.contains(.travel) || item.styleTags.contains(.airport) {
            value += 0.1
        }
        if item.isFavorite { value += 0.05 }
        if item.category == .swimwear && season != .summer { value -= 0.4 }
        if (item.category == .coat || item.category == .jacket) && (band == .hot || band == .warm) {
            value -= 0.25
        }
        return value
    }
}

private extension Array where Element == Double {
    var average: Double? {
        guard !isEmpty else { return nil }
        return reduce(0, +) / Double(count)
    }
}
