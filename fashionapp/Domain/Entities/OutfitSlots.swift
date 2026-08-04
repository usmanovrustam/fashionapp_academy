import Foundation

/// Wear roles for composing a daily full outfit.
enum OutfitWearSlot: String, Codable, CaseIterable, Identifiable {
    case top
    case bottom
    case body
    case shoes

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .top: return NSLocalizedString("Top", comment: "Outfit slot")
        case .bottom: return NSLocalizedString("Bottom", comment: "Outfit slot")
        case .body: return NSLocalizedString("Dress", comment: "One-piece outfit slot")
        case .shoes: return NSLocalizedString("Shoes", comment: "Outfit slot")
        }
    }

    /// Maps a wardrobe category onto a wear slot (nil = not part of core full look).
    static func slot(for category: ClothingCategory) -> OutfitWearSlot? {
        switch category {
        case .top: return .top
        case .bottom: return .bottom
        case .dress: return .body
        case .shoes: return .shoes
        default: return nil
        }
    }
}

/// Named pieces for a full day look.
struct OutfitSlotAssignment: Equatable, Hashable {
    var top: WardrobeItem?
    var bottom: WardrobeItem?
    /// One-piece (dress / jumpsuit). When set, top + bottom are unused.
    var body: WardrobeItem?
    var shoes: WardrobeItem?

    var isDressLook: Bool { body != nil }

    /// Complete = (top + bottom + shoes) OR (dress + shoes).
    var isComplete: Bool {
        if isDressLook { return shoes != nil }
        return top != nil && bottom != nil && shoes != nil
    }

    /// Display order for the Discover card / detail list.
    var orderedItems: [WardrobeItem] {
        if let body {
            return [body, shoes].compactMap { $0 }
        }
        return [top, bottom, shoes].compactMap { $0 }
    }

    var itemIDs: [UUID] { orderedItems.map(\.id) }

    static func from(items: [WardrobeItem]) -> OutfitSlotAssignment {
        var assignment = OutfitSlotAssignment()
        for item in items {
            switch OutfitWearSlot.slot(for: item.category) {
            case .top where assignment.top == nil:
                assignment.top = item
            case .bottom where assignment.bottom == nil:
                assignment.bottom = item
            case .body where assignment.body == nil:
                assignment.body = item
            case .shoes where assignment.shoes == nil:
                assignment.shoes = item
            default:
                break
            }
        }
        // Dress replaces separates when both somehow exist.
        if assignment.body != nil {
            assignment.top = nil
            assignment.bottom = nil
        }
        return assignment
    }
}

/// What the wardrobe can support for daily full outfits.
struct WardrobeOutfitCoverage: Equatable {
    var topCount: Int
    var bottomCount: Int
    var dressCount: Int
    var shoesCount: Int

    var hasTop: Bool { topCount > 0 }
    var hasBottom: Bool { bottomCount > 0 }
    var hasDress: Bool { dressCount > 0 }
    var hasShoes: Bool { shoesCount > 0 }

    /// Top+bottom **or** a one-piece dress.
    var hasBodyCoverage: Bool { (hasTop && hasBottom) || hasDress }

    var canBuildFullOutfit: Bool { hasBodyCoverage && hasShoes }

    var canBuildSeparatesLook: Bool { hasTop && hasBottom && hasShoes }
    var canBuildDressLook: Bool { hasDress && hasShoes }

    static func analyze(_ items: [WardrobeItem]) -> WardrobeOutfitCoverage {
        let available = items.filter(\.isAvailableToWear)
        return WardrobeOutfitCoverage(
            topCount: available.filter { $0.category == .top }.count,
            bottomCount: available.filter { $0.category == .bottom }.count,
            dressCount: available.filter { $0.category == .dress }.count,
            shoesCount: available.filter { $0.category == .shoes }.count
        )
    }

    /// Localized lines describing what’s still needed for a full look.
    var missingMessages: [String] {
        guard !canBuildFullOutfit else { return [] }

        if topCount + bottomCount + dressCount + shoesCount == 0 {
            return [NSLocalizedString(
                "Your wardrobe is empty. Scan a few pieces to get daily outfit ideas.",
                comment: "Discover gap empty wardrobe"
            )]
        }

        var lines: [String] = []

        if !hasBodyCoverage {
            if hasTop && !hasBottom && !hasDress {
                lines.append(NSLocalizedString(
                    "Add a bottom, or a dress, to complete the look.",
                    comment: "Discover gap bottom or dress"
                ))
            } else if hasBottom && !hasTop && !hasDress {
                lines.append(NSLocalizedString(
                    "Add a top, or a dress, to complete the look.",
                    comment: "Discover gap top or dress"
                ))
            } else {
                lines.append(NSLocalizedString(
                    "Add a top and bottom — or a dress — for a full look.",
                    comment: "Discover gap body"
                ))
            }
        }

        if !hasShoes {
            lines.append(NSLocalizedString(
                "Add shoes to finish a full daily outfit.",
                comment: "Discover gap shoes"
            ))
        }

        if lines.isEmpty {
            lines.append(NSLocalizedString(
                "Add a few more pieces so Nook can build a full outfit.",
                comment: "Discover gap generic"
            ))
        }

        return lines
    }
}

extension OutfitRecommendation {
    var slots: OutfitSlotAssignment { OutfitSlotAssignment.from(items: items) }

    var isFullOutfit: Bool { slots.isComplete }
}
