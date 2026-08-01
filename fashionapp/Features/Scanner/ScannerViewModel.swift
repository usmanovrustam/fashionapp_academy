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
            // Normalize orientation + bound size before Vision/CoreML.
            let prepared = ImageProcessing.resized(image, maxDimension: 2048)
            guard let data = prepared.jpegData(compressionQuality: 0.9) else {
                throw DomainError.invalidImage
            }

            // Yield so the shimmer can paint, then run Vision/CoreML work.
            await Task.yield()
            let result = try await self.runScan(imageData: data)
            scanResult = result
            applyDraft(from: result)
            // Preview the centered square crop (cutout when available).
            if let transparent = result.transparentImageData,
               let cutout = UIImage(data: transparent) {
                previewImage = cutout
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

    /// Runs the scan pipeline on a background queue so capture doesn’t block/crash the UI thread.
    private func runScan(imageData: Data) async throws -> ClothingScanResult {
        let pipeline = self.pipeline
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                Task {
                    do {
                        let result = try await pipeline.scan(imageData: imageData)
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
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
