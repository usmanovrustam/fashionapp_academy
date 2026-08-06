import Foundation
import CoreML
import UIKit

/// u2netp saliency segmenter / background remover, run through Core ML directly
/// (no Vision framework). Takes an RGB image and returns a soft foreground mask;
/// robust on flat-lay garments over busy backgrounds where semantic parsers fail.
final class U2NetClothingSegmenter: ClothingSegmenter {
    /// Loaded on first scan — not during `AppContainer` init / app launch.
    private lazy var model: MLModel? = Self.loadModel()
    private let inputSize = 320

    init() {}

    private static func loadModel() -> MLModel? {
        let config = MLModelConfiguration()
        // Prefer CPU+GPU; `.all` (ANE) has crashed some devices while compiling at first load.
        config.computeUnits = .cpuAndGPU
        let candidates: [URL?] = [
            Bundle.main.url(forResource: "u2net", withExtension: "mlmodelc"),
            Bundle.main.url(forResource: "u2net", withExtension: "mlpackage")
        ]
        for url in candidates.compactMap({ $0 }) {
            if let model = try? MLModel(contentsOf: url, configuration: config) {
                return model
            }
        }
        return nil
    }

    func segment(imageData: Data) async throws -> Data {
        guard let model else {
            // Fallback soft full-frame mask so the pipeline remains usable without the model.
            return try await Self.fullOpacityMaskPNG(from: imageData)
        }

        let image = try ImageProcessing.uiImage(from: imageData)
        let buffer = try ImageProcessing.pixelBuffer(from: image, width: inputSize, height: inputSize)
        let provider = try MLDictionaryFeatureProvider(
            dictionary: ["image": MLFeatureValue(pixelBuffer: buffer)]
        )
        let output = try await model.prediction(from: provider)

        guard let multiArray = output.featureValue(for: "mask")?.multiArrayValue
                ?? Self.firstMultiArray(in: output),
              let maskImage = Self.maskImage(from: multiArray) else {
            throw ImageProcessingError.maskFailed
        }

        return try ImageProcessing.pngData(from: maskImage)
    }

    private static func firstMultiArray(in provider: MLFeatureProvider) -> MLMultiArray? {
        for name in provider.featureNames {
            if let array = provider.featureValue(for: name)?.multiArrayValue {
                return array
            }
        }
        return nil
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
