import Foundation
import UIKit
import CoreML

/// On-device clothes parser powered by Hugging Face `mattmdjaga/segformer_b2_clothes`
/// exported as `ClothesSegFormer.mlpackage`.
///
/// Detects garment classes (hat, shoes, pants, dress, bag, …), builds a mask,
/// and returns a centered square crop ready for Firebase Storage.
///
/// Safe for background threads: uses Core Graphics + pointer I/O (no UIGraphicsImageRenderer).
final class ClothesSegFormerParser: @unchecked Sendable {
    static let shared = ClothesSegFormerParser()

    private let model: MLModel?
    private let inputSize = 512
    private let mean: [Float] = [0.485, 0.456, 0.406]
    private let std: [Float] = [0.229, 0.224, 0.225]

    /// ATR / SegFormer clothes labels (index → name).
    private static let labels: [String] = [
        "Background", "Hat", "Hair", "Sunglasses", "Upper-clothes",
        "Skirt", "Pants", "Dress", "Belt", "Left-shoe", "Right-shoe",
        "Face", "Left-leg", "Right-leg", "Left-arm", "Right-arm", "Bag", "Scarf"
    ]

    /// Class indices that count as wearable / outfit items (not body / hair / bg).
    private static let garmentClassIDs: Set<Int> = [1, 3, 4, 5, 6, 7, 8, 9, 10, 16, 17]

    var isAvailable: Bool { model != nil }

    private init() {
        self.model = Self.loadModel()
        #if DEBUG
        if model != nil {
            print("✅ ClothesSegFormer loaded")
        } else {
            print("⚠️ ClothesSegFormer missing — scan will use Vision + U²-Net fallback")
        }
        #endif
    }

    struct ParseResult: Sendable {
        var category: ClothingCategory
        var subcategory: String
        var labelName: String
        var confidence: Double
        /// Centered square crop (JPEG bytes) — primary asset for Storage.
        var squareCropJPEG: Data
        /// Soft garment mask matching the square crop size (PNG grayscale).
        var squareMaskPNG: Data
    }

    func parse(imageData: Data) async throws -> ParseResult {
        guard let model else {
            throw DomainError.scanFailed("ClothesSegFormer model is not bundled.")
        }

        let image = try ImageProcessing.uiImage(from: imageData)
        let prepared = ImageProcessing.resized(image, maxDimension: 1600)

        let pixelValues = try makePixelValues(from: prepared)
        let input = try MLDictionaryFeatureProvider(dictionary: [
            "pixel_values": MLFeatureValue(multiArray: pixelValues)
        ])

        // Core ML prediction is async in current SDKs — keep off the main actor via caller.
        let output = try await model.prediction(from: input)
        let logits = output.featureValue(for: "logits")?.multiArrayValue
            ?? output.featureValue(for: "var_1196")?.multiArrayValue
        guard let logits else {
            throw DomainError.scanFailed("ClothesSegFormer produced no logits.")
        }

        let (classMap, width, height, scores) = try argmaxMap(from: logits)
        guard let best = pickBestGarment(scores: scores) else {
            throw DomainError.noClothingDetected
        }

        guard let maskFull = maskImage(
            classMap: classMap,
            width: width,
            height: height,
            targetClass: best.classID,
            targetSize: prepared.size
        ) else {
            throw DomainError.scanFailed("Failed to build garment mask.")
        }

        let square = try ImageProcessing.centeredSquareCrop(image: prepared, mask: maskFull, padding: 0.12)
        let squareMask = try ImageProcessing.centeredSquareCrop(image: maskFull, mask: maskFull, padding: 0.12)
        let jpeg = try ImageProcessing.jpegData(from: square, quality: 0.92)
        let maskPNG = try ImageProcessing.pngData(from: squareMask)

        let mapping = Self.mapLabel(best.classID)
        return ParseResult(
            category: mapping.category,
            subcategory: mapping.subcategory,
            labelName: Self.labels[best.classID],
            confidence: best.score,
            squareCropJPEG: jpeg,
            squareMaskPNG: maskPNG
        )
    }

    // MARK: - Model load

    private static func loadModel() -> MLModel? {
        let config = MLModelConfiguration()
        config.computeUnits = .all

        let candidates: [URL?] = [
            Bundle.main.url(forResource: "ClothesSegFormer", withExtension: "mlmodelc"),
            Bundle.main.url(forResource: "ClothesSegFormer", withExtension: "mlpackage"),
            Bundle.main.url(forResource: "ClothesSegFormer", withExtension: "mlmodel")
        ]

        for url in candidates.compactMap({ $0 }) {
            if let model = try? MLModel(contentsOf: url, configuration: config) {
                return model
            }
        }
        return nil
    }

    // MARK: - Preprocess (pointer-fast)

    private func makePixelValues(from image: UIImage) throws -> MLMultiArray {
        let width = inputSize
        let height = inputSize
        let rgba = try ImageProcessing.rgbaBytes(from: image, width: width, height: height)

        let array = try MLMultiArray(
            shape: [1, 3, NSNumber(value: height), NSNumber(value: width)],
            dataType: .float32
        )
        let plane = width * height
        let ptr = array.dataPointer.bindMemory(to: Float.self, capacity: 3 * plane)

        let inv255: Float = 1.0 / 255.0
        for i in 0..<plane {
            let o = i * 4
            let r = Float(rgba[o]) * inv255
            let g = Float(rgba[o + 1]) * inv255
            let b = Float(rgba[o + 2]) * inv255
            ptr[i] = (r - mean[0]) / std[0]
            ptr[plane + i] = (g - mean[1]) / std[1]
            ptr[2 * plane + i] = (b - mean[2]) / std[2]
        }
        return array
    }

    // MARK: - Postprocess (pointer-fast)

    private func argmaxMap(
        from logits: MLMultiArray
    ) throws -> (classMap: [UInt8], width: Int, height: Int, scores: [Float]) {
        let shape = logits.shape.map(\.intValue)
        guard shape.count >= 4 else {
            throw DomainError.scanFailed("Unexpected logits shape.")
        }
        let classes = shape[1]
        let height = shape[2]
        let width = shape[3]
        let plane = width * height

        var classMap = [UInt8](repeating: 0, count: plane)
        var pixelCounts = [Int](repeating: 0, count: classes)

        let count = logits.count
        // Copy to Float buffer (handles FLOAT16 storage via NSNumber bridge if needed).
        var floats = [Float](repeating: 0, count: count)
        switch logits.dataType {
        case .float32:
            let src = logits.dataPointer.bindMemory(to: Float.self, capacity: count)
            floats.withUnsafeMutableBufferPointer { dst in
                dst.baseAddress!.update(from: src, count: count)
            }
        case .float16:
            // FLOAT16 logits from Core ML mlprogram — widen to Float for argmax.
            let src = logits.dataPointer.bindMemory(to: UInt16.self, capacity: count)
            for i in 0..<count {
                floats[i] = Float(Float16(bitPattern: src[i]))
            }
        default:
            for i in 0..<count {
                floats[i] = logits[i].floatValue
            }
        }

        for i in 0..<plane {
            var bestClass = 0
            var bestValue = -Float.greatestFiniteMagnitude
            for c in 0..<classes {
                let value = floats[c * plane + i]
                if value > bestValue {
                    bestValue = value
                    bestClass = c
                }
            }
            classMap[i] = UInt8(bestClass)
            pixelCounts[bestClass] += 1
        }

        let total = Float(max(plane, 1))
        let scores = pixelCounts.map { Float($0) / total }
        return (classMap, width, height, scores)
    }

    private func pickBestGarment(scores: [Float]) -> (classID: Int, score: Double)? {
        // Slightly low threshold so flat-lay product photos still register.
        var bestID: Int?
        var bestScore: Float = 0.012
        for id in Self.garmentClassIDs {
            guard id < scores.count else { continue }
            var score = scores[id]
            if id == 9, scores.count > 10 { score += scores[10] }
            if id == 10 { continue }
            if score > bestScore {
                bestScore = score
                bestID = id
            }
        }
        guard let bestID else { return nil }
        let labelID = (bestID == 9 || bestID == 10) ? 9 : bestID
        return (labelID, Double(min(0.98, max(0.35, bestScore * 5))))
    }

    private func maskImage(
        classMap: [UInt8],
        width: Int,
        height: Int,
        targetClass: Int,
        targetSize: CGSize
    ) -> UIImage? {
        var pixels = [UInt8](repeating: 0, count: width * height)
        let shoePair: Set<UInt8> = [9, 10]
        let target = UInt8(targetClass)
        if shoePair.contains(target) {
            for i in 0..<classMap.count where shoePair.contains(classMap[i]) {
                pixels[i] = 255
            }
        } else {
            for i in 0..<classMap.count where classMap[i] == target {
                pixels[i] = 255
            }
        }

        guard let small = ImageProcessing.grayImage(from: pixels, width: width, height: height),
              let smallCG = small.cgImage else { return nil }

        let outW = max(1, Int(targetSize.width.rounded()))
        let outH = max(1, Int(targetSize.height.rounded()))
        guard let scaled = ImageProcessing.redraw(smallCG, width: outW, height: outH) else { return nil }
        // Convert RGB redraw of gray back to gray UIImage via luminance approx — redraw gray properly:
        var gray = [UInt8](repeating: 0, count: outW * outH)
        guard let ctx = CGContext(
            data: &gray,
            width: outW,
            height: outH,
            bitsPerComponent: 8,
            bytesPerRow: outW,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return UIImage(cgImage: scaled, scale: 1, orientation: .up)
        }
        ctx.interpolationQuality = .high
        ctx.draw(smallCG, in: CGRect(x: 0, y: 0, width: outW, height: outH))
        return ImageProcessing.grayImage(from: gray, width: outW, height: outH)
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
        default: return (.other, labels[safe: classID] ?? "Clothing")
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
