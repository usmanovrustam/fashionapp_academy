import Foundation
import FirebaseFirestore

enum FirestorePaths {
    static func userRoot(uid: String) -> String { "users/\(uid)" }
    static func profile(uid: String) -> String { "users/\(uid)/profile/main" }
    static func wardrobe(uid: String) -> String { "users/\(uid)/wardrobeItems" }
    static func outfits(uid: String) -> String { "users/\(uid)/outfits" }
    static func recommendations(uid: String) -> String { "users/\(uid)/recommendations" }
    static func events(uid: String) -> String { "users/\(uid)/events" }
    static func packingLists(uid: String) -> String { "users/\(uid)/packingLists" }
    static func outfitHistory(uid: String) -> String { "users/\(uid)/outfitHistory" }
    static func weatherCache(uid: String) -> String { "users/\(uid)/weatherCache/latest" }
    static func analyticsEvents(uid: String) -> String { "users/\(uid)/analyticsEvents" }
}

enum FirestoreCoding {
    static func encode<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder.sylyo.encode(value)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            throw DomainError.storageFailed("Unable to encode Firestore document.")
        }
        return dictionary
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: [String: Any]) throws -> T {
        let json = try JSONSerialization.data(withJSONObject: data)
        return try JSONDecoder.sylyo.decode(T.self, from: json)
    }
}

enum FirebaseUserContext {
    @MainActor
    static func requireUID() throws -> String {
        guard let uid = AuthSession.shared.userID else {
            throw AuthError.notSignedIn
        }
        return uid
    }
}

/// Tiny bridge so repositories can read the signed-in UID without importing UI.
@MainActor
final class AuthSession {
    static let shared = AuthSession()
    var userID: String?
    private init() {}
}
