import Foundation
import CoreML
import Vision
import UIKit

/// U²-Net based segmenter / background remover.
/// Designed behind protocols so the CoreML model can be swapped later.
final class U2NetClothingSegmenter: ClothingSegmenter {
    /// Loaded on first scan — not during `AppContainer` init / app launch.
    private lazy var model: VNCoreMLModel? = Self.loadModel()
    private let inputSize = 320

    init() {}

    private static func loadModel() -> VNCoreMLModel? {
        guard let mlModel = try? u2net(configuration: MLModelConfiguration()).model else {
            return nil
        }
        return try? VNCoreMLModel(for: mlModel)
    }

    func segment(imageData: Data) async throws -> Data {
        guard let model else {
            // Fallback soft full-frame mask so the pipeline remains usable without the model.
            return try await Self.fullOpacityMaskPNG(from: imageData)
        }

        let image = try ImageProcessing.uiImage(from: imageData)
        let resized = ImageProcessing.resized(image, maxDimension: CGFloat(inputSize))
        guard let cgImage = resized.cgImage else { throw ImageProcessingError.invalidImage }

        // Synchronous Vision perform — never wrap in a checked continuation (double-resume crash).
        let request = VNCoreMLRequest(model: model)
        request.imageCropAndScaleOption = .scaleFill
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw ImageProcessingError.maskFailed
        }

        guard let results = request.results as? [VNCoreMLFeatureValueObservation],
              let multiArray = Self.preferredMaskArray(from: results),
              let maskImage = Self.maskImage(from: multiArray) else {
            throw ImageProcessingError.maskFailed
        }

        return try ImageProcessing.pngData(from: maskImage)
    }

    /// Prefer the primary U²-Net saliency output when multiple tensors are present.
    private static func preferredMaskArray(from results: [VNCoreMLFeatureValueObservation]) -> MLMultiArray? {
        if let named = results.first(where: {
            let name = $0.featureName.lowercased()
            return name == "output_0" || name.contains("output_0") || name.contains("saliency") || name.hasSuffix("mask")
        })?.featureValue.multiArrayValue {
            return named
        }
        return results.last?.featureValue.multiArrayValue ?? results.first?.featureValue.multiArrayValue
    }

    private static func fullOpacityMaskPNG(from imageData: Data) async throws -> Data {
        let image = try ImageProcessing.uiImage(from: imageData)
        guard let source = ImageProcessing.cgImage(from: image) else {
            throw ImageProcessingError.invalidImage
        }
        let width = source.width
        let height = source.height
        let pixels = [UInt8](repeating: 255, count: width * height)
        guard let mask = ImageProcessing.grayImage(from: pixels, width: width, height: height) else {
            throw ImageProcessingError.maskFailed
        }
        return try ImageProcessing.pngData(from: mask)
    }

    private static func maskImage(from multiArray: MLMultiArray) -> UIImage? {
        // U²-Net outputs are typically [1, H, W] or [H, W].
        let shape = multiArray.shape.map { $0.intValue }
        let height: Int
        let width: Int
        let planeOffset: Int

        if shape.count == 3 {
            height = shape[1]
            width = shape[2]
            planeOffset = 0
        } else if shape.count == 4 {
            height = shape[2]
            width = shape[3]
            planeOffset = 0
        } else if shape.count == 2 {
            height = shape[0]
            width = shape[1]
            planeOffset = 0
        } else {
            return nil
        }

        guard height > 0, width > 0 else { return nil }

        var pixels = [UInt8](repeating: 0, count: height * width)
        var minValue = Double.greatestFiniteMagnitude
        var maxValue = -Double.greatestFiniteMagnitude

        for y in 0..<height {
            for x in 0..<width {
                let index: [NSNumber]
                if shape.count == 3 {
                    index = [0, y as NSNumber, x as NSNumber]
                } else if shape.count == 4 {
                    index = [0, 0, y as NSNumber, x as NSNumber]
                } else {
                    index = [y as NSNumber, x as NSNumber]
                }
                let value = multiArray[index].doubleValue
                minValue = min(minValue, value)
                maxValue = max(maxValue, value)
                _ = planeOffset
            }
        }

        let range = max(maxValue - minValue, 0.0001)
        for y in 0..<height {
            for x in 0..<width {
                let index: [NSNumber]
                if shape.count == 3 {
                    index = [0, y as NSNumber, x as NSNumber]
                } else if shape.count == 4 {
                    index = [0, 0, y as NSNumber, x as NSNumber]
                } else {
                    index = [y as NSNumber, x as NSNumber]
                }
                let normalized = (multiArray[index].doubleValue - minValue) / range
                // Harden saliency so fallback cutouts are solid garments, not speckles.
                pixels[y * width + x] = normalized >= 0.45 ? 255 : 0
            }
        }

        Self.erodeMask(&pixels, width: width, height: height, radius: 1)
        Self.dilateMask(&pixels, width: width, height: height, radius: 1)
        Self.keepLargestForegroundComponents(&pixels, width: width, height: height, minFractionOfLargest: 0.12)
        Self.fillMaskHoles(&pixels, width: width, height: height)
        Self.dilateMask(&pixels, width: width, height: height, radius: 1)

        return ImageProcessing.grayImage(from: pixels, width: width, height: height)
    }

    private static func keepLargestForegroundComponents(
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
                for n in [i - 1, i + 1, i - width, i + width] {
                    guard n >= 0, n < count, labels[n] < 0, pixels[n] >= 128 else { continue }
                    let nx = n % width
                    let ny = n / width
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
        for i in 0..<count where pixels[i] >= 128 && !keepLabels.contains(labels[i]) {
            pixels[i] = 0
        }
    }

    private static func fillMaskHoles(_ pixels: inout [UInt8], width: Int, height: Int) {
        let count = width * height
        guard count == pixels.count, count > 0 else { return }
        var exterior = [Bool](repeating: false, count: count)
        var queue: [Int] = []
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

    private static func dilateMask(_ pixels: inout [UInt8], width: Int, height: Int, radius: Int) {
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

    private static func erodeMask(_ pixels: inout [UInt8], width: Int, height: Int, radius: Int) {
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
}

final class MaskBackgroundRemover: BackgroundRemover {
    func removeBackground(imageData: Data, maskData: Data) async throws -> Data {
        let image = try ImageProcessing.uiImage(from: imageData)
        let mask = try ImageProcessing.uiImage(from: maskData)
        // applyMask resizes the mask via Core Graphics — no UIGraphicsImageRenderer.
        let cutout = try ImageProcessing.applyMask(image: image, mask: mask)
        return try ImageProcessing.pngData(from: cutout)
    }
}
