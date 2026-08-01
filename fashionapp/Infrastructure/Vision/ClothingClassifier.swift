import Foundation
import UIKit
import Vision

/// On-device Vision clothing detector. Rejects photos with no apparel so the UI can ask for a retake.
final class HeuristicClothingDetector: ClothingDetector {
    private let presenceThreshold: Float = 0.12
    private let categoryThreshold: Float = 0.08

    func detectCategory(in imageData: Data) async throws -> (ClothingCategory, Double) {
        let image = try ImageProcessing.uiImage(from: imageData)
        // Downscale for Vision — full camera frames are unnecessary and heavy on the main thread.
        let analysisImage = ImageProcessing.resized(image, maxDimension: 1280)
        guard let cgImage = analysisImage.cgImage else { throw DomainError.invalidImage }

        let observations = try classify(cgImage)
        let apparelHits = observations.filter { isApparelRelated($0.identifier) }
        let bestPresence = apparelHits.map(\.confidence).max() ?? 0

        let mapped = observations.compactMap { observation -> (ClothingCategory, Float, String)? in
            guard let category = mapCategory(for: observation.identifier) else { return nil }
            return (category, observation.confidence, observation.identifier)
        }

        let hasCategorySignal = mapped.contains { $0.1 >= categoryThreshold }
        guard bestPresence >= presenceThreshold || hasCategorySignal else {
            throw DomainError.noClothingDetected
        }

        if let best = mapped.max(by: { $0.1 < $1.1 }), best.1 >= categoryThreshold {
            return (best.0, Double(max(best.1, 0.35)))
        }

        // Apparel present but label is generic — fall back to aspect heuristics.
        return aspectCategory(for: analysisImage)
    }

    /// Synchronous Vision classify — do NOT wrap `perform` in a checked continuation.
    /// `perform` both throws and invokes the completion handler on failure (double-resume crash).
    private func classify(_ cgImage: CGImage) throws -> [VNClassificationObservation] {
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw DomainError.scanFailed(error.localizedDescription)
        }
        return request.results ?? []
    }

    private func isApparelRelated(_ identifier: String) -> Bool {
        let id = identifier.lowercased()
        let keywords = [
            "apparel", "clothing", "garment", "fashion", "outerwear", "footwear",
            "shirt", "t-shirt", "tee", "blouse", "sweater", "hoodie", "sweatshirt",
            "jacket", "coat", "blazer", "parka", "windbreaker",
            "dress", "gown", "skirt", "jumpsuit", "romper",
            "pant", "pants", "trouser", "jean", "jeans", "short", "legging",
            "shoe", "sneaker", "boot", "sandal", "heel", "loafer",
            "hat", "cap", "beanie", "scarf", "shawl", "belt", "tie", "necktie",
            "bag", "handbag", "backpack", "purse", "tote", "watch",
            "jewelry", "necklace", "earring", "bracelet", "ring",
            "swim", "bikini", "swimsuit", "activewear", "sportswear", "jersey",
            "suit", "tuxedo", "pajama", "sleepwear", "robe", "lingerie",
            "denim", "sock", "glove", "sunglasses", "accessory"
        ]
        return keywords.contains { id.contains($0) }
    }

    private func mapCategory(for identifier: String) -> ClothingCategory? {
        let id = identifier.lowercased()

        let rules: [(ClothingCategory, [String])] = [
            (.dress, ["dress", "gown", "skirt", "jumpsuit", "romper"]),
            (.bottom, ["jean", "pant", "trouser", "short", "legging", "chino"]),
            (.shoes, ["shoe", "sneaker", "boot", "sandal", "heel", "loafer", "footwear"]),
            (.coat, ["coat", "overcoat", "parka", "trench"]),
            (.jacket, ["jacket", "blazer", "windbreaker", "bomber"]),
            (.hat, ["hat", "cap", "beanie", "fedora"]),
            (.scarf, ["scarf", "shawl"]),
            (.bag, ["bag", "handbag", "backpack", "purse", "tote"]),
            (.belt, ["belt"]),
            (.watch, ["watch"]),
            (.jewelry, ["jewelry", "necklace", "earring", "bracelet", "ring"]),
            (.swimwear, ["swim", "bikini", "swimsuit"]),
            (.sportswear, ["sport", "athletic", "activewear", "jersey", "gym"]),
            (.formalwear, ["suit", "tuxedo", "formalwear"]),
            (.sleepwear, ["sleep", "pajama", "robe", "lingerie"]),
            (.top, ["shirt", "blouse", "sweater", "hoodie", "sweatshirt", "tee", "t-shirt", "top", "tank"]),
            (.accessories, ["accessory", "sunglasses", "glove", "tie", "necktie"])
        ]

        for (category, keywords) in rules {
            if keywords.contains(where: { id.contains($0) }) {
                return category
            }
        }

        // Generic apparel without a specific garment type.
        if id.contains("apparel") || id.contains("clothing") || id.contains("garment") || id.contains("outerwear") {
            return .top
        }
        return nil
    }

    private func aspectCategory(for image: UIImage) -> (ClothingCategory, Double) {
        let aspect = image.size.height / max(image.size.width, 1)
        if aspect > 1.6 { return (.dress, 0.45) }
        if aspect > 1.25 { return (.coat, 0.4) }
        if aspect < 0.75 { return (.shoes, 0.45) }
        if aspect < 0.95 { return (.accessories, 0.35) }
        return (.top, 0.4)
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
/// Prefers SegFormer clothes parsing (detect + mask + centered square crop),
/// then falls back to Vision + U²-Net when the Core ML package is unavailable.
final class DefaultClothingScanPipeline: ClothingScanPipeline {
    private let detector: ClothingDetector
    private let segmenter: ClothingSegmenter
    private let backgroundRemover: BackgroundRemover
    private let metadataExtractor: ClothingMetadataExtractor
    private let clothesParser: ClothesSegFormerParser

    init(
        detector: ClothingDetector,
        segmenter: ClothingSegmenter,
        backgroundRemover: BackgroundRemover,
        metadataExtractor: ClothingMetadataExtractor,
        clothesParser: ClothesSegFormerParser = .shared
    ) {
        self.detector = detector
        self.segmenter = segmenter
        self.backgroundRemover = backgroundRemover
        self.metadataExtractor = metadataExtractor
        self.clothesParser = clothesParser
    }

    func scan(imageData: Data) async throws -> ClothingScanResult {
        guard !imageData.isEmpty else { throw DomainError.invalidImage }

        if clothesParser.isAvailable {
            return try await scanWithSegFormer(imageData: imageData)
        }
        return try await scanWithFallback(imageData: imageData)
    }

    /// SegFormer path: classify garment → square-center crop → cutout → metadata.
    private func scanWithSegFormer(imageData: Data) async throws -> ClothingScanResult {
        let parsed = try await clothesParser.parse(imageData: imageData)

        var transparentData: Data?
        do {
            transparentData = try await backgroundRemover.removeBackground(
                imageData: parsed.squareCropJPEG,
                maskData: parsed.squareMaskPNG
            )
        } catch {
            // Soft-fail cutout — still keep the square crop for Storage.
            transparentData = nil
        }

        let metadataSource = transparentData ?? parsed.squareCropJPEG
        var metadata = try await metadataExtractor.extract(
            from: metadataSource,
            category: parsed.category
        )
        // Prefer SegFormer type label over heuristic subcategory.
        metadata.subcategory = parsed.subcategory
        if !parsed.subcategory.isEmpty {
            let colorPrefix = metadata.dominantColor.map { "\($0) " } ?? ""
            metadata.suggestedName = "\(colorPrefix)\(parsed.subcategory)".trimmingCharacters(in: .whitespaces)
        }

        let confidence = min(1, (parsed.confidence + metadata.confidence) / 2)
        return ClothingScanResult(
            detectedCategory: parsed.category,
            subcategory: parsed.subcategory,
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
            // Square crop is what we store to Firebase Storage as the wardrobe photo.
            originalImageData: parsed.squareCropJPEG,
            transparentImageData: transparentData,
            processedAt: Date()
        )
    }

    /// Legacy Vision + U²-Net path with square crop from the soft mask.
    private func scanWithFallback(imageData: Data) async throws -> ClothingScanResult {
        let (category, detectionConfidence) = try await detector.detectCategory(in: imageData)

        var squareJPEG = imageData
        var transparentData: Data?
        do {
            let maskData = try await segmenter.segment(imageData: imageData)
            let image = try ImageProcessing.uiImage(from: imageData)
            let mask = try ImageProcessing.uiImage(from: maskData)
            let square = try ImageProcessing.centeredSquareCrop(image: image, mask: mask, padding: 0.12)
            let squareMask = try ImageProcessing.centeredSquareCrop(image: mask, mask: mask, padding: 0.12)
            squareJPEG = try ImageProcessing.jpegData(from: square, quality: 0.92)
            let squareMaskPNG = try ImageProcessing.pngData(from: squareMask)
            transparentData = try await backgroundRemover.removeBackground(
                imageData: squareJPEG,
                maskData: squareMaskPNG
            )
        } catch {
            transparentData = nil
        }

        let metadataSource = transparentData ?? squareJPEG
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
            originalImageData: squareJPEG,
            transparentImageData: transparentData,
            processedAt: Date()
        )
    }
}
