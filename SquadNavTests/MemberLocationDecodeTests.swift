import XCTest
import FirebaseFirestore

/// Regression probe: member docs written BEFORE the `joinedAt` field
/// existed must still decode. The members listener uses
/// `compactMap { try? $0.data(as:) }` — one bad field drops the whole
/// document silently (observed: members count 0, succession never fires).
final class MemberLocationDecodeTests: XCTestCase {

    override class func setUp() {
        FirebaseTestSupport.configureIfNeeded()
    }

    /// Exact field set of a pre-joinedAt member doc (as joinGroup wrote it).
    func testDecodesDocWithoutJoinedAtField() throws {
        let legacy: [String: Any] = [
            "displayName": "Sim2 User",
            "role": "driver",
            "latitude": 0.0,
            "longitude": 0.0,
            "heading": 0.0,
            "speed": 0.0,
            "lastUpdated": Timestamp(date: Date()),
            "status": "idle",
            "currentStepIndex": 0
            // NOTE: no "joinedAt" key — field absent entirely
        ]

        // @DocumentID decoding requires the document reference in userInfo,
        // mirroring what snapshot.data(as:) passes internally.
        let ref = Firestore.firestore().document("groups/g1/members/m1")
        let decoder = Firestore.Decoder()
        decoder.userInfo[CodingUserInfoKey(rawValue: "DocumentRefUserInfoKey")!] = ref
        let decoded = try decoder.decode(MemberLocation.self, from: legacy)
        XCTAssertEqual(decoded.displayName, "Sim2 User")
        XCTAssertNil(decoded.joinedAt)
    }
}
