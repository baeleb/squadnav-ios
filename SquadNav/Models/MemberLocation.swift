import Foundation
import FirebaseFirestore
import CoreLocation

enum DriverStatus: String, Codable {
    case onRoute = "on_route"
    case offRoute = "off_route"
    case behind = "behind"
    case stopped = "stopped"
    case idle = "idle"
    case rerouting = "rerouting"

    var displayLabel: String {
        switch self {
        case .onRoute: return "On Route"
        case .offRoute: return "Off Route"
        case .behind: return "Behind"
        case .stopped: return "Stopped"
        case .idle: return "Idle"
        case .rerouting: return "Rerouting"
        }
    }

    var iconSystemName: String {
        switch self {
        case .onRoute: return "checkmark.circle.fill"
        case .offRoute: return "exclamationmark.triangle.fill"
        case .behind: return "tortoise.fill"
        case .stopped: return "pause.circle.fill"
        case .idle: return "circle.fill"
        case .rerouting: return "arrow.triangle.turn.up.right.circle.fill"
        }
    }

    // Flock palette — status color, independent of member identity color (see AppTheme.memberColor).
    var colorHex: String {
        switch self {
        case .onRoute: return "4E9A9B"
        case .offRoute: return "E2603A"
        case .behind: return "D9642F"
        case .stopped: return "D2A03D"
        case .idle: return "B3A48C"
        case .rerouting: return "F2894C"
        }
    }
}

struct MemberLocation: Identifiable, Codable, Equatable {
    @DocumentID var id: String?
    var displayName: String
    var role: String
    var latitude: Double
    var longitude: Double
    var heading: Double
    var speed: Double
    // Server timestamps are null in latency-compensated local snapshots;
    // a non-optional Date would fail to decode and drop the member row.
    @ServerTimestamp var lastUpdated: Date?
    // Server-set at member-doc creation. Must be @ServerTimestamp:
    // pending sentinels in latency-compensated snapshots fail plain
    // Date? decode and drop the doc from compactMap listeners — which
    // made claimLeadershipIfNeeded false-trigger.
    @ServerTimestamp var joinedAt: Date?
    var status: DriverStatus
    var currentStepIndex: Int

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var isLeader: Bool {
        role == "leader"
    }

    var formattedSpeed: String {
        // CLLocation.speed is -1 when invalid; never show negative mph.
        let mph = max(0, speed) * 2.237
        return "\(Int(mph)) mph"
    }

    init(
        id: String? = nil,
        displayName: String,
        role: String = "driver",
        latitude: Double = 0,
        longitude: Double = 0,
        heading: Double = 0,
        speed: Double = 0,
        lastUpdated: Date? = nil,
        joinedAt: Date? = nil,
        status: DriverStatus = .idle,
        currentStepIndex: Int = 0
    ) {
        self.id = id
        self.displayName = displayName
        self.role = role
        self.latitude = latitude
        self.longitude = longitude
        self.heading = heading
        self.speed = speed
        self.lastUpdated = lastUpdated
        self.joinedAt = joinedAt
        self.status = status
        self.currentStepIndex = currentStepIndex
    }
}
