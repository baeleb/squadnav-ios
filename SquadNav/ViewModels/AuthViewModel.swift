import Foundation
import AuthenticationServices

@MainActor
class AuthViewModel: ObservableObject {
    @Published var currentUser: AppUser?
    @Published var isLoading: Bool = true
    @Published var error: String?
    @Published var isSigningIn: Bool = false

    private let authService = FirebaseAuthService()
    private var currentNonce: String?

    init() {
        // Observe auth state
        Task {
            // Short delay to let Firebase restore session
            try? await Task.sleep(nanoseconds: 500_000_000)
            self.currentUser = authService.currentUser
            self.isLoading = false

            // Observe future changes
            for await _ in authService.$currentUser.values {
                self.currentUser = authService.currentUser
            }
        }
    }

    // MARK: - Email Auth

    func signInWithEmail(email: String, password: String) async {
        isSigningIn = true
        error = nil
        do {
            let user = try await authService.signInWithEmail(email: email, password: password)
            self.currentUser = user
        } catch {
            self.error = error.localizedDescription
        }
        isSigningIn = false
    }

    func signUpWithEmail(email: String, password: String, displayName: String) async {
        isSigningIn = true
        error = nil
        do {
            let user = try await authService.signUpWithEmail(email: email, password: password, displayName: displayName)
            self.currentUser = user
        } catch {
            self.error = error.localizedDescription
        }
        isSigningIn = false
    }

    // MARK: - Google Auth

    func signInWithGoogle() async {
        isSigningIn = true
        error = nil
        do {
            let user = try await authService.signInWithGoogle()
            self.currentUser = user
        } catch {
            self.error = error.localizedDescription
        }
        isSigningIn = false
    }

    // MARK: - Apple Auth

    func prepareAppleSignIn() -> (nonce: String, hashedNonce: String) {
        let nonce = authService.generateNonce()
        currentNonce = nonce
        let hashedNonce = authService.sha256(nonce)
        return (nonce, hashedNonce)
    }

    func handleAppleSignIn(result: Result<ASAuthorization, Error>) async {
        isSigningIn = true
        error = nil

        switch result {
        case .success(let authorization):
            guard let appleCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let nonce = currentNonce else {
                error = "Apple Sign-In failed: invalid credentials."
                isSigningIn = false
                return
            }

            do {
                let user = try await authService.signInWithApple(credential: appleCredential, nonce: nonce)
                self.currentUser = user
            } catch {
                self.error = error.localizedDescription
            }

        case .failure(let err):
            // User cancelled is not an error
            if (err as NSError).code != ASAuthorizationError.canceled.rawValue {
                self.error = err.localizedDescription
            }
        }

        isSigningIn = false
    }

    // MARK: - Sign Out

    func signOut() {
        do {
            try authService.signOut()
            currentUser = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
