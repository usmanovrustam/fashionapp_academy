import Foundation
import CoreML
import UIKit

/// On-device multi-task fashion model (CoreML, no Vision framework).
///
/// Backed by `FashionMultiTask.mlpackage` (trained by `/ml`), this single model
/// predicts clothing category, gender, season, usage and base colour, and emits
/// a 256-d embedding for wardrobe similarity search. All inference runs directly
/// through `MLModel` on a `CVPixelBuffer` — deliberately not using Vision.
final class CoreMLFashionModel {
    struct Labels: Decodable {
        var category: [String]
        var gender: [String]
        var season: [String]
        var usage: [String]
        var color: [String]
    }

    struct Prediction {
        var category: ClothingCategory
        var categoryConfidence: Double
        var gender: String
        var season: Season?
        var usage: String
        var color: String
        var embedding: [Float]
    }

    static let inputSize = 128
    private let model: MLModel
    private let labels: Labels

    /// Returns `nil` when the compiled model isn't bundled (e.g. not yet added
    /// to the Xcode target), so callers can fall back to heuristics.
    init?() {
        guard let url = Bundle.main.url(forResource: "FashionMultiTask", withExtension: "mlmodelc") else {
            return nil
        }
        let config = MLModelConfiguration()
        config.computeUnits = .all
        guard let model = try? MLModel(contentsOf: url, configuration: config) else { return nil }
        self.model = model
        self.labels = Self.loadLabels(from: model)
    }

    func predict(imageData: Data) throws -> Prediction {
        let outputs = try runModel(imageData: imageData)

        let (catIdx, catConf) = Self.argmax(outputs["category"])
        let category = ClothingCategory(rawValue: labels.category[safe: catIdx] ?? "other") ?? .other
        let gender = labels.gender[safe: Self.argmax(outputs["gender"]).0] ?? "Unisex"
        let seasonRaw = labels.season[safe: Self.argmax(outputs["season"]).0]
        let season = seasonRaw.flatMap(Season.init(rawValue:))
        let usage = labels.usage[safe: Self.argmax(outputs["usage"]).0] ?? "Casual"
        let color = labels.color[safe: Self.argmax(outputs["color"]).0] ?? "Neutral"

        return Prediction(
            category: category,
            categoryConfidence: catConf,
            gender: gender,
            season: season,
            usage: usage,
            color: color,
            embedding: Self.vector(outputs["embedding"])
        )
    }

    func embed(imageData: Data) throws -> [Float] {
        Self.vector(try runModel(imageData: imageData)["embedding"])
    }

    // MARK: - Inference

    private func runModel(imageData: Data) throws -> [String: MLMultiArray] {
        let image = try ImageProcessing.uiImage(from: imageData)
        let buffer = try ImageProcessing.pixelBuffer(
            from: image, width: Self.inputSize, height: Self.inputSize
        )
        let provider = try MLDictionaryFeatureProvider(
            dictionary: ["image": MLFeatureValue(pixelBuffer: buffer)]
        )
        let result = try model.prediction(from: provider)
        var outputs: [String: MLMultiArray] = [:]
        for name in result.featureNames {
            if let array = result.featureValue(for: name)?.multiArrayValue {
                outputs[name] = array
            }
        }
        return outputs
    }

    // MARK: - Helpers

    private static func loadLabels(from model: MLModel) -> Labels {
        let creator = model.modelDescription.metadata[.creatorDefinedKey] as? [String: String]
        if let json = creator?["labels_json"], let data = json.data(using: .utf8),
           let labels = try? JSONDecoder().decode(Labels.self, from: data) {
            return labels
        }
        if let url = Bundle.main.url(forResource: "FashionMultiTaskLabels", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let labels = try? JSONDecoder().decode(Labels.self, from: data) {
            return labels
        }
        return Labels(category: [], gender: [], season: [], usage: [], color: [])
    }

    private static func argmax(_ array: MLMultiArray?) -> (Int, Double) {
        guard let array, array.count > 0 else { return (0, 0) }
        var bestIndex = 0
        var bestValue = -Double.greatestFiniteMagnitude
        for i in 0..<array.count {
            let value = array[i].doubleValue
            if value > bestValue {
                bestValue = value
                bestIndex = i
            }
        }
        return (bestIndex, bestValue)
    }

    private static func vector(_ array: MLMultiArray?) -> [Float] {
        guard let array else { return [] }
        return (0..<array.count).map { array[$0].floatValue }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
