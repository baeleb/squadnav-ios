import Foundation
import MapKit
import CoreLocation
import Combine

@MainActor
class NavigationService: ObservableObject {
    @Published var navigationState = NavigationState()
    @Published var routePolylineCoordinates: [CLLocationCoordinate2D] = []

    // Canonical shared route members converge onto; routePolylineCoordinates
    // is this member's active path (connector + shared remainder).
    private(set) var sharedRouteCoordinates: [CLLocationCoordinate2D] = []

    // True while on a connector leg; the uploader reports .rerouting then.
    var isConverging: Bool { navigationState.followUpRoute != nil }

    // Off-route detection
    private let offRouteThreshold: CLLocationDistance = 75  // meters
    private let offRouteTimeThreshold: TimeInterval = 5     // seconds
    private var offRouteStartTime: Date?

    // Step advancement
    private let stepAdvanceDistance: CLLocationDistance = 50  // meters

    var onOffRoute: (() -> Void)?
    var onStepAdvanced: ((Int) -> Void)?
    var onArrived: (() -> Void)?

    // MARK: - Route Calculation

    /// Calculates a route from origin to destination using MapKit.
    func calculateRoute(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async throws -> MKRoute {
        navigationState.phase = .calculatingRoute

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .automobile
        request.requestsAlternateRoutes = false

        let directions = MKDirections(request: request)
        let response = try await directions.calculate()

        guard let route = response.routes.first else {
            navigationState.phase = .error("No route found")
            throw NavigationError.noRouteFound
        }

        return route
    }

    /// Sets the active route and prepares for navigation.
    func setRoute(_ route: MKRoute) {
        navigationState.route = route
        navigationState.followUpRoute = nil
        navigationState.steps = route.steps.filter { !$0.instructions.isEmpty }
        navigationState.currentStepIndex = 0
        navigationState.totalDistanceRemaining = route.distance
        navigationState.estimatedTimeRemaining = route.expectedTravelTime
        estimatedPolylineIndex = 0

        // Extract polyline coordinates
        let pointCount = route.polyline.pointCount
        var coords = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: pointCount)
        route.polyline.getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        routePolylineCoordinates = coords
        sharedRouteCoordinates = coords
    }

    /// Sets route from an encoded polyline string (for non-leader drivers).
    /// Members away from the shared route get a converging route instead of
    /// steps computed from the leader's start point.
    func setRouteFromPolyline(
        _ encodedPolyline: String,
        destination: CLLocationCoordinate2D,
        from memberLocation: CLLocationCoordinate2D? = nil
    ) async throws {
        let coordinates = RouteEncoder.decode(polyline: encodedPolyline)
        sharedRouteCoordinates = coordinates

        guard let firstCoord = coordinates.first else {
            throw NavigationError.noRouteFound
        }

        if let memberLocation {
            try await setConvergingRoute(
                from: memberLocation,
                destination: destination,
                searchFromIndex: 0
            )
            return
        }

        // No member location: assume they are at the route start (leader path).
        let route = try await calculateRoute(from: firstCoord, to: destination)
        setRoute(route)
        sharedRouteCoordinates = routePolylineCoordinates
    }

    /// Reconnects to the canonical shared route after going off-route.
    /// Local-only: the shared route in Firestore is never touched.
    func rerouteToSharedRoute(
        from memberLocation: CLLocationCoordinate2D,
        destination: CLLocationCoordinate2D
    ) async throws {
        guard !sharedRouteCoordinates.isEmpty else {
            throw NavigationError.noRouteFound
        }
        try await setConvergingRoute(
            from: memberLocation,
            destination: destination,
            searchFromIndex: estimatedPolylineIndex
        )
        navigationState.isOffRoute = false
        navigationState.phase = .navigating
        offRouteStartTime = nil
    }

    /// Builds the active route as connector (member → nearest shared point
    /// at/after searchFromIndex) + shared remainder held in `followUpRoute`
    /// and swapped in when the connector completes.
    private func setConvergingRoute(
        from memberLocation: CLLocationCoordinate2D,
        destination: CLLocationCoordinate2D,
        searchFromIndex: Int
    ) async throws {
        let joinIndex = nearestPolylineIndex(
            to: memberLocation,
            in: sharedRouteCoordinates,
            from: searchFromIndex
        )
        let joinPoint = sharedRouteCoordinates[joinIndex]
        let sharedRemainder = Array(sharedRouteCoordinates[joinIndex...])

        let memberLoc = CLLocation(latitude: memberLocation.latitude, longitude: memberLocation.longitude)
        let joinLoc = CLLocation(latitude: joinPoint.latitude, longitude: joinPoint.longitude)

        let remainderRoute = try await calculateRoute(from: joinPoint, to: destination)

        // Already essentially on the shared route: follow the remainder
        // directly, no connector leg.
        guard memberLoc.distance(from: joinLoc) > 100 else {
            setRoute(remainderRoute)
            routePolylineCoordinates = sharedRemainder
            return
        }

        let connectorRoute = try await calculateRoute(from: memberLocation, to: joinPoint)

        navigationState.route = connectorRoute
        navigationState.followUpRoute = remainderRoute
        navigationState.steps = connectorRoute.steps.filter { !$0.instructions.isEmpty }
        navigationState.currentStepIndex = 0
        navigationState.totalDistanceRemaining = connectorRoute.distance + remainderRoute.distance
        navigationState.estimatedTimeRemaining = connectorRoute.expectedTravelTime + remainderRoute.expectedTravelTime
        estimatedPolylineIndex = 0

        routePolylineCoordinates = polylineCoordinates(of: connectorRoute) + sharedRemainder
    }

    /// Index of the shared-polyline vertex closest to `location`, searching
    /// only at/after `fromIndex` so reconnects converge forward, never back.
    func nearestPolylineIndex(
        to location: CLLocationCoordinate2D,
        in coordinates: [CLLocationCoordinate2D],
        from fromIndex: Int = 0
    ) -> Int {
        guard !coordinates.isEmpty else { return 0 }
        let loc = CLLocation(latitude: location.latitude, longitude: location.longitude)
        let start = max(0, min(fromIndex, coordinates.count - 1))

        var bestIndex = start
        var bestDistance: CLLocationDistance = .greatestFiniteMagnitude
        for i in start..<coordinates.count {
            let coord = coordinates[i]
            let dist = loc.distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude))
            if dist < bestDistance {
                bestDistance = dist
                bestIndex = i
            }
        }
        return bestIndex
    }

    private func polylineCoordinates(of route: MKRoute) -> [CLLocationCoordinate2D] {
        let pointCount = route.polyline.pointCount
        var coords = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: pointCount)
        route.polyline.getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }

    /// Encodes the current route's polyline for sharing via Firestore.
    func encodeCurrentRoute() -> String? {
        guard !routePolylineCoordinates.isEmpty else { return nil }
        return RouteEncoder.encode(coordinates: routePolylineCoordinates)
    }

    // MARK: - Navigation Control

    func startNavigation() {
        navigationState.phase = .navigating
        navigationState.isOffRoute = false
        offRouteStartTime = nil
    }

    func stopNavigation() {
        navigationState.phase = .idle
        navigationState.route = nil
        navigationState.followUpRoute = nil
        navigationState.steps = []
        navigationState.currentStepIndex = 0
        routePolylineCoordinates = []
        sharedRouteCoordinates = []
        estimatedPolylineIndex = 0
        offRouteStartTime = nil
    }

    // MARK: - Location Updates (called each location tick)

    func updateLocation(_ location: CLLocation) {
        guard navigationState.phase == .navigating || navigationState.phase == .rerouting else { return }

        navigationState.currentSpeed = location.speed

        // Check off-route
        let distanceToRoute = distanceFromRoute(location: location)
        checkOffRoute(distance: distanceToRoute)

        // Check step advancement
        checkStepAdvancement(location: location)

        // Update remaining distance/time estimates
        updateEstimates(location: location)
    }

    // MARK: - Off-Route Detection

    private func checkOffRoute(distance: CLLocationDistance) {
        if distance > offRouteThreshold {
            if offRouteStartTime == nil {
                offRouteStartTime = Date()
            } else if let start = offRouteStartTime,
                      Date().timeIntervalSince(start) >= offRouteTimeThreshold {
                if !navigationState.isOffRoute {
                    navigationState.isOffRoute = true
                    navigationState.phase = .rerouting
                    onOffRoute?()
                }
            }
        } else {
            offRouteStartTime = nil
            if navigationState.isOffRoute {
                navigationState.isOffRoute = false
                navigationState.phase = .navigating
            }
        }
    }

    /// Calculates the minimum perpendicular distance from a location to the route polyline.
    func distanceFromRoute(location: CLLocation) -> CLLocationDistance {
        guard routePolylineCoordinates.count >= 2 else { return 0 }

        var minDistance: CLLocationDistance = .greatestFiniteMagnitude
        let point = location.coordinate

        // Only check nearby segments for performance (±10 segments around current progress)
        let searchStart = max(0, estimatedPolylineIndex - 10)
        let searchEnd = min(routePolylineCoordinates.count - 1, estimatedPolylineIndex + 20)

        for i in searchStart..<searchEnd {
            let segStart = routePolylineCoordinates[i]
            let segEnd = routePolylineCoordinates[i + 1]
            let dist = perpendicularDistance(point: point, segStart: segStart, segEnd: segEnd)
            minDistance = min(minDistance, dist)
        }

        return minDistance
    }

    // Internal (not private) purely as a test seam for SquadNavTests.
    var estimatedPolylineIndex: Int = 0

    private func perpendicularDistance(
        point: CLLocationCoordinate2D,
        segStart: CLLocationCoordinate2D,
        segEnd: CLLocationCoordinate2D
    ) -> CLLocationDistance {
        let pointLoc = CLLocation(latitude: point.latitude, longitude: point.longitude)
        let startLoc = CLLocation(latitude: segStart.latitude, longitude: segStart.longitude)
        let endLoc = CLLocation(latitude: segEnd.latitude, longitude: segEnd.longitude)

        let segLength = startLoc.distance(from: endLoc)

        if segLength < 1 {
            return pointLoc.distance(from: startLoc)
        }

        // Project point onto segment
        let dx = endLoc.coordinate.longitude - startLoc.coordinate.longitude
        let dy = endLoc.coordinate.latitude - startLoc.coordinate.latitude
        let px = pointLoc.coordinate.longitude - startLoc.coordinate.longitude
        let py = pointLoc.coordinate.latitude - startLoc.coordinate.latitude

        let t = max(0, min(1, (px * dx + py * dy) / (dx * dx + dy * dy)))

        let projLat = startLoc.coordinate.latitude + t * dy
        let projLng = startLoc.coordinate.longitude + t * dx

        let projLoc = CLLocation(latitude: projLat, longitude: projLng)
        return pointLoc.distance(from: projLoc)
    }

    // MARK: - Step Advancement

    private func checkStepAdvancement(location: CLLocation) {
        guard navigationState.currentStepIndex < navigationState.steps.count else { return }

        let currentStep = navigationState.steps[navigationState.currentStepIndex]

        // Calculate distance to the end of current step
        // MKRoute.Step provides a polyline — use its last point as the maneuver endpoint
        let stepPolyline = currentStep.polyline
        let pointCount = stepPolyline.pointCount
        guard pointCount > 0 else { return }

        var endCoord = CLLocationCoordinate2D()
        stepPolyline.getCoordinates(&endCoord, range: NSRange(location: pointCount - 1, length: 1))

        let endLocation = CLLocation(latitude: endCoord.latitude, longitude: endCoord.longitude)
        let distanceToEnd = location.distance(from: endLocation)

        navigationState.distanceToNextManeuver = distanceToEnd

        if distanceToEnd < stepAdvanceDistance {
            // Advance to next step
            navigationState.currentStepIndex += 1
            onStepAdvanced?(navigationState.currentStepIndex)

            // Check if arrived
            if navigationState.currentStepIndex >= navigationState.steps.count {
                if let followUp = navigationState.followUpRoute {
                    // Connector leg complete: continue onto the shared route.
                    navigationState.route = followUp
                    navigationState.steps = followUp.steps.filter { !$0.instructions.isEmpty }
                    navigationState.currentStepIndex = 0
                    navigationState.followUpRoute = nil
                } else {
                    navigationState.phase = .arrived
                    onArrived?()
                }
            }
        }
    }

    // MARK: - Estimates

    private func updateEstimates(location: CLLocation) {
        guard let route = navigationState.route else { return }

        // Simple estimation based on remaining steps
        let completedSteps = navigationState.currentStepIndex
        let totalSteps = navigationState.steps.count

        if totalSteps > 0 {
            let progress = Double(completedSteps) / Double(totalSteps)
            var distanceRemaining = route.distance * (1.0 - progress)
            var timeRemaining = route.expectedTravelTime * (1.0 - progress)
            if let followUp = navigationState.followUpRoute {
                distanceRemaining += followUp.distance
                timeRemaining += followUp.expectedTravelTime
            }
            navigationState.totalDistanceRemaining = distanceRemaining
            navigationState.estimatedTimeRemaining = timeRemaining
        }

        // Update polyline tracking index
        updatePolylineIndex(location: location)
    }

    private func updatePolylineIndex(location: CLLocation) {
        let searchStart = max(0, estimatedPolylineIndex)
        let searchEnd = min(routePolylineCoordinates.count, estimatedPolylineIndex + 30)

        var minDist: CLLocationDistance = .greatestFiniteMagnitude
        var bestIndex = estimatedPolylineIndex

        for i in searchStart..<searchEnd {
            let coord = routePolylineCoordinates[i]
            let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            let dist = location.distance(from: loc)
            if dist < minDist {
                minDist = dist
                bestIndex = i
            }
        }

        estimatedPolylineIndex = bestIndex
    }
}

// MARK: - Errors

enum NavigationError: LocalizedError {
    case noRouteFound
    case routeCalculationFailed

    var errorDescription: String? {
        switch self {
        case .noRouteFound: return "No route could be found to the destination."
        case .routeCalculationFailed: return "Route calculation failed. Please try again."
        }
    }
}
