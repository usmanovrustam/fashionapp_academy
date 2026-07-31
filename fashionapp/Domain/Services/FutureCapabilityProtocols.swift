import Foundation

// MARK: - Future AI capabilities
// These protocols reserve extension points without shipping unfinished UI.

/// Virtual try-on against a user body avatar.
protocol VirtualTryOnServing: AnyObject {
    func renderTryOn(itemID: UUID, avatarImageData: Data) async throws -> Data
}

/// Body-shape analysis for fit recommendations.
protocol BodyShapeAnalyzing: AnyObject {
    func analyze(imageData: Data) async throws -> String
}

/// Seasonal color analysis (e.g. warm/cool autumn).
protocol ColorSeasonAnalyzing: AnyObject {
    func analyze(imageData: Data) async throws -> String
}

/// Trend detection for shopping and styling cues.
protocol FashionTrendDetecting: AnyObject {
    func currentTrends(for styles: [StyleTag]) async throws -> [String]
}

/// Shopping recommendations for missing wardrobe gaps.
protocol ShoppingRecommending: AnyObject {
    func suggestPurchases(for wardrobe: [WardrobeItem]) async throws -> [String]
}

/// Closet organization helpers.
protocol ClosetOrganizing: AnyObject {
    func suggestOrganization(for wardrobe: [WardrobeItem]) async throws -> [String]
}

/// Laundry tracking integration.
protocol LaundryTracking: AnyObject {
    func markInLaundry(itemID: UUID) async throws
    func markClean(itemID: UUID) async throws
}

/// Visual search across the wardrobe.
protocol WardrobeImageSearching: AnyObject {
    func search(similarTo imageData: Data, in wardrobe: [WardrobeItem]) async throws -> [UUID]
}

/// Voice assistant façade.
protocol VoiceAssisting: AnyObject {
    func handleSpeech(_ transcript: String) async throws -> StylingAssistantResponse
}

/// Smart mirror integration hook.
protocol SmartMirrorIntegrating: AnyObject {
    func pushOutfit(_ recommendation: OutfitRecommendation) async throws
}

struct MissingWardrobeSuggestion: Identifiable, Equatable, Hashable {
    var id: UUID
    var category: ClothingCategory
    var reason: String
    var priority: Double
}

protocol CapsuleWardrobePlanning: AnyObject {
    func buildCapsule(from wardrobe: [WardrobeItem], targetCount: Int) async throws -> [UUID]
    func missingEssentials(in wardrobe: [WardrobeItem]) async throws -> [MissingWardrobeSuggestion]
}

/// Default offline implementation for missing-piece suggestions.
final class BasicCapsulePlanner: CapsuleWardrobePlanning {
    private let essentials: [ClothingCategory] = [
        .top, .bottom, .shoes, .jacket, .dress
    ]

    func buildCapsule(from wardrobe: [WardrobeItem], targetCount: Int) async throws -> [UUID] {
        Array(wardrobe.sorted { $0.wornCount > $1.wornCount }.prefix(targetCount).map(\.id))
    }

    func missingEssentials(in wardrobe: [WardrobeItem]) async throws -> [MissingWardrobeSuggestion] {
        let present = Set(wardrobe.map(\.category))
        return essentials.compactMap { category in
            guard !present.contains(category) else { return nil }
            return MissingWardrobeSuggestion(
                id: UUID(),
                category: category,
                reason: "Your capsule wardrobe is missing a \(category.displayName.lowercased()).",
                priority: 0.8
            )
        }
    }
}
