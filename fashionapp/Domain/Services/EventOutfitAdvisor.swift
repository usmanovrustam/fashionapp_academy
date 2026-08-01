import Foundation

/// Suggests wardrobe pieces that fit a calendar event type.
enum EventOutfitAdvisor {
    static func suggest(
        from wardrobe: [WardrobeItem],
        eventType: DayEventType,
        limit: Int = 8
    ) -> [WardrobeItem] {
        let available = wardrobe.filter(\.isAvailableToWear)
        guard !available.isEmpty else { return [] }

        let scored = available
            .map { ($0, score(item: $0, eventType: eventType)) }
            .filter { $0.1 > 0.15 }
            .sorted { $0.1 > $1.1 }

        var selected: [WardrobeItem] = []
        var used = Set<ClothingCategory>()
        for (item, _) in scored {
            if selected.count >= limit { break }
            if used.contains(item.category), selected.count < min(4, limit) { continue }
            selected.append(item)
            used.insert(item.category)
        }
        if selected.count < min(4, limit) {
            for (item, _) in scored where !selected.contains(where: { $0.id == item.id }) {
                selected.append(item)
                if selected.count >= limit { break }
            }
        }
        return selected
    }

    private static func score(item: WardrobeItem, eventType: DayEventType) -> Double {
        let profile = profile(for: eventType)
        var value = 0.2

        if profile.formality.contains(item.formalityScore) {
            value += 0.35
        } else {
            let mid = (profile.formality.lowerBound + profile.formality.upperBound) / 2
            value += max(0, 0.25 - abs(item.formalityScore - mid))
        }

        if !Set(item.styleTags).isDisjoint(with: profile.tags) { value += 0.25 }
        if !Set(item.occasions).isDisjoint(with: profile.occasions) { value += 0.2 }
        if item.isFavorite { value += 0.05 }
        if item.category == .swimwear || item.category == .sleepwear { value -= 0.5 }
        return value
    }

    private static func profile(
        for eventType: DayEventType
    ) -> (formality: ClosedRange<Double>, tags: Set<StyleTag>, occasions: Set<Occasion>) {
        switch eventType {
        case .wedding:
            return (0.65...1.0, [.elegant, .formal, .weddingGuest, .quietLuxury], [.formal, .party])
        case .work, .interview:
            return (0.45...0.9, [.office, .business, .minimalist, .quietLuxury], [.work])
        case .dinner:
            return (0.35...0.8, [.date, .elegant, .nightOut, .casual], [.date, .everyday])
        case .party:
            return (0.4...0.95, [.nightOut, .elegant, .streetwear], [.party, .formal])
        case .religious, .family:
            return (0.35...0.85, [.elegant, .minimalist, .quietLuxury, .formal], [.formal, .everyday])
        case .other:
            return (0.2...0.8, [.casual, .minimalist], [.everyday])
        }
    }
}
