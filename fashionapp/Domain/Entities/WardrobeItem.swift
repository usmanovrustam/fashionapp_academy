import Foundation

/// A single clothing item in the digital wardrobe.
struct WardrobeItem: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var name: String
    var originalImagePath: String
    var transparentImagePath: String?
    var category: ClothingCategory
    var subcategory: String?
    var colorPalette: [String]
    var dominantColor: String?
    var material: Material
    var seasons: [Season]
    var temperatureBands: [TemperatureBand]
    var formalityScore: Double          // 0.0 casual → 1.0 formal
    var styleTags: [StyleTag]
    var occasions: [Occasion]
    var genderNeutral: Bool
    var aiConfidence: Double            // 0.0 → 1.0
    var purchaseDate: Date?
    var isFavorite: Bool
    var wornCount: Int
    var lastWornAt: Date?
    var isInLaundry: Bool
    /// Listed in the local giveaway store for nearby free handoffs.
    var isListedForDonate: Bool
    var listedForDonateAt: Date?
    var notes: String?
    var plannedDate: Date?
    var createdAt: Date
    var updatedAt: Date

    var primarySeason: Season { seasons.first ?? .allSeason }

    /// Available for wear recommendations (not washing, not in the giveaway store).
    var isAvailableToWear: Bool { !isInLaundry && !isListedForDonate }

    init(
        id: UUID,
        name: String,
        originalImagePath: String,
        transparentImagePath: String? = nil,
        category: ClothingCategory,
        subcategory: String? = nil,
        colorPalette: [String] = [],
        dominantColor: String? = nil,
        material: Material,
        seasons: [Season],
        temperatureBands: [TemperatureBand],
        formalityScore: Double,
        styleTags: [StyleTag],
        occasions: [Occasion],
        genderNeutral: Bool,
        aiConfidence: Double,
        purchaseDate: Date? = nil,
        isFavorite: Bool = false,
        wornCount: Int = 0,
        lastWornAt: Date? = nil,
        isInLaundry: Bool = false,
        isListedForDonate: Bool = false,
        listedForDonateAt: Date? = nil,
        notes: String? = nil,
        plannedDate: Date? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.originalImagePath = originalImagePath
        self.transparentImagePath = transparentImagePath
        self.category = category
        self.subcategory = subcategory
        self.colorPalette = colorPalette
        self.dominantColor = dominantColor
        self.material = material
        self.seasons = seasons
        self.temperatureBands = temperatureBands
        self.formalityScore = formalityScore
        self.styleTags = styleTags
        self.occasions = occasions
        self.genderNeutral = genderNeutral
        self.aiConfidence = aiConfidence
        self.purchaseDate = purchaseDate
        self.isFavorite = isFavorite
        self.wornCount = wornCount
        self.lastWornAt = lastWornAt
        self.isInLaundry = isInLaundry
        self.isListedForDonate = isListedForDonate
        self.listedForDonateAt = listedForDonateAt
        self.notes = notes
        self.plannedDate = plannedDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        originalImagePath = try container.decode(String.self, forKey: .originalImagePath)
        transparentImagePath = try container.decodeIfPresent(String.self, forKey: .transparentImagePath)
        category = try container.decode(ClothingCategory.self, forKey: .category)
        subcategory = try container.decodeIfPresent(String.self, forKey: .subcategory)
        colorPalette = try container.decodeIfPresent([String].self, forKey: .colorPalette) ?? []
        dominantColor = try container.decodeIfPresent(String.self, forKey: .dominantColor)
        material = try container.decode(Material.self, forKey: .material)
        seasons = try container.decodeIfPresent([Season].self, forKey: .seasons) ?? [.allSeason]
        temperatureBands = try container.decodeIfPresent([TemperatureBand].self, forKey: .temperatureBands)
            ?? TemperatureBand.allCases
        formalityScore = try container.decodeIfPresent(Double.self, forKey: .formalityScore) ?? 0.3
        styleTags = try container.decodeIfPresent([StyleTag].self, forKey: .styleTags) ?? [.casual]
        occasions = try container.decodeIfPresent([Occasion].self, forKey: .occasions) ?? [.everyday]
        genderNeutral = try container.decodeIfPresent(Bool.self, forKey: .genderNeutral) ?? false
        aiConfidence = try container.decodeIfPresent(Double.self, forKey: .aiConfidence) ?? 0
        purchaseDate = try container.decodeIfPresent(Date.self, forKey: .purchaseDate)
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        wornCount = try container.decodeIfPresent(Int.self, forKey: .wornCount) ?? 0
        lastWornAt = try container.decodeIfPresent(Date.self, forKey: .lastWornAt)
        isInLaundry = try container.decodeIfPresent(Bool.self, forKey: .isInLaundry) ?? false
        isListedForDonate = try container.decodeIfPresent(Bool.self, forKey: .isListedForDonate) ?? false
        listedForDonateAt = try container.decodeIfPresent(Date.self, forKey: .listedForDonateAt)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        plannedDate = try container.decodeIfPresent(Date.self, forKey: .plannedDate)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    static func placeholder(
        name: String = "New Item",
        category: ClothingCategory = .top
    ) -> WardrobeItem {
        let now = Date()
        return WardrobeItem(
            id: UUID(),
            name: name,
            originalImagePath: "",
            transparentImagePath: nil,
            category: category,
            subcategory: nil,
            colorPalette: [],
            dominantColor: nil,
            material: .unknown,
            seasons: [.allSeason],
            temperatureBands: TemperatureBand.allCases,
            formalityScore: 0.3,
            styleTags: [.casual],
            occasions: [.everyday],
            genderNeutral: false,
            aiConfidence: 0,
            purchaseDate: nil,
            isFavorite: false,
            wornCount: 0,
            lastWornAt: nil,
            isInLaundry: false,
            isListedForDonate: false,
            listedForDonateAt: nil,
            notes: nil,
            plannedDate: nil,
            createdAt: now,
            updatedAt: now
        )
    }
}

/// Presentation-friendly snapshot used by UI cards (decoupled from UIImage).
struct WardrobeItemCardModel: Identifiable, Hashable {
    let id: UUID
    let name: String
    let category: ClothingCategory
    let dominantColor: String?
    let styleTags: [StyleTag]
    let isFavorite: Bool
    let imagePath: String?
    let aiConfidence: Double
}
