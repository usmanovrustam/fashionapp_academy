import Foundation
import UIKit

/// One garment pulled out of a full-outfit photo (SegFormer multi-class masks).
struct DecomposedItemDraft: Equatable, Sendable {
    var classID: Int
    var labelName: String
    var category: ClothingCategory
    var subcategory: String
    var confidence: Double
    var squareCropJPEG: Data
    var transparentPNG: Data?
    var suggestedName: String
    var colorPalette: [String]
    var dominantColor: String?
    var material: Material
    var seasons: [Season]
    var formalityScore: Double
}

/// Splits a single photo into separate wardrobe-ready garment cutouts.
/// Uses ClothesSegFormer class masks (no arms/legs/face) + `ImageProcessing.applyMask`.
final class OutfitDecomposer: @unchecked Sendable {
    private let segFormerParser: ClothesSegFormerParser
    private let metadataExtractor: ClothingMetadataExtractor

    init(
        segFormerParser: ClothesSegFormerParser = .shared,
        metadataExtractor: ClothingMetadataExtractor = ColorAwareMetadataExtractor()
    ) {
        self.segFormerParser = segFormerParser
        self.metadataExtractor = metadataExtractor
    }

    func decompose(imageData: Data) async throws -> [DecomposedItemDraft] {
        guard !imageData.isEmpty else { throw DomainError.invalidImage }
        guard segFormerParser.isAvailable else {
            throw DomainError.scanFailed("ClothesSegFormer model is not bundled.")
        }

        let (prepared, items) = try await segFormerParser.extractAllGarments(imageData: imageData)
        var drafts: [DecomposedItemDraft] = []
        drafts.reserveCapacity(items.count)

        for item in items {
            let cleanedMask = ImageProcessing.cleanedMask(item.mask, threshold: 128, mode: .semantic)
                ?? item.mask
            // Skip tiny / empty masks after cleanup.
            guard ImageProcessing.maskCoverage(cleanedMask) >= 0.004 else { continue }

            let square: UIImage
            let squareMask: UIImage
            do {
                square = try ImageProcessing.centeredSquareCrop(image: prepared, mask: cleanedMask, padding: 0.08)
                squareMask = try ImageProcessing.centeredSquareCrop(image: cleanedMask, mask: cleanedMask, padding: 0.08)
            } catch {
                continue
            }

            // applyMask uses Int-safe RGB×alpha — must not use UInt8 multiply.
            let cutout = try? ImageProcessing.applyMask(image: square, mask: squareMask)
            let squareJPEG = (try? ImageProcessing.jpegData(from: square, quality: 0.92)) ?? Data()
            let transparentPNG = cutout.flatMap { try? ImageProcessing.pngData(from: $0) }

            let mapping = Self.mapLabel(item.classID)
            let metaSource: Data
            if let transparentPNG, !transparentPNG.isEmpty {
                metaSource = transparentPNG
            } else {
                metaSource = squareJPEG
            }
            let metadata = (try? await metadataExtractor.extract(
                from: metaSource,
                category: mapping.category
            ))

            let colorPrefix = metadata?.dominantColor.map { "\($0) " } ?? ""
            let suggested = "\(colorPrefix)\(mapping.subcategory)".trimmingCharacters(in: .whitespaces)

            drafts.append(DecomposedItemDraft(
                classID: item.classID,
                labelName: item.labelName,
                category: mapping.category,
                subcategory: mapping.subcategory,
                confidence: item.score,
                squareCropJPEG: squareJPEG,
                transparentPNG: transparentPNG,
                suggestedName: suggested.isEmpty ? mapping.subcategory : suggested,
                colorPalette: metadata?.colorPalette ?? [],
                dominantColor: metadata?.dominantColor,
                material: metadata?.material ?? .unknown,
                seasons: metadata?.seasons ?? [.allSeason],
                formalityScore: metadata?.formalityScore ?? 0.35
            ))
        }

        guard !drafts.isEmpty else { throw DomainError.noClothingDetected }
        return drafts
    }

    /// Best single item — used when the scanner still saves one wardrobe entry.
    func decomposeBest(imageData: Data) async throws -> DecomposedItemDraft {
        let drafts = try await decompose(imageData: imageData)
        guard let best = drafts.max(by: { $0.confidence < $1.confidence }) else {
            throw DomainError.noClothingDetected
        }
        return best
    }

    private static func mapLabel(_ classID: Int) -> (category: ClothingCategory, subcategory: String) {
        switch classID {
        case 1: return (.hat, "Hat")
        case 3: return (.accessories, "Sunglasses")
        case 4: return (.top, "Top")
        case 5: return (.bottom, "Skirt")
        case 6: return (.bottom, "Pants / Jeans")
        case 7: return (.dress, "Dress")
        case 8: return (.belt, "Belt")
        case 9, 10: return (.shoes, "Shoes / Sneakers")
        case 16: return (.bag, "Bag")
        case 17: return (.scarf, "Scarf")
        default: return (.other, "Clothing")
        }
    }
}
