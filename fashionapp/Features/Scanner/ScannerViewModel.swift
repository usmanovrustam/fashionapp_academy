import Foundation
import UIKit
import SwiftUI

@MainActor
final class ScannerViewModel: ObservableObject {
    @Published var selectedImage: UIImage?
    @Published var previewImage: UIImage?
    @Published var scanResult: ClothingScanResult?
    @Published var isProcessing = false
    @Published var isSaving = false
    @Published var errorMessage: String?
    @Published var showNoOutfitAlert = false
    @Published var showCamera = false
    @Published var showLibrary = false
    @Published var didSave = false
    @Published var savedItem: WardrobeItem?

    // Reviewed draft — prefilled from scan; user must confirm before save.
    @Published var draftName = ""
    @Published var draftCategory: ClothingCategory = .top
    @Published var draftType = ""
    @Published var draftMaterial: Material = .cotton
    @Published var draftColor = ""
    @Published var draftSeason: Season = .allSeason
    @Published var draftFormality: Double = 0.35

    private let scanAndSave: ScanAndSaveClothingUseCase
    private let pipeline: ClothingScanPipeline
    private let analytics: AnalyticsTracking
    let plannedDate: Date?

    var canSave: Bool {
        selectedImage != nil && scanResult != nil && !isProcessing && !isSaving
    }

    init(container: AppContainer, plannedDate: Date? = nil) {
        self.scanAndSave = container.scanAndSaveUseCase
        self.pipeline = container.scanPipeline
        self.analytics = container.analytics
        self.plannedDate = plannedDate
    }

    func openCamera() async {
        analytics.track(.scanStarted, parameters: ["source": "camera"])
        let auth = await CameraAuthorization.ensureAuthorized()
        switch auth {
        case .success:
            showCamera = true
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    func handlePickedImage(_ image: UIImage) async {
        selectedImage = image
        previewImage = image
        scanResult = nil
        clearDraft()
        isProcessing = true
        errorMessage = nil
        showNoOutfitAlert = false
        analytics.track(.scanStarted, parameters: ["source": "image"])

        do {
            // Normalize on a cooperative yield so shimmer can paint first.
            await Task.yield()
            let upright = ImageProcessing.orientedUp(image)
            let prepared = ImageProcessing.resized(upright, maxDimension: 1600)
            guard let data = try? ImageProcessing.jpegData(from: prepared, quality: 0.9) else {
                throw DomainError.invalidImage
            }

            // Heavy Core ML + CG work runs off the main actor (thread-safe image path).
            let result = try await BackgroundScanJob(pipeline: pipeline, imageData: data).runDetached()
            scanResult = result
            applyDraft(from: result)
            if let transparent = result.transparentImageData,
               let cutout = UIImage(data: transparent) {
                previewImage = cutout
                selectedImage = cutout
            } else if let square = UIImage(data: result.originalImageData) {
                previewImage = square
                selectedImage = square
            }
            analytics.track(.scanCompleted, parameters: [
                "category": result.detectedCategory.rawValue,
                "confidence": String(format: "%.2f", result.confidence)
            ])
        } catch DomainError.noClothingDetected {
            scanResult = nil
            clearDraft()
            showNoOutfitAlert = true
            analytics.track(.scanCompleted, parameters: ["outcome": "no_clothing"])
        } catch {
            errorMessage = error.localizedDescription
        }

        isProcessing = false
    }

    func save() async {
        guard let scan = scanResult else {
            errorMessage = DomainError.invalidImage.localizedDescription
            return
        }

        isSaving = true
        errorMessage = nil
        do {
            let draft = ReviewedClothingDraft(
                name: draftName,
                category: draftCategory,
                subcategory: draftType,
                material: draftMaterial,
                dominantColor: draftColor,
                season: draftSeason,
                formalityScore: draftFormality
            )
            let item = try await scanAndSave.execute(
                scan: scan,
                draft: draft,
                plannedDate: plannedDate
            )
            savedItem = item
            didSave = true
            analytics.track(.itemSaved, parameters: [
                "category": item.category.rawValue,
                "item_id": item.id.uuidString,
                "storage_path": item.originalImagePath
            ])
            resetForm()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    func clearFailedScan() {
        selectedImage = nil
        previewImage = nil
        scanResult = nil
        clearDraft()
        showNoOutfitAlert = false
    }

    func resetForm() {
        selectedImage = nil
        previewImage = nil
        scanResult = nil
        clearDraft()
        showNoOutfitAlert = false
    }

    private func applyDraft(from result: ClothingScanResult) {
        draftName = result.suggestedName
        draftCategory = result.detectedCategory
        draftType = result.subcategory ?? ""
        draftMaterial = result.material
        draftColor = result.dominantColor ?? ""
        draftSeason = result.seasons.first ?? .allSeason
        draftFormality = result.formalityScore
    }

    private func clearDraft() {
        draftName = ""
        draftCategory = .top
        draftType = ""
        draftMaterial = .cotton
        draftColor = ""
        draftSeason = .allSeason
        draftFormality = 0.35
    }
}

/// Runs the clothing scan off the main actor without capturing non-Sendable pipeline unsafely across isolation.
private final class BackgroundScanJob: @unchecked Sendable {
    private let pipeline: ClothingScanPipeline
    private let imageData: Data

    init(pipeline: ClothingScanPipeline, imageData: Data) {
        self.pipeline = pipeline
        self.imageData = imageData
    }

    func runDetached() async throws -> ClothingScanResult {
        try await Task.detached(priority: .userInitiated) { [pipeline, imageData] in
            try await pipeline.scan(imageData: imageData)
        }.value
    }
}
