import Foundation

/// High-level wardrobe categories used by the clothing scanner.
enum ClothingCategory: String, Codable, CaseIterable, Identifiable, Hashable {
    case top
    case bottom
    case shoes
    case dress
    case jacket
    case coat
    case accessories
    case hat
    case scarf
    case jewelry
    case bag
    case watch
    case belt
    case sportswear
    case formalwear
    case sleepwear
    case swimwear
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .top: return "Top"
        case .bottom: return "Bottom"
        case .shoes: return "Shoes"
        case .dress: return "Dress"
        case .jacket: return "Jacket"
        case .coat: return "Coat"
        case .accessories: return "Accessories"
        case .hat: return "Hat"
        case .scarf: return "Scarf"
        case .jewelry: return "Jewelry"
        case .bag: return "Bag"
        case .watch: return "Watch"
        case .belt: return "Belt"
        case .sportswear: return "Sportswear"
        case .formalwear: return "Formalwear"
        case .sleepwear: return "Sleepwear"
        case .swimwear: return "Swimwear"
        case .other: return "Other"
        }
    }
}

enum Season: String, Codable, CaseIterable, Hashable {
    case spring, summer, autumn, winter, allSeason

    var displayName: String {
        switch self {
        case .spring: return "Spring"
        case .summer: return "Summer"
        case .autumn: return "Autumn"
        case .winter: return "Winter"
        case .allSeason: return "All Season"
        }
    }
}

enum Material: String, Codable, CaseIterable, Hashable {
    case cotton, linen, wool, silk, leather, denim, polyester, nylon
    case cashmere, velvet, suede, knit, unknown

    var displayName: String { rawValue.capitalized }
}

enum StyleTag: String, Codable, CaseIterable, Hashable {
    case casual, office, date, gym, travel, business, elegant
    case minimalist, streetwear, luxury, oldMoney, quietLuxury
    case summer, winter, rainy, snow, nightOut, weddingGuest, airport
    case formal, sporty, bohemian, vintage, preppy

    var displayName: String {
        switch self {
        case .oldMoney: return "Old Money"
        case .quietLuxury: return "Quiet Luxury"
        case .nightOut: return "Night Out"
        case .weddingGuest: return "Wedding Guest"
        default: return rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }
}

enum Occasion: String, Codable, CaseIterable, Hashable {
    case everyday, work, date, party, formal, sport, travel, outdoor, lounge
}

enum OutfitOccasion: String, Codable, CaseIterable, Identifiable, Hashable {
    case casual, office, date, gym, travel, business, elegant
    case minimalist, streetwear, luxury, oldMoney, quietLuxury
    case summer, winter, rainy, snow, nightOut, weddingGuest, airport

    var id: String { rawValue }

    var styleTag: StyleTag {
        StyleTag(rawValue: rawValue) ?? .casual
    }

    var displayName: String { styleTag.displayName }
}

enum TemperatureBand: String, Codable, CaseIterable, Hashable {
    case freezing   // < 0°C
    case cold       // 0–10
    case cool       // 10–18
    case mild       // 18–24
    case warm       // 24–30
    case hot        // > 30

    static func from(celsius: Double) -> TemperatureBand {
        switch celsius {
        case ..<0: return .freezing
        case ..<10: return .cold
        case ..<18: return .cool
        case ..<24: return .mild
        case ..<30: return .warm
        default: return .hot
        }
    }
}
