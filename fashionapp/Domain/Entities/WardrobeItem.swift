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
    var notes: String?
    var plannedDate: Date?
    var createdAt: Date
    var updatedAt: Date

    var primarySeason: Season { seasons.first ?? .allSeason }

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
