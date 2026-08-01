import Foundation

struct AuthUser: Equatable, Hashable, Identifiable {
    var id: String
    var email: String?
    var displayName: String?
    var isAnonymous: Bool
    /// Firebase provider IDs (e.g. `password`, `apple.com`, `anonymous`).
    var providerIDs: [String] = []

    var usesSignInWithApple: Bool {
        providerIDs.contains("apple.com")
    }
}

enum AuthError: LocalizedError, Equatable {
    case notConfigured
    case notSignedIn
    case invalidCredentials
    case emailAlreadyInUse
    case weakPassword
    case network
    case cancelled
    case underlying(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Firebase is not configured. Add GoogleService-Info.plist from the Firebase console."
        case .notSignedIn:
            return "You need to sign in to continue."
        case .invalidCredentials:
            return "Invalid email or password."
        case .emailAlreadyInUse:
            return "That email is already registered."
        case .weakPassword:
            return "Password should be at least 6 characters."
        case .network:
            return "Network error. Check your connection and try again."
        case .cancelled:
            return "Sign in was cancelled."
        case .underlying(let message):
            return message
        }
    }
}

/// Firebase Authentication surface used by the app.
@MainActor
protocol AuthServicing: AnyObject {
    var currentUser: AuthUser? { get }
    var isSignedIn: Bool { get }
    var isFirebaseConfigured: Bool { get }

    func refreshSession() async -> AuthUser?
    func signInAnonymously() async throws -> AuthUser
    func signIn(email: String, password: String) async throws -> AuthUser
    func signUp(email: String, password: String, displayName: String?) async throws -> AuthUser
    /// Completes Sign in with Apple using the identity token + original raw nonce.
    func signInWithApple(idToken: String, rawNonce: String, fullName: PersonNameComponents?) async throws -> AuthUser
    func updateDisplayName(_ name: String) async throws
    func signOut() throws
    func sendPasswordReset(email: String) async throws
}

@MainActor
extension AuthServicing {
    var isSignedIn: Bool { currentUser != nil }
}
