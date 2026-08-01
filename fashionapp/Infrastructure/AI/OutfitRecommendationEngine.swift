import Foundation

/// Rule-based recommendation engine that scores wardrobe combinations.
/// Swap this implementation without changing feature code.
final class RuleBasedOutfitRecommender: OutfitRecommending {
    func recommend(
        from wardrobe: [WardrobeItem],
        context: RecommendationContext,
        limit: Int
    ) async throws -> [OutfitRecommendation] {
        let available = wardrobe.filter(\.isAvailableToWear)
        guard !available.isEmpty else { return [] }

        let occasions: [OutfitOccasion]
        if !context.preferredOccasions.isEmpty {
            occasions = context.preferredOccasions
        } else {
            occasions = context.isWeekend
                ? [.casual, .date, .travel]
                : [.office, .business, .casual]
        }

        var weatherBoosted = occasions
        if let weather = context.weather {
            if weather.isRainy { weatherBoosted.insert(.rainy, at: 0) }
            if weather.isSnowy { weatherBoosted.insert(.snow, at: 0) }
            switch weather.temperatureBand {
            case .hot, .warm: weatherBoosted.insert(.summer, at: 0)
            case .cold, .freezing: weatherBoosted.insert(.winter, at: 0)
            default: break
            }
        }

        var results: [OutfitRecommendation] = []
        let uniqueOccasions = Array(NSOrderedSet(array: weatherBoosted)) as? [OutfitOccasion] ?? weatherBoosted

        for occasion in uniqueOccasions.prefix(limit) {
            if let recommendation = buildOutfit(
                occasion: occasion,
                wardrobe: available,
                context: context
            ) {
                results.append(recommendation)
            }
        }

        // Fill remaining slots with favorite-forward casual looks.
        if results.count < limit {
            let favorites = available.filter(\.isFavorite)
            let pool = favorites.isEmpty ? available : favorites
            for item in pool.prefix(limit - results.count) {
                let outfit = Outfit(
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
                )
                results.append(
                    OutfitRecommendation(
                        id: UUID(),
                        outfit: outfit,
                        items: [item],
                        occasion: .casual,
                        confidence: max(0.4, item.aiConfidence),
                        rationale: rationale(for: .casual, items: [item], context: context),
                        weatherSummary: context.weather.map {
                            "\($0.conditionDescription), \(Int($0.temperatureCelsius))°C"
                        },
                        generatedAt: Date()
                    )
                )
            }
        }

        return Array(results.prefix(limit))
    }

    private func buildOutfit(
        occasion: OutfitOccasion,
        wardrobe: [WardrobeItem],
        context: RecommendationContext
    ) -> OutfitRecommendation? {
        let scored = wardrobe.map { item -> (WardrobeItem, Double) in
            (item, score(item: item, occasion: occasion, context: context))
        }
        .sorted { $0.1 > $1.1 }

        guard let best = scored.first, best.1 > 0.15 else { return nil }

        var selected: [WardrobeItem] = [best.0]
        let needed = complementaryCategories(for: best.0.category)

        for category in needed {
            if let match = scored.first(where: {
                $0.0.category == category && !selected.contains($0.0)
            })?.0 {
                selected.append(match)
            }
        }

        let confidence = min(0.98, selected.map { score(item: $0, occasion: occasion, context: context) }.reduce(0, +) / Double(selected.count))
        let outfit = Outfit(
            id: UUID(),
            name: "\(occasion.displayName) Look",
            itemIDs: selected.map(\.id),
            occasion: occasion,
            styleTags: Array(Set(selected.flatMap(\.styleTags))),
            isFavorite: false,
            wornCount: 0,
            lastWornAt: nil,
            plannedDate: nil,
            notes: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        return OutfitRecommendation(
            id: UUID(),
            outfit: outfit,
            items: selected,
            occasion: occasion,
            confidence: confidence,
            rationale: rationale(for: occasion, items: selected, context: context),
            weatherSummary: context.weather.map {
                "\($0.conditionDescription), \(Int($0.temperatureCelsius))°C in \($0.locationName)"
            },
            generatedAt: Date()
        )
    }

    private func score(item: WardrobeItem, occasion: OutfitOccasion, context: RecommendationContext) -> Double {
        var value = 0.25

        if item.styleTags.contains(occasion.styleTag) { value += 0.3 }
        if context.user.stylePreferences.contains(where: { item.styleTags.contains($0) }) { value += 0.15 }
        if item.isFavorite { value += 0.1 }
        if context.user.avoidCategories.contains(item.category) { value -= 0.5 }

        if let weather = context.weather {
            if item.temperatureBands.contains(weather.temperatureBand) { value += 0.2 }
            else { value -= 0.15 }
            if weather.isRainy && (item.category == .coat || item.category == .jacket || item.styleTags.contains(.rainy)) {
                value += 0.15
            }
        }

        // Prefer less recently worn items for variety.
        if let lastWorn = item.lastWornAt, Date().timeIntervalSince(lastWorn) < 2 * 24 * 3600 {
            value -= 0.1
        }

        value += item.aiConfidence * 0.1
        return max(0, min(1, value))
    }

    private func complementaryCategories(for category: ClothingCategory) -> [ClothingCategory] {
        switch category {
        case .top: return [.bottom, .shoes]
        case .bottom: return [.top, .shoes]
        case .dress: return [.shoes, .bag]
        case .shoes: return [.top, .bottom]
        case .jacket, .coat: return [.top, .bottom, .shoes]
        default: return [.top, .bottom]
        }
    }

    private func rationale(
        for occasion: OutfitOccasion,
        items: [WardrobeItem],
        context: RecommendationContext
    ) -> String {
        var parts: [String] = ["Selected for \(occasion.displayName.lowercased())."]

        if let weather = context.weather {
            parts.append(
                "Weather is \(weather.conditionDescription.lowercased()) around \(Int(weather.temperatureCelsius))°C."
            )
            if weather.isRainy {
                parts.append("Includes pieces suited for rain.")
            }
        }

        if context.isWeekend {
            parts.append("Weekend-friendly styling.")
        } else {
            parts.append("Balanced for a weekday schedule.")
        }

        if items.contains(where: \.isFavorite) {
            parts.append("Uses one of your favorite items.")
        }

        let colors = items.compactMap(\.dominantColor)
        if !colors.isEmpty {
            parts.append("Color story: \(colors.joined(separator: ", ")).")
        }

        return parts.joined(separator: " ")
    }
}
