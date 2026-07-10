import Foundation
import CoreLocation
import FirebaseAuth

/// Monitors all caravan members' positions relative to the shared route
/// and generates alerts when someone deviates, falls behind, or stops.
@MainActor
class CaravanMonitorService: ObservableObject {
    @Published var memberStatuses: [String: DriverStatus] = [:] // userId -> status
    @Published var alerts: [CaravanAlert] = []

    private var routeCoordinates: [CLLocationCoordinate2D] = []
    private var stoppedTimers: [String: Date] = [:] // userId -> when they stopped

    private let offRouteThreshold: CLLocationDistance = 100
    private let behindDistanceThreshold: CLLocationDistance = 2000  // 2km
    private let behindStepThreshold: Int = 3
    private let stoppedSpeedThreshold: Double = 1.4  // m/s (~5 km/h)
    private let stoppedTimeThreshold: TimeInterval = 60

    private let groupService: GroupService
    private let chatService: ChatService

    init(groupService: GroupService, chatService: ChatService) {
        self.groupService = groupService
        self.chatService = chatService
    }

    func setRoute(coordinates: [CLLocationCoordinate2D]) {
        self.routeCoordinates = coordinates
    }

    /// Called periodically to evaluate all members' statuses.
    func evaluateMembers(
        members: [MemberLocation],
        leaderLocation: MemberLocation?,
        groupId: String
    ) async {
        guard !routeCoordinates.isEmpty else { return }

        let currentUserId = Auth.auth().currentUser?.uid

        for member in members {
            guard let memberId = member.id, memberId != currentUserId else { continue }

            let previousStatus = memberStatuses[memberId]
            let newStatus = evaluateMemberStatus(member: member, leader: leaderLocation)

            memberStatuses[memberId] = newStatus

            // Send alert if status changed to a problematic state
            if newStatus != previousStatus && newStatus != .onRoute && newStatus != .idle {
                let alert = CaravanAlert(
                    memberId: memberId,
                    memberName: member.displayName,
                    status: newStatus,
                    timestamp: Date()
                )
                alerts.append(alert)

                // Send system alert to group chat
                let alertText = alertMessage(for: newStatus, memberName: member.displayName)
                try? await chatService.sendSystemAlert(groupId: groupId, text: alertText)

                // Update that member's status in Firestore
                try? await groupService.updateMemberStatus(
                    groupId: groupId,
                    memberId: memberId,
                    status: newStatus
                )
            }
        }
    }

    private func evaluateMemberStatus(
        member: MemberLocation,
        leader: MemberLocation?
    ) -> DriverStatus {
        let memberLocation = CLLocation(latitude: member.latitude, longitude: member.longitude)

        // 1. Check if off-route
        let distanceToRoute = calculateDistanceToRoute(location: memberLocation)
        if distanceToRoute > offRouteThreshold {
            return .offRoute
        }

        // 2. Check if stopped
        if member.speed < stoppedSpeedThreshold {
            if let stopStart = stoppedTimers[member.id ?? ""] {
                if Date().timeIntervalSince(stopStart) > stoppedTimeThreshold {
                    return .stopped
                }
            } else {
                stoppedTimers[member.id ?? ""] = Date()
            }
        } else {
            stoppedTimers[member.id ?? ""] = nil
        }

        // 3. Check if falling behind the leader
        if let leader = leader {
            let leaderLocation = CLLocation(latitude: leader.latitude, longitude: leader.longitude)
            let distanceBehind = memberLocation.distance(from: leaderLocation)

            if distanceBehind > behindDistanceThreshold ||
               (leader.currentStepIndex - member.currentStepIndex) > behindStepThreshold {
                return .behind
            }
        }

        return .onRoute
    }

    private func calculateDistanceToRoute(location: CLLocation) -> CLLocationDistance {
        guard routeCoordinates.count >= 2 else { return 0 }

        var minDistance: CLLocationDistance = .greatestFiniteMagnitude

        for i in 0..<(routeCoordinates.count - 1) {
            let dist = perpendicularDistance(
                point: location.coordinate,
                segStart: routeCoordinates[i],
                segEnd: routeCoordinates[i + 1]
            )
            minDistance = min(minDistance, dist)
        }

        return minDistance
    }

    private func perpendicularDistance(
        point: CLLocationCoordinate2D,
        segStart: CLLocationCoordinate2D,
        segEnd: CLLocationCoordinate2D
    ) -> CLLocationDistance {
        let pointLoc = CLLocation(latitude: point.latitude, longitude: point.longitude)
        let startLoc = CLLocation(latitude: segStart.latitude, longitude: segStart.longitude)
        let endLoc = CLLocation(latitude: segEnd.latitude, longitude: segEnd.longitude)

        let segLength = startLoc.distance(from: endLoc)
        if segLength < 1 { return pointLoc.distance(from: startLoc) }

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

    private func alertMessage(for status: DriverStatus, memberName: String) -> String {
        switch status {
        case .offRoute:
            return "⚠️ \(memberName)'s car has left the route!"
        case .behind:
            return "🐢 \(memberName) is falling behind the caravan."
        case .stopped:
            return "🛑 \(memberName) has stopped moving."
        default:
            return "ℹ️ \(memberName) status changed to \(status.displayLabel)."
        }
    }

    func clearAlerts() {
        alerts = []
    }
}

// MARK: - Alert Model

struct CaravanAlert: Identifiable, Equatable {
    let id = UUID()
    let memberId: String
    let memberName: String
    let status: DriverStatus
    let timestamp: Date

    static func == (lhs: CaravanAlert, rhs: CaravanAlert) -> Bool {
        lhs.id == rhs.id
    }
}
