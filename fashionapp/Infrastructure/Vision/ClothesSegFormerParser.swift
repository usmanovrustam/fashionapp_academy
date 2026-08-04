import Foundation
import UIKit
import CoreML

/// On-device clothes parser powered by `ClothesSegFormer.mlpackage`
/// (ATR 18-class SegFormer; built via `scripts/build_strong_clothes_coreml.py`
/// from multiple Hugging Face teachers — see `ClothesSegFormerLabels.json`).
///
/// Detects garment classes (hat, shoes, pants, dress, bag, …), builds a mask,
/// and returns a centered square crop ready for Firebase Storage.
///
/// Safe for background threads: uses Core Graphics + pointer I/O (no UIGraphicsImageRenderer).
final class ClothesSegFormerParser: @unchecked Sendable {
    /// Lazy so TestFlight / cold launch does not compile+load Core ML before first scan.
    static let shared: ClothesSegFormerParser = {
        ClothesSegFormerParser()
    }()

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
        /// Hard garment mask matching the square crop size (PNG grayscale, 0/255).
        var squareMaskPNG: Data
    }

    func parse(imageData: Data) async throws -> ParseResult {
        guard let model else {
            throw DomainError.scanFailed("ClothesSegFormer model is not bundled.")
        }

        let image = try ImageProcessing.uiImage(from: imageData)
        // Bake camera EXIF so logits / mask align with an upright garment.
        let upright = ImageProcessing.orientedUp(image)
        let prepared = ImageProcessing.resized(upright, maxDimension: 1600)

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

        guard let preparedCG = ImageProcessing.cgImage(from: prepared) else {
            throw DomainError.invalidImage
        }
        guard let maskFull = maskImage(
            classMap: classMap,
            width: width,
            height: height,
            targetClass: best.classID,
            targetSize: CGSize(width: preparedCG.width, height: preparedCG.height)
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
        // Prefer CPU+GPU; `.all` (ANE) has crashed some devices while compiling at first load.
        config.computeUnits = .cpuAndGPU

        let candidates: [URL?] = [
            Bundle.main.url(forResource: "ClothesSegFormer", withExtension: "mlmodelc"),
            Bundle.main.url(forResource: "ClothesSegFormer", withExtension: "mlpackage"),
            Bundle.main.url(forResource: "ClothesSegFormer", withExtension: "mlmodel")
        ]

        for url in candidates.compactMap({ $0 }) {
            do {
                return try MLModel(contentsOf: url, configuration: config)
            } catch {
                #if DEBUG
                print("⚠️ ClothesSegFormer failed to load from \(url.lastPathComponent): \(error)")
                #endif
                continue
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
            // Flat-lay hoodies / jackets are often mislabeled "Dress" by ATR SegFormer.
            // Prefer Upper-clothes when it is competitively present.
            if id == 7, scores.count > 4 {
                let upper = scores[4]
                if upper >= 0.01, upper >= score * 0.45 {
                    continue
                }
            }
            if id == 4, scores.count > 7 {
                let dress = scores[7]
                if dress > score, score >= dress * 0.45 {
                    score = dress + 0.001
                }
            }
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
        let keep = Self.maskClasses(for: targetClass)
        for i in 0..<classMap.count where keep.contains(classMap[i]) {
            pixels[i] = 255
        }
        // Open (erode→dilate) kills salt-and-pepper false positives before growing edges.
        erodeMask(&pixels, width: width, height: height, radius: 1)
        dilateMask(&pixels, width: width, height: height, radius: 1)
        keepLargestForegroundComponents(&pixels, width: width, height: height, minFractionOfLargest: 0.12)
        fillMaskHoles(&pixels, width: width, height: height)
        dilateMask(&pixels, width: width, height: height, radius: 1)

        guard let small = ImageProcessing.grayImage(from: pixels, width: width, height: height),
              let smallCG = small.cgImage else { return nil }

        let outW = max(1, Int(targetSize.width.rounded()))
        let outH = max(1, Int(targetSize.height.rounded()))
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
            return nil
        }
        // Nearest avoids soft fringe that becomes speckles after thresholding.
        ctx.interpolationQuality = .none
        ctx.draw(smallCG, in: CGRect(x: 0, y: 0, width: outW, height: outH))
        for i in 0..<gray.count {
            gray[i] = gray[i] >= 128 ? 255 : 0
        }
        keepLargestForegroundComponents(&gray, width: outW, height: outH, minFractionOfLargest: 0.12)
        fillMaskHoles(&gray, width: outW, height: outH)
        return ImageProcessing.grayImage(from: gray, width: outW, height: outH)
    }

    /// Outfit fabric classes only — arms / legs / skin stay out of the cutout.
    private static func maskClasses(for targetClass: Int) -> Set<UInt8> {
        switch targetClass {
        case 4: return [4, 8, 17] // Upper-clothes + belt/scarf (no arms)
        case 7: return [7]        // Dress fabric only
        case 5: return [5]        // Skirt
        case 6: return [6]        // Pants fabric only (no legs)
        case 9, 10: return [9, 10]
        default: return [UInt8(targetClass)]
        }
    }

    /// Keep the dominant garment blob(s); drop tiny false-positive islands.
    private func keepLargestForegroundComponents(
        _ pixels: inout [UInt8],
        width: Int,
        height: Int,
        minFractionOfLargest: Float
    ) {
        let count = width * height
        guard count == pixels.count, count > 0 else { return }

        var labels = [Int](repeating: -1, count: count)
        var sizes: [Int] = []
        var nextLabel = 0

        for start in 0..<count where pixels[start] >= 128 && labels[start] < 0 {
            var size = 0
            var queue = [start]
            labels[start] = nextLabel
            var head = 0
            while head < queue.count {
                let i = queue[head]
                head += 1
                size += 1
                let x = i % width
                let y = i / width
                let neighbors = [i - 1, i + 1, i - width, i + width]
                for n in neighbors {
                    guard n >= 0, n < count, labels[n] < 0, pixels[n] >= 128 else { continue }
                    let nx = n % width
                    let ny = n / width
                    // Reject wrap-around from left/right edges.
                    if abs(nx - x) + abs(ny - y) != 1 { continue }
                    labels[n] = nextLabel
                    queue.append(n)
                }
            }
            sizes.append(size)
            nextLabel += 1
        }

        guard let largest = sizes.max(), largest > 0 else { return }
        let minKeep = max(1, Int(Float(largest) * minFractionOfLargest))
        var keepLabels = Set<Int>()
        for (label, size) in sizes.enumerated() where size >= minKeep {
            keepLabels.insert(label)
        }
        for i in 0..<count where pixels[i] >= 128 {
            if !keepLabels.contains(labels[i]) {
                pixels[i] = 0
            }
        }
    }

    /// Flood-fill background from the border; any enclosed zeros become foreground.
    private func fillMaskHoles(_ pixels: inout [UInt8], width: Int, height: Int) {
        let count = width * height
        guard count == pixels.count, count > 0 else { return }
        var exterior = [Bool](repeating: false, count: count)
        var queue: [Int] = []
        queue.reserveCapacity(width + height)

        func enqueue(_ idx: Int) {
            guard idx >= 0, idx < count, !exterior[idx], pixels[idx] < 128 else { return }
            exterior[idx] = true
            queue.append(idx)
        }

        for x in 0..<width {
            enqueue(x)
            enqueue((height - 1) * width + x)
        }
        for y in 0..<height {
            enqueue(y * width)
            enqueue(y * width + (width - 1))
        }

        var head = 0
        while head < queue.count {
            let i = queue[head]
            head += 1
            let x = i % width
            let y = i / width
            if x > 0 { enqueue(i - 1) }
            if x + 1 < width { enqueue(i + 1) }
            if y > 0 { enqueue(i - width) }
            if y + 1 < height { enqueue(i + width) }
        }

        for i in 0..<count where pixels[i] < 128 && !exterior[i] {
            pixels[i] = 255
        }
    }

    private func dilateMask(_ pixels: inout [UInt8], width: Int, height: Int, radius: Int) {
        guard radius > 0 else { return }
        let src = pixels
        for y in 0..<height {
            for x in 0..<width {
                if src[y * width + x] >= 128 { continue }
                var hit = false
                let y0 = max(0, y - radius), y1 = min(height - 1, y + radius)
                let x0 = max(0, x - radius), x1 = min(width - 1, x + radius)
                outer: for yy in y0...y1 {
                    for xx in x0...x1 where src[yy * width + xx] >= 128 {
                        hit = true
                        break outer
                    }
                }
                if hit { pixels[y * width + x] = 255 }
            }
        }
    }

    private func erodeMask(_ pixels: inout [UInt8], width: Int, height: Int, radius: Int) {
        guard radius > 0 else { return }
        let src = pixels
        for y in 0..<height {
            for x in 0..<width {
                if src[y * width + x] < 128 { continue }
                var keep = true
                let y0 = max(0, y - radius), y1 = min(height - 1, y + radius)
                let x0 = max(0, x - radius), x1 = min(width - 1, x + radius)
                outer: for yy in y0...y1 {
                    for xx in x0...x1 where src[yy * width + xx] < 128 {
                        keep = false
                        break outer
                    }
                }
                if !keep { pixels[y * width + x] = 0 }
            }
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
