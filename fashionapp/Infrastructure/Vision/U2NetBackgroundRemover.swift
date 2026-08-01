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
                pixels[y * width + x] = UInt8(max(0, min(255, normalized * 255)))
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cgImage = CGImage(
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
            return nil
        }
        return UIImage(cgImage: cgImage)
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
