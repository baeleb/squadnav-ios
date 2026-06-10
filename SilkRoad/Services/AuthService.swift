import Foundation
import FirebaseAuth
import GoogleSignIn
import AuthenticationServices
import CryptoKit

// MARK: - Protocol

@MainActor
protocol AuthServiceProtocol {
    var currentUser: AppUser? { get }
    func signInWithEmail(email: String, password: String) async throws -> AppUser
    func signUpWithEmail(email: String, password: String, displayName: String) async throws -> AppUser
    func signInWithGoogle() async throws -> AppUser
    func signInWithApple(credential: ASAuthorizationAppleIDCredential, nonce: String) async throws -> AppUser
    func signOut() throws
    func generateNonce() -> String
    func sha256(_ input: String) -> String
}

// MARK: - Firebase Implementation

@MainActor
class FirebaseAuthService: ObservableObject, AuthServiceProtocol {
    @Published var currentUser: AppUser?
    private var authListener: AuthStateDidChangeListenerHandle?

    init() {
        listenToAuthChanges()
    }

    deinit {
        if let listener = authListener {
            Auth.auth().removeStateDidChangeListener(listener)
        }
    }

    private func listenToAuthChanges() {
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, firebaseUser in
            guard let self else { return }
            if let firebaseUser {
                self.currentUser = AppUser(
                    id: firebaseUser.uid,
                    displayName: firebaseUser.displayName ?? "Driver",
                    email: firebaseUser.email ?? "",
                    photoURL: firebaseUser.photoURL?.absoluteString,
                    createdAt: firebaseUser.metadata.creationDate ?? Date()
                )
            } else {
                self.currentUser = nil
            }
        }
    }

    func signInWithEmail(email: String, password: String) async throws -> AppUser {
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        let user = AppUser(
            id: result.user.uid,
            displayName: result.user.displayName ?? "Driver",
            email: result.user.email ?? email,
            photoURL: result.user.photoURL?.absoluteString
        )
        self.currentUser = user
        return user
    }

    func signUpWithEmail(email: String, password: String, displayName: String) async throws -> AppUser {
        let result = try await Auth.auth().createUser(withEmail: email, password: password)

        let changeRequest = result.user.createProfileChangeRequest()
        changeRequest.displayName = displayName
        try await changeRequest.commitChanges()

        let user = AppUser(
            id: result.user.uid,
            displayName: displayName,
            email: email,
            photoURL: nil
        )
        self.currentUser = user

        // Store user doc in Firestore
        try await UserRepository.createUserDocument(user: user)

        return user
    }

    func signInWithGoogle() async throws -> AppUser {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootViewController = window.rootViewController else {
            throw AuthError.noRootViewController
        }

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)

        guard let idToken = result.user.idToken?.tokenString else {
            throw AuthError.missingToken
        }

        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: result.user.accessToken.tokenString
        )

        let authResult = try await Auth.auth().signIn(with: credential)

        let user = AppUser(
            id: authResult.user.uid,
            displayName: authResult.user.displayName ?? "Driver",
            email: authResult.user.email ?? "",
            photoURL: authResult.user.photoURL?.absoluteString
        )
        self.currentUser = user

        try await UserRepository.createUserDocumentIfNeeded(user: user)

        return user
    }

    func signInWithApple(credential: ASAuthorizationAppleIDCredential, nonce: String) async throws -> AppUser {
        guard let appleIDToken = credential.identityToken,
              let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
            throw AuthError.missingToken
        }

        let firebaseCredential = OAuthProvider.appleCredential(
            withIDToken: idTokenString,
            rawNonce: nonce,
            fullName: credential.fullName
        )

        let authResult = try await Auth.auth().signIn(with: firebaseCredential)

        var displayName = authResult.user.displayName ?? "Driver"
        if let fullName = credential.fullName {
            let name = [fullName.givenName, fullName.familyName]
                .compactMap { $0 }
                .joined(separator: " ")
            if !name.isEmpty {
                displayName = name
                let changeRequest = authResult.user.createProfileChangeRequest()
                changeRequest.displayName = displayName
                try? await changeRequest.commitChanges()
            }
        }

        let user = AppUser(
            id: authResult.user.uid,
            displayName: displayName,
            email: authResult.user.email ?? credential.email ?? "",
            photoURL: authResult.user.photoURL?.absoluteString
        )
        self.currentUser = user

        try await UserRepository.createUserDocumentIfNeeded(user: user)

        return user
    }

    func signOut() throws {
        try Auth.auth().signOut()
        self.currentUser = nil
    }

    // MARK: - Apple Sign-In Helpers

    func generateNonce() -> String {
        let length = 32
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var nonce = ""
        var remainingLength = length

        while remainingLength > 0 {
            let randoms: [UInt8] = (0 ..< 16).map { _ in
                var random: UInt8 = 0
                let errorCode = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                if errorCode != errSecSuccess {
                    fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
                }
                return random
            }

            randoms.forEach { random in
                if remainingLength == 0 { return }
                if random < charset.count {
                    nonce.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }

        return nonce
    }

    func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - User Repository

enum UserRepository {
    static func createUserDocument(user: AppUser) async throws {
        guard let uid = user.id else { return }
        let db = FirestoreService.shared.db
        try db.collection("users").document(uid).setData(from: user)
    }

    static func createUserDocumentIfNeeded(user: AppUser) async throws {
        guard let uid = user.id else { return }
        let db = FirestoreService.shared.db
        let doc = try await db.collection("users").document(uid).getDocument()
        if !doc.exists {
            try db.collection("users").document(uid).setData(from: user)
        }
    }
}

// MARK: - Firestore Singleton

class FirestoreService {
    static let shared = FirestoreService()

    let db: Firestore

    private init() {
        db = Firestore.firestore()
    }
}

import FirebaseFirestore

// MARK: - Errors

enum AuthError: LocalizedError {
    case noRootViewController
    case missingToken
    case unknown

    var errorDescription: String? {
        switch self {
        case .noRootViewController: return "Cannot find root view controller."
        case .missingToken: return "Authentication token is missing."
        case .unknown: return "An unknown error occurred."
        }
    }
}
