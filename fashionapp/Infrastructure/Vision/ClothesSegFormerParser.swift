import Foundation
import UIKit
import CoreML

/// On-device clothes parser powered by Hugging Face `mattmdjaga/segformer_b2_clothes`
/// exported as `ClothesSegFormer.mlpackage`.
///
/// Detects garment classes (hat, shoes, pants, dress, bag, …), builds a mask,
/// and returns a centered square crop ready for Firebase Storage.
final class ClothesSegFormerParser {
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
    }

    struct ParseResult {
        var category: ClothingCategory
        var subcategory: String
        var labelName: String
        var confidence: Double
        /// Centered square crop (JPEG bytes) — primary asset for Storage.
        var squareCropJPEG: Data
        /// Soft garment mask matching the square crop size (PNG grayscale).
        var squareMaskPNG: Data
        var squareImage: UIImage
    }

    func parse(imageData: Data) async throws -> ParseResult {
        guard let model else {
            throw DomainError.scanFailed("ClothesSegFormer model is not bundled.")
        }

        let image = try ImageProcessing.uiImage(from: imageData)
        let squareReady = ImageProcessing.resized(image, maxDimension: 2048)

        let pixelValues = try makePixelValues(from: squareReady)
        let input = try MLDictionaryFeatureProvider(dictionary: [
            "pixel_values": MLFeatureValue(multiArray: pixelValues)
        ])

        let output = try model.prediction(from: input)
        let logits = output.featureValue(for: "logits")?.multiArrayValue
            ?? output.featureValue(for: "var_1196")?.multiArrayValue
        guard let logits else {
            throw DomainError.scanFailed("ClothesSegFormer produced no logits.")
        }

        let (classMap, scores) = argmaxMap(from: logits)
        guard let best = pickBestGarment(scores: scores) else {
            throw DomainError.noClothingDetected
        }

        let maskFull = maskImage(classMap: classMap, targetClass: best.classID, targetSize: squareReady.size)
        let square = try ImageProcessing.centeredSquareCrop(image: squareReady, mask: maskFull, padding: 0.12)
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
            squareMaskPNG: maskPNG,
            squareImage: square
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

    // MARK: - Preprocess

    private func makePixelValues(from image: UIImage) throws -> MLMultiArray {
        let size = CGSize(width: inputSize, height: inputSize)
        let renderer = UIGraphicsImageRenderer(size: size)
        let scaled = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let cgImage = scaled.cgImage else { throw DomainError.invalidImage }

        let width = inputSize
        let height = inputSize
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var rgba = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let ctx = CGContext(
            data: &rgba,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw DomainError.invalidImage
        }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let array = try MLMultiArray(
            shape: [1, 3, NSNumber(value: height), NSNumber(value: width)],
            dataType: .float32
        )
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let r = (Float(rgba[i]) / 255.0 - mean[0]) / std[0]
                let g = (Float(rgba[i + 1]) / 255.0 - mean[1]) / std[1]
                let b = (Float(rgba[i + 2]) / 255.0 - mean[2]) / std[2]
                array[[0, 0, y, x] as [NSNumber]] = NSNumber(value: r)
                array[[0, 1, y, x] as [NSNumber]] = NSNumber(value: g)
                array[[0, 2, y, x] as [NSNumber]] = NSNumber(value: b)
            }
        }
        return array
    }

    // MARK: - Postprocess

    private func argmaxMap(from logits: MLMultiArray) -> ([[UInt8]], [Float]) {
        // Expected shape [1, 18, H, W]
        let shape = logits.shape.map(\.intValue)
        let classes = shape.count >= 4 ? shape[1] : 18
        let height = shape.count >= 4 ? shape[2] : shape[shape.count - 2]
        let width = shape.count >= 4 ? shape[3] : shape[shape.count - 1]

        var map = Array(repeating: Array(repeating: UInt8(0), count: width), count: height)
        var pixelCounts = Array(repeating: 0, count: classes)
        var scoreSums = Array(repeating: Float(0), count: classes)

        for y in 0..<height {
            for x in 0..<width {
                var bestClass = 0
                var bestValue = -Float.greatestFiniteMagnitude
                for c in 0..<classes {
                    let value = floatValue(logits, c: c, y: y, x: x, classes: classes, height: height, width: width)
                    if value > bestValue {
                        bestValue = value
                        bestClass = c
                    }
                }
                map[y][x] = UInt8(bestClass)
                pixelCounts[bestClass] += 1
                // Softmax-ish confidence proxy via max logit (normalized later)
                scoreSums[bestClass] += bestValue
            }
        }

        let totalPixels = Float(max(width * height, 1))
        var scores = Array(repeating: Float(0), count: classes)
        for c in 0..<classes {
            let coverage = Float(pixelCounts[c]) / totalPixels
            scores[c] = coverage
        }
        return (map, scores)
    }

    private func floatValue(
        _ logits: MLMultiArray,
        c: Int,
        y: Int,
        x: Int,
        classes: Int,
        height: Int,
        width: Int
    ) -> Float {
        let index: [NSNumber] = [0, c as NSNumber, y as NSNumber, x as NSNumber]
        let number = logits[index]
        // FLOAT16 outputs come through as NSNumber already.
        return number.floatValue
    }

    private func pickBestGarment(scores: [Float]) -> (classID: Int, score: Double)? {
        var bestID: Int?
        var bestScore: Float = 0.02 // minimum coverage ~2% of frame
        for id in Self.garmentClassIDs {
            guard id < scores.count else { continue }
            // Merge left/right shoes into a shared score for selection.
            var score = scores[id]
            if id == 9, scores.count > 10 { score += scores[10] }
            if id == 10 { continue } // handled with left shoe
            if score > bestScore {
                bestScore = score
                bestID = id
            }
        }
        guard let bestID else { return nil }
        // Map merged shoe score back to Left-shoe id for labeling if either shoe won.
        let labelID = (bestID == 9 || bestID == 10) ? 9 : bestID
        return (labelID, Double(min(0.98, max(0.35, bestScore * 4))))
    }

    private func maskImage(classMap: [[UInt8]], targetClass: Int, targetSize: CGSize) -> UIImage {
        let height = classMap.count
        let width = classMap.first?.count ?? 0
        var pixels = [UInt8](repeating: 0, count: width * height)

        let shoePair: Set<Int> = [9, 10]
        for y in 0..<height {
            for x in 0..<width {
                let cls = Int(classMap[y][x])
                let match: Bool
                if shoePair.contains(targetClass) {
                    match = shoePair.contains(cls)
                } else {
                    match = cls == targetClass
                }
                pixels[y * width + x] = match ? 255 : 0
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceGray()
        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData),
              let cgMask = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 8,
                bytesPerRow: width,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            return UIImage()
        }

        let mask = UIImage(cgImage: cgMask)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            mask.draw(in: CGRect(origin: .zero, size: targetSize))
        }
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
