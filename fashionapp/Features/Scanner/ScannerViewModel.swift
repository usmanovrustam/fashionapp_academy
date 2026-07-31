import Foundation
import UIKit
import SwiftUI

@MainActor
final class ScannerViewModel: ObservableObject {
    @Published var selectedImage: UIImage?
    @Published var previewImage: UIImage?
    @Published var suggestedName = ""
    @Published var editableName = ""
    @Published var scanResult: ClothingScanResult?
    @Published var isProcessing = false
    @Published var isSaving = false
    @Published var errorMessage: String?
    @Published var showCamera = false
    @Published var showLibrary = false
    @Published var didSave = false
    @Published var savedItem: WardrobeItem?

    private let scanAndSave: ScanAndSaveClothingUseCase
    private let pipeline: ClothingScanPipeline
    let plannedDate: Date?

    init(container: AppContainer, plannedDate: Date? = nil) {
        self.scanAndSave = container.scanAndSaveUseCase
        self.pipeline = container.scanPipeline
        self.plannedDate = plannedDate
    }

    func openCamera() async {
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
        editableName = ""
        scanResult = nil
        isProcessing = true
        errorMessage = nil

        do {
            guard let data = image.jpegData(compressionQuality: 0.92) else {
                throw DomainError.invalidImage
            }
            let result = try await pipeline.scan(imageData: data)
            scanResult = result
            suggestedName = result.suggestedName
            editableName = result.suggestedName
            if let transparent = result.transparentImageData {
                previewImage = UIImage(data: transparent) ?? image
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isProcessing = false
    }

    func save() async {
        guard let image = selectedImage,
              let data = image.jpegData(compressionQuality: 0.92) else {
            errorMessage = DomainError.invalidImage.localizedDescription
            return
        }

        isSaving = true
        errorMessage = nil
        do {
            let item = try await scanAndSave.execute(
                imageData: data,
                overrideName: editableName,
                plannedDate: plannedDate
            )
            savedItem = item
            didSave = true
            resetForm()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    func resetForm() {
        selectedImage = nil
        previewImage = nil
        suggestedName = ""
        editableName = ""
        scanResult = nil
    }
}
