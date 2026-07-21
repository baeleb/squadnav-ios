import XCTest
import CoreLocation

/// F5 / F10 / F7b / F9: CaravanMonitorService member classification.
/// Tests call the pure classification path (evaluateMemberStatus, exposed via
/// internal test seam) — no Firestore access. Firebase is configured only
/// because GroupService/ChatService touch Firestore.firestore()/Auth at init.
@MainActor
final class CaravanMonitorTests: XCTestCase {

    override class func setUp() {
        FirebaseTestSupport.configureIfNeeded()
    }

    /// A California route (SF -> San Jose straight line).
    private let californiaRoute: [CLLocationCoordinate2D] = [
        CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        CLLocationCoordinate2D(latitude: 37.3382, longitude: -121.8863)
    ]
    /// Point exactly on that route (midpoint).
    private let onRoutePoint = CLLocationCoordinate2D(latitude: 37.55655, longitude: -122.15285)

    private func makeMonitor() -> CaravanMonitorService {
        let monitor = CaravanMonitorService(groupService: GroupService(), chatService: ChatService())
        monitor.setRoute(coordinates: californiaRoute)
        return monitor
    }

    /// F5: a member who never uploaded a location decodes at (0,0), which is
    /// ~10,000 km from the California route -> classified .offRoute and
    /// alerts the whole caravan. Expected: .idle / skipped as no-data.
    func testMemberAtZeroZeroClassifiedOffRoute() async {
        let monitor = makeMonitor()
        let ghost = MemberLocation(id: "ghost", displayName: "Ghost", latitude: 0, longitude: 0, speed: 0)
        let status = monitor.evaluateMemberStatus(member: ghost, leader: nil)
        XCTAssertEqual(
            status, .idle,
            "F5: member at never-uploaded (0,0) should be idle/skipped, not off-route"
        )
    }

    /// F10: a member whose lastUpdated is 1 hour stale is still evaluated as
    /// live data. Expected: excluded / .idle. Actual: .onRoute.
    func testStaleMemberEvaluatedAsLive() async {
        let monitor = makeMonitor()
        let stale = MemberLocation(
            id: "stale",
            displayName: "Stale",
            latitude: onRoutePoint.latitude,
            longitude: onRoutePoint.longitude,
            speed: 5,
            lastUpdated: Date(timeIntervalSinceNow: -3600) // 1 hour old
        )
        let status = monitor.evaluateMemberStatus(member: stale, leader: nil)
        XCTAssertEqual(
            status, .idle,
            "F10: member with 1-hour-stale location should be excluded/idle, not trusted as live"
        )
    }

    /// F7b: CLLocation uses speed -1 for "invalid/unknown". The monitor's
    /// `member.speed < 1.4` check treats -1 as stopped; after the 60 s
    /// threshold it reports .stopped. Expected: invalid speed ignored
    /// (member is otherwise on-route -> .onRoute).
    func testNegativeSpeedClassifiedAsStopped() async {
        let monitor = makeMonitor()
        // Seed the stop timer as if the member has been below threshold for 2 min
        // (internal seam; avoids waiting 60 s real time).
        monitor.stoppedTimers["neg"] = Date(timeIntervalSinceNow: -120)

        let invalidSpeed = MemberLocation(
            id: "neg",
            displayName: "NoSpeed",
            latitude: onRoutePoint.latitude,
            longitude: onRoutePoint.longitude,
            speed: -1 // CLLocation invalid-speed sentinel
        )
        let status = monitor.evaluateMemberStatus(member: invalidSpeed, leader: nil)
        XCTAssertEqual(
            status, .onRoute,
            "F7b: speed -1 (invalid) should be ignored, not classified as stopped"
        )
    }

    /// F9: monitor state (stoppedTimers) is never reset between navigation
    /// sessions. A member who was stopped >60 s in a PREVIOUS session is
    /// instantly .stopped on the first tick of a NEW session, with zero new
    /// observation. setRoute (what startNavigation calls per session) performs
    /// no reset. Expected: fresh session requires a fresh 60 s observation.
    func testStoppedStatePersistsAcrossSessions() async {
        let monitor = makeMonitor()
        // Previous session left this timer behind (seam; simulates prior session state).
        monitor.stoppedTimers["carry"] = Date(timeIntervalSinceNow: -120)

        // New navigation session starts — real API call, performs no state reset.
        monitor.setRoute(coordinates: californiaRoute)

        let member = MemberLocation(
            id: "carry",
            displayName: "Carry",
            latitude: onRoutePoint.latitude,
            longitude: onRoutePoint.longitude,
            speed: 0
        )
        let status = monitor.evaluateMemberStatus(member: member, leader: nil)
        XCTAssertEqual(
            status, .onRoute,
            "F9: first tick of a new session should not inherit stopped timers from a previous session"
        )
    }
}
