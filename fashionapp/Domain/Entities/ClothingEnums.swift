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
        case .top: return NSLocalizedString("Top", comment: "")
        case .bottom: return NSLocalizedString("Bottom", comment: "")
        case .shoes: return NSLocalizedString("Shoes", comment: "")
        case .dress: return NSLocalizedString("Dress", comment: "")
        case .jacket: return NSLocalizedString("Jacket", comment: "")
        case .coat: return NSLocalizedString("Coat", comment: "")
        case .accessories: return NSLocalizedString("Accessories", comment: "")
        case .hat: return NSLocalizedString("Hat", comment: "")
        case .scarf: return NSLocalizedString("Scarf", comment: "")
        case .jewelry: return NSLocalizedString("Jewelry", comment: "")
        case .bag: return NSLocalizedString("Bag", comment: "")
        case .watch: return NSLocalizedString("Watch", comment: "")
        case .belt: return NSLocalizedString("Belt", comment: "")
        case .sportswear: return NSLocalizedString("Sportswear", comment: "")
        case .formalwear: return NSLocalizedString("Formalwear", comment: "")
        case .sleepwear: return NSLocalizedString("Sleepwear", comment: "")
        case .swimwear: return NSLocalizedString("Swimwear", comment: "")
        case .other: return NSLocalizedString("Other", comment: "")
        }
    }
}

enum Season: String, Codable, CaseIterable, Hashable {
    case spring, summer, autumn, winter, allSeason

    var displayName: String {
        switch self {
        case .spring: return NSLocalizedString("Spring", comment: "")
        case .summer: return NSLocalizedString("Summer", comment: "")
        case .autumn: return NSLocalizedString("Autumn", comment: "")
        case .winter: return NSLocalizedString("Winter", comment: "")
        case .allSeason: return NSLocalizedString("All Season", comment: "")
        }
    }
}

enum Material: String, Codable, CaseIterable, Hashable {
    case cotton, linen, wool, silk, leather, denim, polyester, nylon
    case cashmere, velvet, suede, knit, unknown

    var displayName: String {
        switch self {
        case .cotton: return NSLocalizedString("Cotton", comment: "Material")
        case .linen: return NSLocalizedString("Linen", comment: "Material")
        case .wool: return NSLocalizedString("Wool", comment: "Material")
        case .silk: return NSLocalizedString("Silk", comment: "Material")
        case .leather: return NSLocalizedString("Leather", comment: "Material")
        case .denim: return NSLocalizedString("Denim", comment: "Material")
        case .polyester: return NSLocalizedString("Polyester", comment: "Material")
        case .nylon: return NSLocalizedString("Nylon", comment: "Material")
        case .cashmere: return NSLocalizedString("Cashmere", comment: "Material")
        case .velvet: return NSLocalizedString("Velvet", comment: "Material")
        case .suede: return NSLocalizedString("Suede", comment: "Material")
        case .knit: return NSLocalizedString("Knit", comment: "Material")
        case .unknown: return NSLocalizedString("Unknown", comment: "Material")
        }
    }
}

enum StyleTag: String, Codable, CaseIterable, Hashable {
    case casual, office, date, gym, travel, business, elegant
    case minimalist, streetwear, luxury, oldMoney, quietLuxury
    case summer, winter, rainy, snow, nightOut, weddingGuest, airport
    case formal, sporty, bohemian, vintage, preppy

    var displayName: String {
        switch self {
        case .oldMoney: return NSLocalizedString("Classic tailored", comment: "")
        case .quietLuxury: return NSLocalizedString("Understated", comment: "")
        case .luxury: return NSLocalizedString("Refined", comment: "")
        case .preppy: return NSLocalizedString("Neat casual", comment: "")
        case .nightOut: return NSLocalizedString("Evening out", comment: "")
        case .weddingGuest: return NSLocalizedString("Formal event", comment: "")
        default: return NSLocalizedString(rawValue.prefix(1).uppercased() + rawValue.dropFirst(), comment: "Style tag")
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
