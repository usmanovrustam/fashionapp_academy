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

    /// Live ML stage while `isProcessing` — driven by the real pipeline, not a timer.
    @Published var pipelineStage: ScanPipelineStage?
    @Published var pipelineFraction: Double = 0
    @Published var pipelineDetail: String?
    @Published var stagePreview: UIImage?

    // Reviewed draft — prefilled from scan; user must confirm before save.
    @Published var draftName = ""
    @Published var draftCategory: ClothingCategory = .top
    @Published var draftType = ""
    @Published var draftMaterial: Material = .cotton
    @Published var draftColor = ""
    @Published var draftSeason: Season = .allSeason
    @Published var draftFormality: Double = 0.35
    @Published var userGender: UserGender = .woman

    private let scanAndSave: ScanAndSaveClothingUseCase
    private let pipeline: ClothingScanPipeline
    private let profileRepository: UserProfileRepository
    private let analytics: AnalyticsTracking
    let plannedDate: Date?

    var selectableCategories: [ClothingCategory] {
        userGender.selectableClothingCategories
    }

    var canSave: Bool {
        selectedImage != nil && scanResult != nil && !isProcessing && !isSaving
    }

    init(container: AppContainer, plannedDate: Date? = nil) {
        self.scanAndSave = container.scanAndSaveUseCase
        self.pipeline = container.scanPipeline
        self.profileRepository = container.profileRepository
        self.analytics = container.analytics
        self.plannedDate = plannedDate
    }

    func loadProfileGender() async {
        if let gender = try? await profileRepository.load().gender {
            userGender = gender
            if !selectableCategories.contains(draftCategory) {
                draftCategory = selectableCategories.first ?? .top
            }
        }
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
        resetPipelineUI()
        isProcessing = true
        errorMessage = nil
        showNoOutfitAlert = false
        analytics.track(.scanStarted, parameters: ["source": "image"])

        do {
            // Normalize on a cooperative yield so the stage UI can paint first.
            await Task.yield()
            let upright = ImageProcessing.orientedUp(image)
            let prepared = ImageProcessing.resized(upright, maxDimension: 1600)
            guard let data = try? ImageProcessing.jpegData(from: prepared, quality: 0.9) else {
                throw DomainError.invalidImage
            }

            pipelineStage = .detectClothing
            pipelineFraction = 0.05
            stagePreview = prepared

            // Heavy Core ML + CG work runs off the main actor; progress hops back.
            let result = try await BackgroundScanJob(pipeline: pipeline, imageData: data).runDetached {
                [weak self] progress in
                Task { @MainActor in
                    self?.applyPipelineProgress(progress)
                }
            }
            scanResult = result
            applyDraft(from: result)
            if let transparent = result.transparentImageData,
               let cutout = UIImage(data: transparent) {
                previewImage = cutout
                selectedImage = cutout
                stagePreview = cutout
            } else if let square = UIImage(data: result.originalImageData) {
                previewImage = square
                selectedImage = square
                stagePreview = square
            }
            pipelineFraction = 1
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
        // Keep last stage preview briefly; clear stage chrome after completion.
        pipelineStage = nil
        pipelineDetail = nil
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
        resetPipelineUI()
        showNoOutfitAlert = false
    }

    func resetForm() {
        selectedImage = nil
        previewImage = nil
        scanResult = nil
        clearDraft()
        resetPipelineUI()
        showNoOutfitAlert = false
    }

    private func applyPipelineProgress(_ progress: ScanPipelineProgress) {
        pipelineStage = progress.stage
        pipelineFraction = max(pipelineFraction, min(1, progress.fraction))
        pipelineDetail = progress.detail
        if let data = progress.previewImageData, let image = UIImage(data: data) {
            stagePreview = image
            // Live-swap the main preview once we have a real cutout / square crop.
            switch progress.stage {
            case .removeBackground, .generateTransparentPNG, .extractMetadata:
                previewImage = image
            default:
                break
            }
        }
    }

    private func resetPipelineUI() {
        pipelineStage = nil
        pipelineFraction = 0
        pipelineDetail = nil
        stagePreview = nil
    }

    private func applyDraft(from result: ClothingScanResult) {
        draftName = result.suggestedName
        if selectableCategories.contains(result.detectedCategory) {
            draftCategory = result.detectedCategory
        } else if result.detectedCategory == .dress, userGender == .man {
            // Dress isn't offered for men — map to a separates category.
            draftCategory = .top
        } else {
            draftCategory = selectableCategories.first ?? .top
        }
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

    func runDetached(
        onProgress: @escaping @Sendable (ScanPipelineProgress) -> Void
    ) async throws -> ClothingScanResult {
        try await Task.detached(priority: .userInitiated) { [pipeline, imageData] in
            try await pipeline.scan(imageData: imageData, onProgress: onProgress)
        }.value
    }
}
