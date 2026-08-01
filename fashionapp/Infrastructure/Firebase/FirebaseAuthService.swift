import Foundation
import FirebaseAuth
import Combine

@MainActor
final class FirebaseAuthService: ObservableObject, AuthServicing {
    @Published private(set) var currentUser: AuthUser?
    let isFirebaseConfigured: Bool

    private var handle: AuthStateDidChangeListenerHandle?

    init() {
        isFirebaseConfigured = FirebaseBootstrap.configureIfPossible()
        guard isFirebaseConfigured else {
            currentUser = nil
            return
        }

        handle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.currentUser = user.map(Self.map)
                AuthSession.shared.userID = user?.uid
            }
        }
        currentUser = Auth.auth().currentUser.map(Self.map)
        AuthSession.shared.userID = currentUser?.id
    }

    deinit {
        if let handle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    func refreshSession() async -> AuthUser? {
        guard isFirebaseConfigured else { return nil }
        currentUser = Auth.auth().currentUser.map(Self.map)
        AuthSession.shared.userID = currentUser?.id
        return currentUser
    }

    func signInAnonymously() async throws -> AuthUser {
        try ensureConfigured()
        do {
            let result = try await Auth.auth().signInAnonymously()
            let mapped = Self.map(result.user)
            currentUser = mapped
            AuthSession.shared.userID = mapped.id
            return mapped
        } catch {
            throw mapError(error)
        }
    }

    func signIn(email: String, password: String) async throws -> AuthUser {
        try ensureConfigured()
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            let mapped = Self.map(result.user)
            currentUser = mapped
            AuthSession.shared.userID = mapped.id
            return mapped
        } catch {
            throw mapError(error)
        }
    }

    func signUp(email: String, password: String, displayName: String?) async throws -> AuthUser {
        try ensureConfigured()
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            if let displayName, !displayName.isEmpty {
                let request = result.user.createProfileChangeRequest()
                request.displayName = displayName
                try await request.commitChanges()
            }
            let mapped = Self.map(result.user)
            currentUser = mapped
            AuthSession.shared.userID = mapped.id
            return mapped
        } catch {
            throw mapError(error)
        }
    }

    func updateDisplayName(_ name: String) async throws {
        try ensureConfigured()
        guard let user = Auth.auth().currentUser else { throw AuthError.notSignedIn }
        let request = user.createProfileChangeRequest()
        request.displayName = name
        try await request.commitChanges()
        currentUser = Self.map(user)
    }

    func signOut() throws {
        try ensureConfigured()
        try Auth.auth().signOut()
        currentUser = nil
        AuthSession.shared.userID = nil
    }

    func sendPasswordReset(email: String) async throws {
        try ensureConfigured()
        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
        } catch {
            throw mapError(error)
        }
    }

    private func ensureConfigured() throws {
        guard isFirebaseConfigured else { throw AuthError.notConfigured }
    }

    private static func map(_ user: User) -> AuthUser {
        AuthUser(
            id: user.uid,
            email: user.email,
            displayName: user.displayName,
            isAnonymous: user.isAnonymous
        )
    }

    private func mapError(_ error: Error) -> AuthError {
        let nsError = error as NSError
        guard nsError.domain == AuthErrorDomain,
              let code = AuthErrorCode(rawValue: nsError.code) else {
            return .underlying(error.localizedDescription)
        }

        switch code {
        case .wrongPassword, .invalidEmail, .userNotFound, .invalidCredential:
            return .invalidCredentials
        case .emailAlreadyInUse:
            return .emailAlreadyInUse
        case .weakPassword:
            return .weakPassword
        case .networkError:
            return .network
        default:
            return .underlying(error.localizedDescription)
        }
    }
}
