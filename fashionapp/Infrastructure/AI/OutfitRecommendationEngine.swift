import Foundation

/// Rule-based recommendation engine that scores wardrobe combinations.
/// Emits only **complete** daily looks:
/// - Separates: top + bottom + shoes
/// - One-piece: dress + shoes (bottom not required)
final class RuleBasedOutfitRecommender: OutfitRecommending {
    func recommend(
        from wardrobe: [WardrobeItem],
        context: RecommendationContext,
        limit: Int
    ) async throws -> [OutfitRecommendation] {
        let available = wardrobe.filter(\.isAvailableToWear)
        let coverage = WardrobeOutfitCoverage.analyze(available)
        guard coverage.canBuildFullOutfit else { return [] }

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
        var usedItemIDs = Set<UUID>()
        let uniqueOccasions = Array(NSOrderedSet(array: weatherBoosted)) as? [OutfitOccasion] ?? weatherBoosted

        for occasion in uniqueOccasions {
            guard results.count < limit else { break }
            if let recommendation = buildFullOutfit(
                occasion: occasion,
                wardrobe: available,
                context: context,
                excluding: usedItemIDs,
                preferDress: coverage.canBuildDressLook && shouldPreferDress(context: context)
            ) {
                results.append(recommendation)
                usedItemIDs.formUnion(recommendation.items.map(\.id))
            }
        }

        // Fill remaining with alternate complete looks (dress or separates).
        var attempts = 0
        while results.count < limit && attempts < limit * 3 {
            attempts += 1
            let preferDress = attempts % 2 == 0 && coverage.canBuildDressLook
            guard let recommendation = buildFullOutfit(
                occasion: .casual,
                wardrobe: available,
                context: context,
                excluding: usedItemIDs,
                preferDress: preferDress
            ) else { break }
            results.append(recommendation)
            usedItemIDs.formUnion(recommendation.items.map(\.id))
        }

        return Array(results.prefix(limit))
    }

    private func shouldPreferDress(context: RecommendationContext) -> Bool {
        switch context.user.gender {
        case .woman:
            return true
        case .man:
            return false
        case .preferNotToSay, .none:
            guard let weather = context.weather else { return false }
            switch weather.temperatureBand {
            case .hot, .warm: return true
            default: return false
            }
        }
    }

    private func buildFullOutfit(
        occasion: OutfitOccasion,
        wardrobe: [WardrobeItem],
        context: RecommendationContext,
        excluding: Set<UUID>,
        preferDress: Bool
    ) -> OutfitRecommendation? {
        let pool = wardrobe.filter { !excluding.contains($0.id) }
        guard !pool.isEmpty else { return nil }

        let scored = pool.map { item -> (WardrobeItem, Double) in
            (item, score(item: item, occasion: occasion, context: context))
        }
        .sorted { $0.1 > $1.1 }

        let paths: [Bool] = preferDress ? [true, false] : [false, true]
        for useDress in paths {
            if let built = useDress
                ? assembleDressLook(scored: scored, occasion: occasion, context: context)
                : assembleSeparatesLook(scored: scored, occasion: occasion, context: context)
            {
                return built
            }
        }
        return nil
    }

    private func assembleDressLook(
        scored: [(WardrobeItem, Double)],
        occasion: OutfitOccasion,
        context: RecommendationContext
    ) -> OutfitRecommendation? {
        guard let dress = scored.first(where: { $0.0.category == .dress && $0.1 > 0.12 })?.0,
              let shoes = scored.first(where: { $0.0.category == .shoes && $0.0.id != dress.id })?.0
        else { return nil }

        var selected = [dress, shoes]
        // Optional bag — does not affect completeness.
        if let bag = scored.first(where: {
            $0.0.category == .bag && $0.0.id != dress.id && $0.0.id != shoes.id
        })?.0 {
            selected.append(bag)
        }

        return makeRecommendation(selected: selected, occasion: occasion, context: context)
    }

    private func assembleSeparatesLook(
        scored: [(WardrobeItem, Double)],
        occasion: OutfitOccasion,
        context: RecommendationContext
    ) -> OutfitRecommendation? {
        guard let top = scored.first(where: { $0.0.category == .top && $0.1 > 0.12 })?.0,
              let bottom = scored.first(where: {
                  $0.0.category == .bottom && $0.0.id != top.id
              })?.0,
              let shoes = scored.first(where: {
                  $0.0.category == .shoes && $0.0.id != top.id && $0.0.id != bottom.id
              })?.0
        else { return nil }

        var selected = [top, bottom, shoes]
        // Optional layer for cold / rain.
        if let weather = context.weather,
           weather.temperatureBand == .cold || weather.temperatureBand == .freezing || weather.isRainy,
           let outer = scored.first(where: {
               ($0.0.category == .jacket || $0.0.category == .coat)
                   && !selected.contains($0.0)
           })?.0
        {
            selected.insert(outer, at: 0)
        }

        return makeRecommendation(selected: selected, occasion: occasion, context: context)
    }

    private func makeRecommendation(
        selected: [WardrobeItem],
        occasion: OutfitOccasion,
        context: RecommendationContext
    ) -> OutfitRecommendation? {
        let slots = OutfitSlotAssignment.from(items: selected)
        guard slots.isComplete else { return nil }

        let ordered = slots.orderedItems
        // Keep optional extras (bag / jacket) after core slots.
        let extras = selected.filter { item in !ordered.contains(item) }
        let finalItems = ordered + extras

        let confidence = min(
            0.98,
            finalItems.map { score(item: $0, occasion: occasion, context: context) }.reduce(0, +)
                / Double(max(finalItems.count, 1))
        )

        let name: String
        if slots.isDressLook {
            name = String(
                format: NSLocalizedString("%@ Dress Look", comment: "Full outfit name with dress"),
                occasion.displayName
            )
        } else {
            name = String(
                format: NSLocalizedString("%@ Look", comment: "Full outfit name"),
                occasion.displayName
            )
        }

        let outfit = Outfit(
            id: UUID(),
            name: name,
            itemIDs: finalItems.map(\.id),
            occasion: occasion,
            styleTags: Array(Set(finalItems.flatMap(\.styleTags))),
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
            items: finalItems,
            occasion: occasion,
            confidence: confidence,
            rationale: rationale(for: occasion, slots: slots, items: finalItems, context: context),
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

        if let lastWorn = item.lastWornAt, Date().timeIntervalSince(lastWorn) < 2 * 24 * 3600 {
            value -= 0.1
        }

        value += item.aiConfidence * 0.1
        return max(0, min(1, value))
    }

    private func rationale(
        for occasion: OutfitOccasion,
        slots: OutfitSlotAssignment,
        items: [WardrobeItem],
        context: RecommendationContext
    ) -> String {
        var parts: [String] = []

        if slots.isDressLook {
            parts.append(NSLocalizedString(
                "One-piece look with shoes — no separate bottom needed.",
                comment: "Dress outfit rationale"
            ))
        } else {
            parts.append(NSLocalizedString(
                "Full look: top, bottom, and shoes.",
                comment: "Separates outfit rationale"
            ))
        }

        parts.append(String(
            format: NSLocalizedString("Selected for %@.", comment: "Occasion rationale"),
            occasion.displayName.lowercased()
        ))

        if let weather = context.weather {
            parts.append(
                String(
                    format: NSLocalizedString(
                        "Weather is %@ around %d°C.",
                        comment: "Weather rationale"
                    ),
                    weather.conditionDescription.lowercased(),
                    Int(weather.temperatureCelsius)
                )
            )
        }

        if context.isWeekend {
            parts.append(NSLocalizedString("Weekend-friendly styling.", comment: ""))
        } else {
            parts.append(NSLocalizedString("Balanced for a weekday schedule.", comment: ""))
        }

        if items.contains(where: \.isFavorite) {
            parts.append(NSLocalizedString("Uses one of your favorite items.", comment: ""))
        }

        let colors = items.compactMap(\.dominantColor)
        if !colors.isEmpty {
            parts.append(String(
                format: NSLocalizedString("Color story: %@.", comment: ""),
                colors.joined(separator: ", ")
            ))
        }

        return parts.joined(separator: " ")
    }
}
