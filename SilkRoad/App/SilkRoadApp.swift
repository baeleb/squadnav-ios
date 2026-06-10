import SwiftUI
import FirebaseCore
import GoogleSignIn

@main
struct SilkRoadApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var authViewModel = AuthViewModel()
    @StateObject private var deepLinkRouter = DeepLinkRouter()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authViewModel)
                .environmentObject(deepLinkRouter)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    // With the SwiftUI scene lifecycle, the app delegate's
                    // open-URL callback is never invoked — URLs arrive here.
                    if GIDSignIn.sharedInstance.handle(url) { return }
                    deepLinkRouter.handle(url)
                }
        }
    }
}

// MARK: - Deep Link Router

/// Routes incoming custom-scheme URLs (e.g. silkroad://join/ABC123 from a
/// scanned invite QR code) to the relevant UI.
@MainActor
final class DeepLinkRouter: ObservableObject {
    @Published var pendingInviteCode: String?

    func handle(_ url: URL) {
        guard url.scheme?.lowercased() == "silkroad",
              url.host?.lowercased() == "join" else { return }

        let code = url.lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard code.count == 6 else { return }

        pendingInviteCode = code
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        return true
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        return GIDSignIn.sharedInstance.handle(url)
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if connectingSceneSession.role == .carTemplateApplication {
            let config = UISceneConfiguration(
                name: "CarPlay",
                sessionRole: connectingSceneSession.role
            )
            config.delegateClass = CarPlaySceneDelegate.self
            return config
        }
        let config = UISceneConfiguration(
            name: "Default",
            sessionRole: connectingSceneSession.role
        )
        return config
    }
}
