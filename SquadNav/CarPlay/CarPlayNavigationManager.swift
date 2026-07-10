import CarPlay
import MapKit

/// Bridges the NavigationService's turn-by-turn data to CarPlay's CPNavigationSession.
class CarPlayNavigationManager {
    private weak var mapTemplate: CPMapTemplate?
    private weak var mapController: CarPlayMapController?
    private var navigationSession: CPNavigationSession?

    init(mapTemplate: CPMapTemplate, mapController: CarPlayMapController) {
        self.mapTemplate = mapTemplate
        self.mapController = mapController
    }

    // MARK: - Navigation Lifecycle

    func startNavigation(session: CPNavigationSession) {
        self.navigationSession = session
    }

    func stopNavigation() {
        navigationSession?.finishTrip()
        navigationSession = nil
    }

    // MARK: - Update from NavigationService

    /// Call this when the NavigationService advances a step or updates state.
    func updateManeuvers(from state: NavigationState) {
        guard let session = navigationSession else { return }

        var maneuvers: [CPManeuver] = []

        // Current maneuver
        if let currentStep = state.currentStep {
            let maneuver = createManeuver(
                instruction: currentStep.instructions,
                distance: state.distanceToNextManeuver
            )
            maneuvers.append(maneuver)
        }

        // Next maneuver
        if let nextStep = state.nextStep {
            let maneuver = createManeuver(
                instruction: nextStep.instructions,
                distance: nextStep.distance
            )
            maneuvers.append(maneuver)
        }

        session.upcomingManeuvers = maneuvers

        // Update estimates for first maneuver
        if let firstManeuver = maneuvers.first {
            let estimates = CPTravelEstimates(
                distanceRemaining: Measurement(
                    value: state.distanceToNextManeuver,
                    unit: UnitLength.meters
                ),
                timeRemaining: state.estimatedTimeRemaining
            )
            session.updateEstimates(estimates, for: firstManeuver)
        }
    }

    /// Handle off-route / rerouting state.
    func handleRerouting() {
        navigationSession?.pauseTrip(for: .rerouting, description: "Recalculating route...")
    }

    func handleRerouteComplete() {
        // Trip is automatically resumed by updating maneuvers
    }

    func handleArrival() {
        navigationSession?.finishTrip()
    }

    // MARK: - Create Trip

    /// Creates a CPTrip for the destination to present on CarPlay.
    func createTrip(
        destination: CLLocationCoordinate2D,
        destinationName: String,
        route: MKRoute
    ) -> CPTrip {
        let placemark = MKPlacemark(coordinate: destination)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = destinationName

        let routeChoice = CPRouteChoice(
            summaryVariants: [route.name],
            additionalInformationVariants: [
                "\(MKDistanceFormatter().string(fromDistance: route.distance)) • \(formattedTime(route.expectedTravelTime))"
            ],
            selectionSummaryVariants: ["Via \(route.name)"]
        )

        let trip = CPTrip(
            origin: MKMapItem.forCurrentLocation(),
            destination: mapItem,
            routeChoices: [routeChoice]
        )

        return trip
    }

    /// Presents a trip preview on the map template.
    func presentTripPreview(trip: CPTrip) {
        mapTemplate?.showTripPreviews([trip], textConfiguration: nil)
    }

    // MARK: - Private Helpers

    private func createManeuver(instruction: String, distance: CLLocationDistance) -> CPManeuver {
        let maneuver = CPManeuver()
        maneuver.instructionVariants = [instruction]

        // Set appropriate symbol
        if let symbolImage = maneuverSymbolImage(for: instruction) {
            maneuver.symbolImage = symbolImage
        }

        // Set initial travel estimates
        let estimates = CPTravelEstimates(
            distanceRemaining: Measurement(value: distance, unit: UnitLength.meters),
            timeRemaining: distance / 13.4 // Rough estimate at ~30mph
        )
        maneuver.initialTravelEstimates = estimates

        return maneuver
    }

    private func maneuverSymbolImage(for instruction: String) -> UIImage? {
        let lower = instruction.lowercased()

        let symbolName: String
        if lower.contains("right") {
            symbolName = "arrow.turn.up.right"
        } else if lower.contains("left") {
            symbolName = "arrow.turn.up.left"
        } else if lower.contains("u-turn") || lower.contains("u turn") {
            symbolName = "arrow.uturn.down"
        } else if lower.contains("merge") {
            symbolName = "arrow.merge"
        } else if lower.contains("exit") || lower.contains("ramp") {
            symbolName = "arrow.up.right"
        } else if lower.contains("arrive") || lower.contains("destination") {
            symbolName = "flag.checkered"
        } else {
            symbolName = "arrow.up"
        }

        return UIImage(systemName: symbolName)?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 24, weight: .bold))
    }

    private func formattedTime(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: seconds) ?? "--"
    }
}
