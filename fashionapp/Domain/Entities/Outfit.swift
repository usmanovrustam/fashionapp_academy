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
    /// Items the user has already packed (subset of `itemIDs`).
    var packedItemIDs: [UUID]
    var createdAt: Date

    init(
        id: UUID,
        title: String,
        destination: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        itemIDs: [UUID] = [],
        packedItemIDs: [UUID] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.destination = destination
        self.startDate = startDate
        self.endDate = endDate
        self.itemIDs = itemIDs
        self.packedItemIDs = packedItemIDs
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        destination = try container.decodeIfPresent(String.self, forKey: .destination)
        startDate = try container.decodeIfPresent(Date.self, forKey: .startDate)
        endDate = try container.decodeIfPresent(Date.self, forKey: .endDate)
        itemIDs = try container.decodeIfPresent([UUID].self, forKey: .itemIDs) ?? []
        packedItemIDs = try container.decodeIfPresent([UUID].self, forKey: .packedItemIDs) ?? []
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}
