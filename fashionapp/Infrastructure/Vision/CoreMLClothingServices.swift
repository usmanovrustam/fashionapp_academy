import Foundation
import UIKit

/// CoreML-backed clothing detector (replaces the aspect-ratio heuristic).
final class CoreMLClothingDetector: ClothingDetector {
    private let model: CoreMLFashionModel

    init(model: CoreMLFashionModel) {
        self.model = model
    }

    func detectCategory(in imageData: Data) async throws -> (ClothingCategory, Double) {
        let prediction = try model.predict(imageData: imageData)
        return (prediction.category, prediction.categoryConfidence)
    }
}

/// CoreML-backed metadata extractor (replaces the pixel-bucket rule chain).
/// Category/gender/season/usage/base-colour come from the trained model;
/// the colour palette still uses the pixel sampler for a richer hex swatch set.
final class CoreMLClothingMetadataExtractor: ClothingMetadataExtractor {
    private let model: CoreMLFashionModel

    init(model: CoreMLFashionModel) {
        self.model = model
    }

    func extract(from imageData: Data, category: ClothingCategory) async throws -> ClothingMetadata {
        let prediction = try model.predict(imageData: imageData)
        let image = try ImageProcessing.uiImage(from: imageData)
        let palette = ImageProcessing.dominantColors(from: image).map(ImageProcessing.hexString)

        let seasons: [Season] = prediction.season.map { [$0] } ?? [.allSeason]
        let bands = Array(Set(seasons.flatMap(Self.temperatureBands(for:))))
            .sorted { $0.rawValue < $1.rawValue }
        let formality = Self.formality(for: prediction.usage, category: category)
        let styles = Self.styleTags(for: prediction.usage, seasons: seasons)
        let occasions = Self.occasions(for: styles)
        let name = [prediction.color, category.displayName].joined(separator: " ")

        return ClothingMetadata(
            subcategory: nil,
            colorPalette: palette,
            dominantColor: prediction.color,
            material: .unknown,
            seasons: seasons,
            temperatureBands: bands.isEmpty ? TemperatureBand.allCases : bands,
            formalityScore: formality,
            styleTags: styles,
            occasions: occasions,
            genderNeutral: prediction.gender == "Unisex",
            suggestedName: name,
            confidence: prediction.categoryConfidence
        )
    }

    // MARK: - Attribute mapping

    static func temperatureBands(for season: Season) -> [TemperatureBand] {
        switch season {
        case .winter: return [.freezing, .cold]
        case .autumn: return [.cold, .cool]
        case .spring: return [.cool, .mild]
        case .summer: return [.mild, .warm, .hot]
        case .allSeason: return TemperatureBand.allCases
        }
    }

    static func formality(for usage: String, category: ClothingCategory) -> Double {
        switch usage {
        case "Formal": return 0.85
        case "Smart Casual": return 0.55
        case "Ethnic": return 0.6
        case "Sports": return 0.15
        default: return category == .formalwear ? 0.8 : 0.3
        }
    }

    static func styleTags(for usage: String, seasons: [Season]) -> [StyleTag] {
        var tags: [StyleTag] = []
        switch usage {
        case "Formal": tags += [.business, .elegant]
        case "Smart Casual": tags += [.office, .minimalist]
        case "Ethnic": tags += [.elegant]
        case "Sports": tags += [.gym, .sporty]
        default: tags.append(.casual)
        }
        if seasons.contains(.summer) { tags.append(.summer) }
        if seasons.contains(.winter) { tags.append(.winter) }
        return Array(Set(tags))
    }

    static func occasions(for styles: [StyleTag]) -> [Occasion] {
        var occasions: Set<Occasion> = [.everyday]
        if styles.contains(.office) || styles.contains(.business) { occasions.insert(.work) }
        if styles.contains(.elegant) { occasions.insert(.party) }
        if styles.contains(.gym) || styles.contains(.sporty) { occasions.insert(.sport) }
        return Array(occasions)
    }
}

/// CoreML embedding-based visual search across the wardrobe.
final class CoreMLWardrobeImageSearch: WardrobeImageSearching {
    private let model: CoreMLFashionModel
    private let imageStorage: ImageStorage

    init(model: CoreMLFashionModel, imageStorage: ImageStorage) {
        self.model = model
        self.imageStorage = imageStorage
    }

    func search(similarTo imageData: Data, in wardrobe: [WardrobeItem]) async throws -> [UUID] {
        let query = try model.embed(imageData: imageData)
        guard !query.isEmpty else { return [] }

        var scored: [(id: UUID, score: Float)] = []
        for item in wardrobe {
            let path = item.transparentImagePath ?? item.originalImagePath
            guard !path.isEmpty,
                  let data = try? await imageStorage.loadImageData(at: path),
                  let embedding = try? model.embed(imageData: data),
                  embedding.count == query.count else { continue }
            scored.append((item.id, Self.cosine(query, embedding)))
        }
        return scored.sorted { $0.score > $1.score }.map(\.id)
    }

    private static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        // Embeddings are already L2-normalized by the model, so this is a dot product.
        var sum: Float = 0
        for i in 0..<min(a.count, b.count) { sum += a[i] * b[i] }
        return sum
    }
}
