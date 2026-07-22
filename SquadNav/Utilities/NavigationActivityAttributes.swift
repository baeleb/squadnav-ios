import ActivityKit
import Foundation

struct NavigationActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var instruction: String
        var nextInstruction: String?
        var maneuverIconName: String
        var distanceToManeuverMeters: Double
        var distanceRemainingMeters: Double
        var etaSeconds: TimeInterval
        var isRerouting: Bool
    }

    var destinationName: String
}
