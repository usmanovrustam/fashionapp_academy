import Foundation

/// A composed look made of one or more wardrobe items.
struct Outfit: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var name: String
    var itemIDs: [UUID]
    var occasion: OutfitOccasion
    var styleTags: [StyleTag]
    var isFavorite: Bool
    var wornCount: Int
    var lastWornAt: Date?
    var plannedDate: Date?
    var notes: String?
    var createdAt: Date
    var updatedAt: Date

    static func empty(name: String, occasion: OutfitOccasion = .casual) -> Outfit {
        let now = Date()
        return Outfit(
            id: UUID(),
            name: name,
            itemIDs: [],
            occasion: occasion,
            styleTags: [occasion.styleTag],
            isFavorite: false,
            wornCount: 0,
            lastWornAt: nil,
            plannedDate: nil,
            notes: nil,
            createdAt: now,
            updatedAt: now
        )
    }
}

struct OutfitRecommendation: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var outfit: Outfit
    var items: [WardrobeItem]
    var occasion: OutfitOccasion
    var confidence: Double
    var rationale: String
    var weatherSummary: String?
    var generatedAt: Date

    var displayName: String { outfit.name }
}

struct OutfitHistoryEntry: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var outfitID: UUID
    var wornAt: Date
    var occasion: OutfitOccasion?
    var notes: String?
}

struct PackingList: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var title: String
    var destination: String?
    var startDate: Date?
    var endDate: Date?
    var itemIDs: [UUID]
    var createdAt: Date
}
