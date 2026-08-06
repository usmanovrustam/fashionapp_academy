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

    /// Stages shown during on-device scan (persist happens later on save).
    static var scanUIStages: [ScanPipelineStage] {
        [.detectClothing, .segmentClothing, .removeBackground, .generateTransparentPNG, .extractMetadata]
    }

    var displayName: String {
        switch self {
        case .detectClothing: return NSLocalizedString("Detecting garment", comment: "ML scan stage")
        case .segmentClothing: return NSLocalizedString("Segmenting clothing", comment: "ML scan stage")
        case .removeBackground: return NSLocalizedString("Isolating object", comment: "ML scan stage")
        case .generateTransparentPNG: return NSLocalizedString("Building cutout", comment: "ML scan stage")
        case .extractMetadata: return NSLocalizedString("Reading colors & details", comment: "ML scan stage")
        case .persistAssets: return NSLocalizedString("Saving assets", comment: "ML scan stage")
        }
    }

    /// Overall 0…1 progress for the scan UI (excludes persist).
    var scanFraction: Double {
        guard let idx = Self.scanUIStages.firstIndex(of: self) else { return 1 }
        return Double(idx) / Double(Self.scanUIStages.count)
    }
}

/// Live update emitted while the clothing scan pipeline runs.
struct ScanPipelineProgress: Sendable, Equatable {
    var stage: ScanPipelineStage
    /// Overall progress 0…1 for the scan UI.
    var fraction: Double
    /// Optional JPEG/PNG preview of the current intermediate (mask, crop, cutout).
    var previewImageData: Data?
    var detail: String?

    init(
        stage: ScanPipelineStage,
        fraction: Double? = nil,
        previewImageData: Data? = nil,
        detail: String? = nil
    ) {
        self.stage = stage
        self.fraction = fraction ?? min(1, stage.scanFraction + (1 / Double(ScanPipelineStage.scanUIStages.count)))
        self.previewImageData = previewImageData
        self.detail = detail
    }
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
