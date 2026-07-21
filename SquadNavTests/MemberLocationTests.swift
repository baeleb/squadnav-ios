import XCTest
import CoreLocation

/// F7a / F14: MemberLocation formatting and default-coordinate ambiguity.
final class MemberLocationTests: XCTestCase {

    /// F7a: CLLocation reports speed -1 when speed is invalid/unknown.
    /// formattedSpeed must clamp to a non-negative display ("0 mph");
    /// actual result is "-2 mph" (Int(-1 * 2.237) = -2).
    func testNegativeSpeedFormatsAsNonNegative() {
        let member = MemberLocation(displayName: "Alice", speed: -1)
        XCTAssertEqual(
            member.formattedSpeed, "0 mph",
            "F7a: invalid speed (-1) should display as 0 mph, not negative"
        )
    }

    /// Control: a normal speed formats correctly.
    func testNormalSpeedFormatsCorrectly() {
        let member = MemberLocation(displayName: "Alice", speed: 10) // ~22 mph
        XCTAssertEqual(member.formattedSpeed, "22 mph")
    }

    /// F14 (root cause): a member that has NEVER uploaded a location decodes
    /// with coordinate (0,0) — indistinguishable from a member genuinely
    /// driving in the Gulf of Guinea. No validity flag exists to tell them
    /// apart (lastUpdated is nil, but nothing in the model or map layer keys
    /// off it). This test PASSES to document the root cause; the phantom map
    /// annotation itself is view-layer and untestable here.
    func testDefaultCoordinateIsZeroZeroWithoutValidityFlag() {
        let neverUploaded = MemberLocation(displayName: "Ghost")
        XCTAssertEqual(neverUploaded.latitude, 0)
        XCTAssertEqual(neverUploaded.longitude, 0)
        XCTAssertNil(neverUploaded.lastUpdated, "Never-uploaded member has nil lastUpdated — but coordinate still reads (0,0)")
        XCTAssertEqual(neverUploaded.coordinate, CLLocationCoordinate2D(latitude: 0, longitude: 0))

        // A genuine (0,0) upload is byte-for-byte identical in the fields the
        // map would consume — the bug's root cause.
        let genuinelyAtNullIsland = MemberLocation(displayName: "Sailor", latitude: 0, longitude: 0)
        XCTAssertEqual(neverUploaded.coordinate, genuinelyAtNullIsland.coordinate)
    }
}
