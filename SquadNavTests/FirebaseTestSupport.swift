import XCTest
import FirebaseCore

/// Standalone test target has no app host, so AppDelegate never runs and
/// FirebaseApp is not configured. Tests that construct Firebase-backed
/// services (GroupService/ChatService touch Firestore.firestore() at init;
/// Auth.auth() crashes without a configured app) configure Firebase once
/// with the repo's dummy GoogleService-Info.plist. No network calls are
/// awaited in these tests.
enum FirebaseTestSupport {
    static func configureIfNeeded() {
        guard FirebaseApp.app() == nil else { return }
        let bundle = Bundle(for: BundleToken.self)
        guard let path = bundle.path(forResource: "GoogleService-Info", ofType: "plist"),
              let options = FirebaseOptions(contentsOfFile: path) else {
            XCTFail("GoogleService-Info.plist missing from SquadNavTests bundle resources")
            return
        }
        FirebaseApp.configure(options: options)
    }
}

private final class BundleToken {}
