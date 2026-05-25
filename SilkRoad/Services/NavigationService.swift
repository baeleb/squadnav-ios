import Foundation
import MapKit
import CoreLocation
import Combine

@MainActor
class NavigationService: ObservableObject {
    @Published var navigationState = NavigationState()
    @Published var routePolylineCoordinates: [CLLocationCoordinate2D] = []

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
        navigationState.steps = route.steps.filter { !$0.instructions.isEmpty }
        navigationState.currentStepIndex = 0
        navigationState.totalDistanceRemaining = route.distance
        navigationState.estimatedTimeRemaining = route.expectedTravelTime

        // Extract polyline coordinates
        let pointCount = route.polyline.pointCount
        var coords = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: pointCount)
        route.polyline.getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        routePolylineCoordinates = coords
    }

    /// Sets route from an encoded polyline string (for non-leader drivers).
    func setRouteFromPolyline(_ encodedPolyline: String, destination: CLLocationCoordinate2D) async throws {
        let coordinates = RouteEncoder.decode(polyline: encodedPolyline)
        routePolylineCoordinates = coordinates

        // Still need to calculate the actual MKRoute for step data
        guard let firstCoord = coordinates.first else {
            throw NavigationError.noRouteFound
        }

        let route = try await calculateRoute(from: firstCoord, to: destination)
        setRoute(route)
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
        navigationState.steps = []
        navigationState.currentStepIndex = 0
        routePolylineCoordinates = []
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

    private var estimatedPolylineIndex: Int = 0

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
                navigationState.phase = .arrived
                onArrived?()
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
            navigationState.totalDistanceRemaining = route.distance * (1.0 - progress)
            navigationState.estimatedTimeRemaining = route.expectedTravelTime * (1.0 - progress)
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
