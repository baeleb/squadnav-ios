import Foundation
import MapKit

/// Represents the current state of the turn-by-turn navigation engine.
struct NavigationState: Equatable {
    enum Phase: Equatable {
        case idle
        case calculatingRoute
        case navigating
        case rerouting
        case arrived
        case error(String)
    }

    var phase: Phase = .idle
    var route: MKRoute?
    // Shared-route remainder, swapped in when a connector leg completes.
    var followUpRoute: MKRoute?
    var steps: [MKRoute.Step] = []
    var currentStepIndex: Int = 0
    var distanceToNextManeuver: CLLocationDistance = 0
    var totalDistanceRemaining: CLLocationDistance = 0
    var estimatedTimeRemaining: TimeInterval = 0
    var currentSpeed: CLLocationSpeed = 0
    var isOffRoute: Bool = false

    var currentStep: MKRoute.Step? {
        guard currentStepIndex < steps.count else { return nil }
        return steps[currentStepIndex]
    }

    var nextStep: MKRoute.Step? {
        let next = currentStepIndex + 1
        guard next < steps.count else { return nil }
        return steps[next]
    }

    var currentInstruction: String {
        currentStep?.instructions ?? "Proceed to route"
    }

    var nextInstruction: String? {
        nextStep?.instructions
    }

    var formattedETA: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: estimatedTimeRemaining) ?? "--"
    }

    var formattedDistance: String {
        let formatter = MKDistanceFormatter()
        formatter.unitStyle = .abbreviated
        return formatter.string(fromDistance: totalDistanceRemaining)
    }

    var formattedManeuverDistance: String {
        let formatter = MKDistanceFormatter()
        formatter.unitStyle = .abbreviated
        return formatter.string(fromDistance: distanceToNextManeuver)
    }

    static func == (lhs: NavigationState, rhs: NavigationState) -> Bool {
        lhs.phase == rhs.phase &&
        lhs.currentStepIndex == rhs.currentStepIndex &&
        lhs.isOffRoute == rhs.isOffRoute &&
        Int(lhs.distanceToNextManeuver) == Int(rhs.distanceToNextManeuver)
    }
}
