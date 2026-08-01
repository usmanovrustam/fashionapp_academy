import Foundation
import UIKit

/// Heuristic clothing detector / metadata extractor.
/// Replaceable later with Vision classification or a custom CoreML model.
final class HeuristicClothingDetector: ClothingDetector {
    func detectCategory(in imageData: Data) async throws -> (ClothingCategory, Double) {
        let image = try ImageProcessing.uiImage(from: imageData)
        let aspect = image.size.height / max(image.size.width, 1)

        // Aspect-ratio heuristics — intentionally simple and swappable.
        if aspect > 1.6 {
            return (.dress, 0.55)
        }
        if aspect > 1.25 {
            return (.coat, 0.45)
        }
        if aspect < 0.75 {
            return (.shoes, 0.5)
        }
        if aspect < 0.95 {
            return (.accessories, 0.4)
        }
        return (.top, 0.5)
    }
}

final class ColorAwareMetadataExtractor: ClothingMetadataExtractor {
    func extract(from imageData: Data, category: ClothingCategory) async throws -> ClothingMetadata {
        let image = try ImageProcessing.uiImage(from: imageData)
        let colors = ImageProcessing.dominantColors(from: image)
        let palette = colors.map(ImageProcessing.hexString)
        let names = colors.map(ImageProcessing.colorName)
        let dominantName = names.first
        let brightness = averageBrightness(colors)

        let material = inferMaterial(category: category, brightness: brightness)
        let seasons = inferSeasons(brightness: brightness, category: category)
        let bands = seasons.flatMap { temperatureBands(for: $0) }
        let uniqueBands = Array(Set(bands)).sorted { $0.rawValue < $1.rawValue }
        let formality = inferFormality(category: category, colorName: dominantName)
        let styles = inferStyles(category: category, formality: formality, seasons: seasons)
        let occasions = inferOccasions(styles: styles)
        let subcategory = defaultSubcategory(for: category)
        let name = [
            dominantName,
            material == .unknown ? nil : material.displayName,
            subcategory ?? category.displayName
        ]
        .compactMap { $0 }
        .joined(separator: " ")

        return ClothingMetadata(
            subcategory: subcategory,
            colorPalette: palette,
            dominantColor: dominantName,
            material: material,
            seasons: seasons,
            temperatureBands: uniqueBands.isEmpty ? TemperatureBand.allCases : uniqueBands,
            formalityScore: formality,
            styleTags: styles,
            occasions: occasions,
            genderNeutral: true,
            suggestedName: name.isEmpty ? category.displayName : name,
            confidence: 0.62
        )
    }

    private func averageBrightness(_ colors: [UIColor]) -> CGFloat {
        guard !colors.isEmpty else { return 0.5 }
        let total = colors.reduce(CGFloat(0)) { partial, color in
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            return partial + b
        }
        return total / CGFloat(colors.count)
    }

    private func inferMaterial(category: ClothingCategory, brightness: CGFloat) -> Material {
        switch category {
        case .shoes, .belt, .bag: return brightness < 0.35 ? .leather : .suede
        case .bottom: return .denim
        case .sportswear, .swimwear: return .nylon
        case .coat, .jacket: return brightness < 0.4 ? .wool : .polyester
        case .dress, .formalwear: return brightness > 0.7 ? .silk : .cotton
        case .scarf: return .cashmere
        default: return .cotton
        }
    }

    private func inferSeasons(brightness: CGFloat, category: ClothingCategory) -> [Season] {
        if category == .coat || category == .scarf {
            return [.autumn, .winter]
        }
        if category == .swimwear {
            return [.summer]
        }
        if brightness > 0.75 {
            return [.spring, .summer]
        }
        if brightness < 0.3 {
            return [.autumn, .winter]
        }
        return [.allSeason]
    }

    private func temperatureBands(for season: Season) -> [TemperatureBand] {
        switch season {
        case .winter: return [.freezing, .cold]
        case .autumn: return [.cold, .cool]
        case .spring: return [.cool, .mild]
        case .summer: return [.mild, .warm, .hot]
        case .allSeason: return TemperatureBand.allCases
        }
    }

    private func inferFormality(category: ClothingCategory, colorName: String?) -> Double {
        switch category {
        case .formalwear, .watch: return 0.85
        case .dress, .coat, .jacket: return 0.7
        case .sportswear, .swimwear, .sleepwear: return 0.15
        case .shoes:
            return (colorName == "Black" || colorName == "Brown") ? 0.65 : 0.35
        default:
            return colorName == "Black" ? 0.55 : 0.35
        }
    }

    private func inferStyles(category: ClothingCategory, formality: Double, seasons: [Season]) -> [StyleTag] {
        var tags: [StyleTag] = []
        if formality >= 0.75 {
            tags.append(contentsOf: [.business, .elegant, .quietLuxury])
        } else if formality >= 0.5 {
            tags.append(contentsOf: [.office, .minimalist])
        } else {
            tags.append(.casual)
        }

        if category == .sportswear { tags.append(.gym) }
        if seasons.contains(.summer) { tags.append(.summer) }
        if seasons.contains(.winter) { tags.append(.winter) }
        if category == .jacket || category == .coat { tags.append(.travel) }

        return Array(Set(tags))
    }

    private func inferOccasions(styles: [StyleTag]) -> [Occasion] {
        var occasions: Set<Occasion> = [.everyday]
        if styles.contains(.office) || styles.contains(.business) { occasions.insert(.work) }
        if styles.contains(.date) || styles.contains(.elegant) { occasions.insert(.date) }
        if styles.contains(.gym) { occasions.insert(.sport) }
        if styles.contains(.travel) || styles.contains(.airport) { occasions.insert(.travel) }
        return Array(occasions)
    }

    private func defaultSubcategory(for category: ClothingCategory) -> String? {
        switch category {
        case .top: return "T-Shirt"
        case .bottom: return "Trousers"
        case .shoes: return "Sneakers"
        case .dress: return "Midi Dress"
        case .jacket: return "Jacket"
        case .coat: return "Coat"
        case .hat: return "Cap"
        case .bag: return "Tote"
        case .sportswear: return "Activewear"
        default: return nil
        }
    }
}

/// Orchestrates the swappable CV stages into a single scan result.
final class DefaultClothingScanPipeline: ClothingScanPipeline {
    private let detector: ClothingDetector
    private let segmenter: ClothingSegmenter
    private let backgroundRemover: BackgroundRemover
    private let metadataExtractor: ClothingMetadataExtractor

    init(
        detector: ClothingDetector,
        segmenter: ClothingSegmenter,
        backgroundRemover: BackgroundRemover,
        metadataExtractor: ClothingMetadataExtractor
    ) {
        self.detector = detector
        self.segmenter = segmenter
        self.backgroundRemover = backgroundRemover
        self.metadataExtractor = metadataExtractor
    }

    func scan(imageData: Data) async throws -> ClothingScanResult {
        guard !imageData.isEmpty else { throw DomainError.invalidImage }

        let (category, detectionConfidence) = try await detector.detectCategory(in: imageData)
        let maskData = try await segmenter.segment(imageData: imageData)

        let transparentData: Data?
        do {
            transparentData = try await backgroundRemover.removeBackground(
                imageData: imageData,
                maskData: maskData
            )
        } catch {
            transparentData = nil
        }

        let metadataSource = transparentData ?? imageData
        let metadata = try await metadataExtractor.extract(from: metadataSource, category: category)
        let confidence = min(1, (detectionConfidence + metadata.confidence) / 2)

        return ClothingScanResult(
            detectedCategory: category,
            subcategory: metadata.subcategory,
            colorPalette: metadata.colorPalette,
            dominantColor: metadata.dominantColor,
            material: metadata.material,
            seasons: metadata.seasons,
            temperatureBands: metadata.temperatureBands,
            formalityScore: metadata.formalityScore,
            styleTags: metadata.styleTags,
            occasions: metadata.occasions,
            genderNeutral: metadata.genderNeutral,
            suggestedName: metadata.suggestedName,
            confidence: confidence,
            originalImageData: imageData,
            transparentImageData: transparentData,
            processedAt: Date()
        )
    }
}
