import XCTest

/// F13: GroupService.updateMemberLocation silently no-ops when signed out.
/// Sibling methods (createGroup/joinGroup/leaveGroup) throw
/// GroupError.notAuthenticated in the same situation; updateMemberLocation
/// just `return`s, so the leader's location silently stops uploading.
/// Firebase is configured (dummy plist) so Auth.auth() returns currentUser=nil
/// without crashing; the guard returns before any Firestore call.
@MainActor
final class GroupServiceTests: XCTestCase {

    override class func setUp() {
        FirebaseTestSupport.configureIfNeeded()
    }

    func testUpdateMemberLocationSignedOutThrows() async {
        let service = GroupService()
        do {
            try await service.updateMemberLocation(
                groupId: "group1",
                latitude: 37.7749,
                longitude: -122.4194,
                heading: 0,
                speed: 10,
                status: .onRoute,
                stepIndex: 0
            )
            XCTFail(
                "F13: updateMemberLocation silently no-ops when signed out; expected GroupError.notAuthenticated"
            )
        } catch GroupError.notAuthenticated {
            // Expected correct behavior.
        } catch {
            XCTFail("F13: unexpected error type: \(error)")
        }
    }
}
