import Foundation
import FirebaseAuth
import FirebaseFunctions
import UIKit

/// Orchestrates: upload garment+human → Cloud Function (Replicate IDM-VTON) → download shot.
actor FirebaseFashionShotService: FashionShotServing {
    private let imageStorage: ImageStorage
    private let functions: Functions

    init(
        imageStorage: ImageStorage,
        functions: Functions = Functions.functions(region: "us-central1")
    ) {
        self.imageStorage = imageStorage
        self.functions = functions
    }

    func generateFashionShot(
        garmentImageData: Data,
        humanImageData: Data,
        category: ClothingCategory,
        garmentDescription: String
    ) async throws -> FashionShotResult {
        guard Auth.auth().currentUser != nil else {
            throw AuthError.notSignedIn
        }

        let stamp = UUID().uuidString
        let garmentName = "tmp-fashion/\(stamp)-garment.png"
        let humanName = "tmp-fashion/\(stamp)-human.jpg"

        let garmentPath: String
        let humanPath: String
        do {
            garmentPath = try await imageStorage.saveImageData(garmentImageData, preferredName: garmentName)
            humanPath = try await imageStorage.saveImageData(humanImageData, preferredName: humanName)
        } catch {
            throw DomainError.fashionShotFailed(error.localizedDescription)
        }

        let callable = functions.httpsCallable("generateFashionShot")
        let payload: [String: Any] = [
            "garmentPath": garmentPath,
            "humanPath": humanPath,
            "category": category.rawValue,
            "garmentDescription": garmentDescription
        ]

        let result: HTTPSCallableResult
        do {
            result = try await callable.call(payload)
        } catch {
            throw DomainError.fashionShotFailed(
                NSLocalizedString(
                    "Fashion shot failed. Check that Cloud Functions are deployed and REPLICATE_API_TOKEN is set.",
                    comment: "Fashion shot callable error"
                ) + " (\(error.localizedDescription))"
            )
        }

        guard let data = result.data as? [String: Any],
              let path = data["path"] as? String else {
            throw DomainError.fashionShotFailed("Cloud Function returned an unexpected payload.")
        }

        let imageData: Data
        if let urlString = data["downloadURL"] as? String, let url = URL(string: urlString) {
            do {
                let (bytes, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), !bytes.isEmpty else {
                    throw DomainError.fashionShotFailed("Could not download fashion shot.")
                }
                imageData = bytes
            } catch let error as DomainError {
                throw error
            } catch {
                // Fall back to authenticated Storage read.
                imageData = try await imageStorage.loadImageData(at: path)
            }
        } else {
            imageData = try await imageStorage.loadImageData(at: path)
        }

        // Best-effort cleanup of temp uploads.
        try? await imageStorage.deleteImage(at: garmentPath)
        try? await imageStorage.deleteImage(at: humanPath)

        return FashionShotResult(
            storagePath: path,
            imageData: imageData,
            replicateId: data["replicateId"] as? String
        )
    }
}
