import XCTest
import CoreLocation
import MapKit

/// F20 / F1 / F4: NavigationService distance-windowing and step advancement.
@MainActor
final class NavigationServiceTests: XCTestCase {

    // MARK: - F20: distanceFromRoute with <2 polyline points returns 0 (on-route)

    /// A location 10+ km from anything, with NO route set, reports distance 0
    /// (= "on route") instead of a sentinel/large value.
    func testDistanceFromRouteEmptyPolylineReturnsZeroForDistantLocation() async {
        let service = NavigationService()
        let farAway = CLLocation(latitude: 37.7749, longitude: -122.4194) // SF; no route at all
        let distance = service.distanceFromRoute(location: farAway)
        XCTAssertGreaterThan(
            distance, 1000,
            "F20: with no route, distance should be a sentinel/large value, not 0 (on-route)"
        )
    }

    /// Same bug with a degenerate 1-point polyline.
    func testDistanceFromRouteSinglePointPolylineReturnsZeroForDistantLocation() async {
        let service = NavigationService()
        service.routePolylineCoordinates = [
            CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        ]
        let tenKmAway = CLLocation(latitude: 37.8649, longitude: -122.4194) // ~10 km north
        let distance = service.distanceFromRoute(location: tenKmAway)
        XCTAssertGreaterThan(
            distance, 1000,
            "F20: with a 1-point polyline, distance should be a sentinel/large value, not 0"
        )
    }

    /// Control: a healthy 2-point polyline measures distance correctly.
    func testDistanceFromRouteControlTwoPointPolyline() async {
        let service = NavigationService()
        service.routePolylineCoordinates = [
            CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            CLLocationCoordinate2D(latitude: 37.7849, longitude: -122.4194)
        ]
        let onRoute = CLLocation(latitude: 37.7799, longitude: -122.4194) // midpoint of segment
        let distance = service.distanceFromRoute(location: onRoute)
        XCTAssertLessThan(distance, 50, "Control: point on segment should be ~0 m from route")
    }

    // MARK: - F1: estimatedPolylineIndex never reset in setRoute/stopNavigation

    /// Long route driven forward (index at 150 of 200), then a new SHORT route
    /// (5 points) is set. distanceFromRoute windows around the stale index
    /// (searchStart 140 > searchEnd 4 -> empty loop) -> greatestFiniteMagnitude
    /// for a point ON the new route.
    ///
    /// Note: estimatedPolylineIndex is assigned through the internal test seam
    /// to simulate post-drive state, because the real drive path
    /// (updateLocation -> updateEstimates -> updatePolylineIndex) requires an
    /// MKRoute, which has no public initializer. The reset omission itself
    /// lives in the real setRoute/stopNavigation code (NavigationService.swift
    /// lines 50-99: neither touches estimatedPolylineIndex).
    func testStalePolylineIndexCausesInfiniteOffRoute() async {
        let service = NavigationService()

        // Long route: 200 points spanning ~20 km due north.
        service.routePolylineCoordinates = (0..<200).map {
            CLLocationCoordinate2D(latitude: 37.0 + Double($0) * 0.001, longitude: -122.0)
        }
        // Simulated state after driving 3/4 of the route (seam, see note above).
        service.estimatedPolylineIndex = 150

        // New route is set — this is exactly what setRoute does at
        // NavigationService.swift:61 (assign routePolylineCoordinates; no index
        // reset). New route has 200 points so the stale window [140,170] is in
        // bounds (a SHORTER route makes the stale range 140..<4 fatal-error —
        // Range requires lowerBound <= upperBound — verified by runner crash
        // on 2026-07-20; this variant uses a long route to get a clean
        // finite-distance failure instead of a crash).
        service.routePolylineCoordinates = (0..<200).map {
            CLLocationCoordinate2D(latitude: 37.10 + Double($0) * 0.001, longitude: -122.0)
        }

        // Point ON the new route near its start — outside the stale window.
        let onNewRoute = CLLocation(latitude: 37.101, longitude: -122.0)
        let distance = service.distanceFromRoute(location: onNewRoute)
        XCTAssertLessThan(
            distance, 50,
            "F1: point ON the new route should be ~0 m; stale estimatedPolylineIndex windows it out"
        )
    }

    /// Same bug through the real stopNavigation() API: it clears the route but
    /// not estimatedPolylineIndex, poisoning the next session's distance checks.
    /// (With a 5-point next route this test CRASHED the runner on 2026-07-20:
    /// stale window 140..<4 -> "Range requires lowerBound <= upperBound".
    /// Long next route used here to get a clean finite-distance failure.)
    func testStopNavigationDoesNotResetPolylineIndex() async {
        let service = NavigationService()
        service.routePolylineCoordinates = (0..<200).map {
            CLLocationCoordinate2D(latitude: 37.0 + Double($0) * 0.001, longitude: -122.0)
        }
        service.estimatedPolylineIndex = 150 // simulated post-drive state (seam)

        service.stopNavigation() // real API call — clears route, NOT the index

        // Next navigation: setRoute assigns new coordinates (line 61).
        service.routePolylineCoordinates = (0..<200).map {
            CLLocationCoordinate2D(latitude: 37.10 + Double($0) * 0.001, longitude: -122.0)
        }

        // Point ON the new route near its start — outside the stale window.
        let onNewRoute = CLLocation(latitude: 37.101, longitude: -122.0)
        let distance = service.distanceFromRoute(location: onNewRoute)
        XCTAssertLessThan(
            distance, 50,
            "F1: after stopNavigation + new route, point ON route should be ~0 m, not windowed out by stale index"
        )
    }

    /// Control: fresh index (0) on the same short route measures correctly.
    func testFreshPolylineIndexControl() async {
        let service = NavigationService()
        service.routePolylineCoordinates = (0..<5).map {
            CLLocationCoordinate2D(latitude: 37.10 + Double($0) * 0.001, longitude: -122.0)
        }
        let onRoute = CLLocation(latitude: 37.102, longitude: -122.0)
        let distance = service.distanceFromRoute(location: onRoute)
        XCTAssertLessThan(distance, 50, "Control: fresh index should measure ~0 m")
    }

    // MARK: - F4: step advancement only checks the CURRENT step's end

    /// Place the driver 1 m from the END of step[3]. Correct behavior: snap/
    /// advance to step 3. Actual: stuck at 0, because checkStepAdvancement only
    /// measures distance to the current step's end within 50 m.
    /// Requires network (MKDirections). Skips if directions unavailable.
    func testStepAdvancementOnlyChecksCurrentStepEnd() async throws {
        let service = NavigationService()
        let route: MKRoute
        do {
            route = try await service.calculateRoute(
                from: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), // SF
                to: CLLocationCoordinate2D(latitude: 37.3382, longitude: -121.8863)   // San Jose
            )
        } catch {
            throw XCTSkip("MKDirections unavailable in this environment: \(error.localizedDescription)")
        }

        service.setRoute(route)
        service.startNavigation()

        let steps = service.navigationState.steps
        guard steps.count >= 4 else {
            throw XCTSkip("Route returned only \(steps.count) steps; need at least 4")
        }

        let targetStep = steps[3]
        let pointCount = targetStep.polyline.pointCount
        var stepEnd = CLLocationCoordinate2D()
        targetStep.polyline.getCoordinates(&stepEnd, range: NSRange(location: pointCount - 1, length: 1))

        service.updateLocation(CLLocation(latitude: stepEnd.latitude, longitude: stepEnd.longitude))

        XCTAssertEqual(
            service.navigationState.currentStepIndex, 3,
            "F4: standing at step[3]'s end should snap/advance to step 3"
        )
    }

    /// Control: 1 m from step[0]'s end advances to step 1 — proves the
    /// advancement machinery works when you are on the current step.
    func testStepAdvancementControlCurrentStepEnd() async throws {
        let service = NavigationService()
        let route: MKRoute
        do {
            route = try await service.calculateRoute(
                from: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                to: CLLocationCoordinate2D(latitude: 37.3382, longitude: -121.8863)
            )
        } catch {
            throw XCTSkip("MKDirections unavailable in this environment: \(error.localizedDescription)")
        }

        service.setRoute(route)
        service.startNavigation()

        let steps = service.navigationState.steps
        guard steps.count >= 2 else {
            throw XCTSkip("Route returned only \(steps.count) steps")
        }

        let firstStep = steps[0]
        let pointCount = firstStep.polyline.pointCount
        var stepEnd = CLLocationCoordinate2D()
        firstStep.polyline.getCoordinates(&stepEnd, range: NSRange(location: pointCount - 1, length: 1))

        service.updateLocation(CLLocation(latitude: stepEnd.latitude, longitude: stepEnd.longitude))

        XCTAssertEqual(
            service.navigationState.currentStepIndex, 1,
            "Control: reaching step[0]'s end should advance to step 1"
        )
    }
}
