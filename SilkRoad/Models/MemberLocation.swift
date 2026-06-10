import Foundation
import FirebaseFirestore
import CoreLocation

enum DriverStatus: String, Codable {
    case onRoute = "on_route"
    case offRoute = "off_route"
    case behind = "behind"
    case stopped = "stopped"
    case idle = "idle"

    var displayLabel: String {
        switch self {
        case .onRoute: return "On Route"
        case .offRoute: return "Off Route"
        case .behind: return "Behind"
        case .stopped: return "Stopped"
        case .idle: return "Idle"
        }
    }

    var iconSystemName: String {
        switch self {
        case .onRoute: return "checkmark.circle.fill"
        case .offRoute: return "exclamationmark.triangle.fill"
        case .behind: return "tortoise.fill"
        case .stopped: return "pause.circle.fill"
        case .idle: return "circle.fill"
        }
    }

    var colorHex: String {
        switch self {
        case .onRoute: return "34C759"
        case .offRoute: return "FF3B30"
        case .behind: return "FF9500"
        case .stopped: return "FFCC00"
        case .idle: return "8E8E93"
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
    var status: DriverStatus
    var currentStepIndex: Int

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var isLeader: Bool {
        role == "leader"
    }

    var formattedSpeed: String {
        let mph = speed * 2.237
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
        self.status = status
        self.currentStepIndex = currentStepIndex
    }
}
