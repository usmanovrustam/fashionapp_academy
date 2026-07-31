import Foundation

/// Result of the computer-vision clothing scan pipeline.
struct ClothingScanResult: Equatable, Hashable {
    var detectedCategory: ClothingCategory
    var subcategory: String?
    var colorPalette: [String]
    var dominantColor: String?
    var material: Material
    var seasons: [Season]
    var temperatureBands: [TemperatureBand]
    var formalityScore: Double
    var styleTags: [StyleTag]
    var occasions: [Occasion]
    var genderNeutral: Bool
    var suggestedName: String
    var confidence: Double
    var originalImageData: Data
    var transparentImageData: Data?
    var processedAt: Date
}

enum ScanPipelineStage: String, CaseIterable {
    case detectClothing
    case segmentClothing
    case removeBackground
    case generateTransparentPNG
    case extractMetadata
    case persistAssets
}

struct ChatMessage: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var role: Role
    var content: String
    var createdAt: Date
    var recommendedOutfitIDs: [UUID]

    enum Role: String, Codable {
        case user
        case assistant
        case system
    }

    static func user(_ text: String) -> ChatMessage {
        ChatMessage(id: UUID(), role: .user, content: text, createdAt: Date(), recommendedOutfitIDs: [])
    }

    static func assistant(_ text: String, outfitIDs: [UUID] = []) -> ChatMessage {
        ChatMessage(id: UUID(), role: .assistant, content: text, createdAt: Date(), recommendedOutfitIDs: outfitIDs)
    }
}

struct StylingAssistantResponse: Equatable {
    var reply: String
    var recommendations: [OutfitRecommendation]
}
