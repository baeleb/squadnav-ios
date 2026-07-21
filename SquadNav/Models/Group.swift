import Foundation
import FirebaseFirestore

struct Group: Identifiable, Codable, Equatable, Hashable {
    @DocumentID var id: String?
    var name: String
    var inviteCode: String
    var createdBy: String
    var destinationLatitude: Double?
    var destinationLongitude: Double?
    var destinationName: String?
    var routePolyline: String?
    var isNavigating: Bool
    var createdAt: Date
    // Server-set on every startNavigation; the cleanupGroups Cloud
    // Function deletes groups with no navigation in the last 14 days.
    // Optional: groups created before this field lack it (falls back to
    // createdAt server-side). Plain Date? — @ServerTimestamp would fail
    // decode on absent keys.
    var lastNavigatedAt: Date?
    // Optional for backward compatibility: groups created before the
    // membership-query refactor don't have this field in Firestore.
    var memberIds: [String]?

    var hasDestination: Bool {
        destinationLatitude != nil && destinationLongitude != nil
    }

    init(
        id: String? = nil,
        name: String,
        inviteCode: String,
        createdBy: String,
        destinationLatitude: Double? = nil,
        destinationLongitude: Double? = nil,
        destinationName: String? = nil,
        routePolyline: String? = nil,
        isNavigating: Bool = false,
        createdAt: Date = Date(),
        lastNavigatedAt: Date? = nil,
        memberIds: [String]? = nil
    ) {
        self.id = id
        self.name = name
        self.inviteCode = inviteCode
        self.createdBy = createdBy
        self.destinationLatitude = destinationLatitude
        self.destinationLongitude = destinationLongitude
        self.destinationName = destinationName
        self.routePolyline = routePolyline
        self.isNavigating = isNavigating
        self.createdAt = createdAt
        self.lastNavigatedAt = lastNavigatedAt
        self.memberIds = memberIds
    }
}
