import Foundation
import FirebaseAuth

/// Orchestrates: upload garment+human → Cloud Function (Replicate IDM-VTON) → download shot.
/// Uses the HTTPS callable protocol via URLSession so we don't need the FirebaseFunctions SPM product.
actor FirebaseFashionShotService: FashionShotServing {
    private let imageStorage: ImageStorage
    private let region: String

    init(imageStorage: ImageStorage, region: String = "us-central1") {
        self.imageStorage = imageStorage
        self.region = region
    }

    func generateFashionShot(
        garmentImageData: Data,
        humanImageData: Data,
        category: ClothingCategory,
        garmentDescription: String
    ) async throws -> FashionShotResult {
        guard let user = Auth.auth().currentUser else {
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

        let idToken: String
        do {
            idToken = try await user.getIDToken()
        } catch {
            throw DomainError.fashionShotFailed("Could not refresh auth token.")
        }

        let projectID = FirebaseConfig.projectID ?? "sylyo-fashion"
        guard let url = URL(string: "https://\(region)-\(projectID).cloudfunctions.net/generateFashionShot") else {
            throw DomainError.fashionShotFailed("Invalid Cloud Function URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 300

        let payload: [String: Any] = [
            "data": [
                "garmentPath": garmentPath,
                "humanPath": humanPath,
                "category": category.rawValue,
                "garmentDescription": garmentDescription
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw DomainError.fashionShotFailed(
                NSLocalizedString(
                    "Fashion shot failed. Deploy functions and set REPLICATE_API_TOKEN (see FASHION_SHOT_SETUP.md).",
                    comment: "Fashion shot network error"
                ) + " (\(error.localizedDescription))"
            )
        }

        guard let http = response as? HTTPURLResponse else {
            throw DomainError.fashionShotFailed("Invalid Cloud Function response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw DomainError.fashionShotFailed(
                "Cloud Function HTTP \(http.statusCode): \(body.prefix(280))"
            )
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let result = json["result"] as? [String: Any],
            let path = result["path"] as? String
        else {
            throw DomainError.fashionShotFailed("Cloud Function returned an unexpected payload.")
        }

        let imageData: Data
        if let urlString = result["downloadURL"] as? String, let shotURL = URL(string: urlString) {
            do {
                let (bytes, shotResponse) = try await URLSession.shared.data(from: shotURL)
                guard let shotHTTP = shotResponse as? HTTPURLResponse,
                      (200..<300).contains(shotHTTP.statusCode),
                      !bytes.isEmpty else {
                    throw DomainError.fashionShotFailed("Could not download fashion shot.")
                }
                imageData = bytes
            } catch let error as DomainError {
                throw error
            } catch {
                imageData = try await imageStorage.loadImageData(at: path)
            }
        } else {
            imageData = try await imageStorage.loadImageData(at: path)
        }

        try? await imageStorage.deleteImage(at: garmentPath)
        try? await imageStorage.deleteImage(at: humanPath)

        return FashionShotResult(
            storagePath: path,
            imageData: imageData,
            replicateId: result["replicateId"] as? String
        )
    }
}
