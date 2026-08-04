import Foundation

/// Required profile gender — drives clothing options and full-outfit rules.
enum UserGender: String, Codable, CaseIterable, Identifiable, Hashable {
    case woman
    case man

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .woman: return NSLocalizedString("Woman", comment: "Gender option")
        case .man: return NSLocalizedString("Man", comment: "Gender option")
        }
    }

    /// Categories users can pick when scanning / reviewing a garment.
    var selectableClothingCategories: [ClothingCategory] {
        switch self {
        case .woman:
            return [.top, .bottom, .dress, .shoes, .jacket, .coat, .accessories, .bag, .hat, .scarf, .jewelry, .belt, .sportswear, .formalwear, .sleepwear, .swimwear, .other]
        case .man:
            return [.top, .bottom, .shoes, .jacket, .coat, .accessories, .bag, .hat, .scarf, .watch, .belt, .sportswear, .formalwear, .sleepwear, .swimwear, .other]
        }
    }

    /// Compact filter chips for the Wardrobe tab.
    var wardrobeFilterCategories: [ClothingCategory] {
        switch self {
        case .woman:
            return [.top, .bottom, .dress, .shoes, .jacket, .coat, .accessories]
        case .man:
            return [.top, .bottom, .shoes, .jacket, .coat, .accessories]
        }
    }
}
