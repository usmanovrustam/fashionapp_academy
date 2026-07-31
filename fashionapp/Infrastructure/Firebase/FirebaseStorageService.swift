import Foundation
import FirebaseAuth
import FirebaseStorage

/// Uploads wardrobe images to Firebase Storage under `users/{uid}/...`.
actor FirebaseImageStorage: ImageStorage {
    private let storage: Storage
    private let localFallback: FileImageStorage

    init(storage: Storage = Storage.storage(), localFallback: FileImageStorage = FileImageStorage()) {
        self.storage = storage
        self.localFallback = localFallback
    }

    func saveImageData(_ data: Data, preferredName: String) async throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw AuthError.notSignedIn
        }

        let safeName = preferredName.replacingOccurrences(of: "/", with: "-")
        let path = "users/\(uid)/images/\(safeName)"
        let reference = storage.reference(withPath: path)
        let metadata = StorageMetadata()
        metadata.contentType = safeName.lowercased().hasSuffix(".png") ? "image/png" : "image/jpeg"

        do {
            _ = try await reference.putDataAsync(data, metadata: metadata)
            // Also keep a local cache for fast UI loads.
            _ = try await localFallback.saveImageData(data, preferredName: safeName)
            return path
        } catch {
            throw DomainError.storageFailed(error.localizedDescription)
        }
    }

    func loadImageData(at path: String) async throws -> Data {
        // Prefer local cache when the path is a plain filename from older local saves.
        if !path.contains("/") {
            return try await localFallback.loadImageData(at: path)
        }

        let localName = path.split(separator: "/").last.map(String.init) ?? path
        if let cached = try? await localFallback.loadImageData(at: localName), !cached.isEmpty {
            return cached
        }

        do {
            let data = try await storage.reference(withPath: path).data(maxSize: 15 * 1024 * 1024)
            _ = try? await localFallback.saveImageData(data, preferredName: localName)
            return data
        } catch {
            throw DomainError.storageFailed(error.localizedDescription)
        }
    }

    func deleteImage(at path: String) async throws {
        if !path.contains("/") {
            try await localFallback.deleteImage(at: path)
            return
        }
        do {
            try await storage.reference(withPath: path).delete()
        } catch {
            // Ignore missing remote objects.
        }
        let localName = path.split(separator: "/").last.map(String.init) ?? path
        try? await localFallback.deleteImage(at: localName)
    }
}
