import XCTest

/// Leadership succession: GroupService.firstJoinedMemberId picks the
/// earliest-joined member for involuntary handoff (leader crash /
/// connection loss). Pure static function — no Firebase needed.
@MainActor
final class LeadershipSuccessionTests: XCTestCase {

    private func member(_ id: String?, joinedAt: Date?) -> MemberLocation {
        MemberLocation(id: id, displayName: id ?? "?", joinedAt: joinedAt)
    }

    func testEarliestJoinedWins() {
        let t0 = Date()
        let members = [
            member("b", joinedAt: t0.addingTimeInterval(60)),
            member("a", joinedAt: t0),                       // earliest
            member("c", joinedAt: t0.addingTimeInterval(120))
        ]
        XCTAssertEqual(GroupService.firstJoinedMemberId(members: members), "a")
    }

    func testMembersWithoutJoinedAtSortLast() {
        // Pre-field docs have nil joinedAt — they must never outrank a
        // timestamped member, or old groups would hand leadership to an
        // arbitrary member.
        let t0 = Date()
        let members = [
            member("old", joinedAt: nil),
            member("new", joinedAt: t0)
        ]
        XCTAssertEqual(GroupService.firstJoinedMemberId(members: members), "new")
    }

    func testAllNilJoinedAtFallsBackToFirstDoc() {
        let members = [member("x", joinedAt: nil), member("y", joinedAt: nil)]
        XCTAssertEqual(GroupService.firstJoinedMemberId(members: members), "x")
    }

    func testEmptyMembersReturnsNil() {
        XCTAssertNil(GroupService.firstJoinedMemberId(members: []))
    }

    func testMembersWithoutIdsExcluded() {
        let t0 = Date()
        let members = [member(nil, joinedAt: t0), member("z", joinedAt: t0.addingTimeInterval(60))]
        XCTAssertEqual(GroupService.firstJoinedMemberId(members: members), "z")
    }
}
