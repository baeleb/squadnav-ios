import Foundation
import FirebaseAuth
import FirebaseFirestore
import CoreImage.CIFilterBuiltins

@MainActor
class GroupService: ObservableObject {
    @Published var userGroups: [Group] = []
    @Published var activeGroup: Group?
    @Published var members: [MemberLocation] = []

    private let db = FirestoreService.shared.db
    private var groupsListener: ListenerRegistration?
    private var activeGroupListener: ListenerRegistration?
    private var membersListener: ListenerRegistration?

    deinit {
        groupsListener?.remove()
        activeGroupListener?.remove()
        membersListener?.remove()
    }

    // MARK: - Group CRUD

    func createGroup(name: String) async throws -> Group {
        guard let userId = Auth.auth().currentUser?.uid,
              let displayName = Auth.auth().currentUser?.displayName else {
            throw GroupError.notAuthenticated
        }

        let inviteCode = try await generateUniqueInviteCode()

        let group = Group(
            name: name,
            inviteCode: inviteCode,
            createdBy: userId,
            isNavigating: false,
            createdAt: Date(),
            memberIds: [userId]
        )

        let docRef = try db.collection("groups").addDocument(from: group)

        // Add creator as leader
        let member = MemberLocation(
            displayName: displayName,
            role: "leader",
            status: .idle,
            currentStepIndex: 0
        )
        try docRef.collection("members").document(userId).setData(from: member)

        var createdGroup = group
        createdGroup.id = docRef.documentID
        return createdGroup
    }

    func joinGroup(inviteCode: String) async throws -> Group {
        guard let userId = Auth.auth().currentUser?.uid,
              let displayName = Auth.auth().currentUser?.displayName else {
            throw GroupError.notAuthenticated
        }

        let code = inviteCode.uppercased().trimmingCharacters(in: .whitespaces)

        let snapshot = try await db.collection("groups")
            .whereField("inviteCode", isEqualTo: code)
            .limit(to: 1)
            .getDocuments()

        guard let doc = snapshot.documents.first else {
            throw GroupError.groupNotFound
        }

        let group = try doc.data(as: Group.self)

        // Check if already a member
        let memberDoc = try await doc.reference.collection("members").document(userId).getDocument()
        if memberDoc.exists {
            throw GroupError.alreadyMember
        }

        // Add as driver
        let member = MemberLocation(
            displayName: displayName,
            role: "driver",
            status: .idle,
            currentStepIndex: 0
        )
        try doc.reference.collection("members").document(userId).setData(from: member)
        try await doc.reference.updateData([
            "memberIds": FieldValue.arrayUnion([userId])
        ])

        return group
    }

    func leaveGroup(groupId: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw GroupError.notAuthenticated
        }

        try await db.collection("groups").document(groupId)
            .collection("members").document(userId).delete()
        try await db.collection("groups").document(groupId).updateData([
            "memberIds": FieldValue.arrayRemove([userId])
        ])

        // Check if any members remain
        let remaining = try await db.collection("groups").document(groupId)
            .collection("members").getDocuments()

        if remaining.documents.isEmpty {
            // Delete group if no members left
            try await db.collection("groups").document(groupId).delete()
        }
    }

    // MARK: - Destination & Route

    func setDestination(
        groupId: String,
        latitude: Double,
        longitude: Double,
        name: String,
        routePolyline: String?
    ) async throws {
        try await db.collection("groups").document(groupId).updateData([
            "destinationLatitude": latitude,
            "destinationLongitude": longitude,
            "destinationName": name,
            "routePolyline": routePolyline as Any
        ])
    }

    func startNavigation(groupId: String) async throws {
        try await db.collection("groups").document(groupId).updateData([
            "isNavigating": true
        ])
    }

    func stopNavigation(groupId: String) async throws {
        try await db.collection("groups").document(groupId).updateData([
            "isNavigating": false
        ])
    }

    // MARK: - Real-Time Listeners

    func listenToUserGroups() {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        // Sorting happens client-side: combining arrayContains with a
        // server-side order(by:) would require a composite index.
        groupsListener = db.collection("groups")
            .whereField("memberIds", arrayContains: userId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let documents = snapshot?.documents else { return }
                self?.userGroups = documents
                    .compactMap { try? $0.data(as: Group.self) }
                    .sorted { $0.createdAt > $1.createdAt }
            }
    }

    func listenToGroup(groupId: String) {
        activeGroupListener?.remove()
        activeGroupListener = db.collection("groups").document(groupId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let snapshot, snapshot.exists else { return }
                self?.activeGroup = try? snapshot.data(as: Group.self)
            }
    }

    func listenToMembers(groupId: String) {
        membersListener?.remove()
        membersListener = db.collection("groups").document(groupId).collection("members")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let documents = snapshot?.documents else { return }
                self?.members = documents.compactMap { try? $0.data(as: MemberLocation.self) }
            }
    }

    func stopListeningToGroup() {
        activeGroupListener?.remove()
        membersListener?.remove()
        activeGroup = nil
        members = []
    }

    // MARK: - Update Member Location

    func updateMemberLocation(
        groupId: String,
        latitude: Double,
        longitude: Double,
        heading: Double,
        speed: Double,
        status: DriverStatus,
        stepIndex: Int
    ) async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        try await db.collection("groups").document(groupId)
            .collection("members").document(userId)
            .updateData([
                "latitude": latitude,
                "longitude": longitude,
                "heading": heading,
                "speed": speed,
                "lastUpdated": FieldValue.serverTimestamp(),
                "status": status.rawValue,
                "currentStepIndex": stepIndex
            ])
    }

    /// Updates only the status field of another member's document
    /// (used by the caravan monitor, which evaluates members other than
    /// the current user).
    func updateMemberStatus(
        groupId: String,
        memberId: String,
        status: DriverStatus
    ) async throws {
        try await db.collection("groups").document(groupId)
            .collection("members").document(memberId)
            .updateData(["status": status.rawValue])
    }

    // MARK: - QR Code Generation

    func generateQRCode(for inviteCode: String) -> Data? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        let data = Data("squadnav://join/\(inviteCode)".utf8)
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")

        guard let outputImage = filter.outputImage else { return nil }

        let transform = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = outputImage.transformed(by: transform)

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }

        let uiImage = UIImage(cgImage: cgImage)
        return uiImage.pngData()
    }

    // MARK: - Private Helpers

    private func generateUniqueInviteCode() async throws -> String {
        var code: String
        var attempts = 0

        repeat {
            code = generateInviteCode()
            let snapshot = try await db.collection("groups")
                .whereField("inviteCode", isEqualTo: code)
                .limit(to: 1)
                .getDocuments()

            if snapshot.documents.isEmpty {
                return code
            }
            attempts += 1
        } while attempts < 10

        throw GroupError.codeGenerationFailed
    }

    private func generateInviteCode() -> String {
        let chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" // No O/0/I/1 for readability
        return String((0..<6).map { _ in chars.randomElement()! })
    }
}

// MARK: - Errors

enum GroupError: LocalizedError {
    case notAuthenticated
    case groupNotFound
    case alreadyMember
    case codeGenerationFailed

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "You must be signed in."
        case .groupNotFound: return "No group found with that invite code."
        case .alreadyMember: return "You're already a member of this group."
        case .codeGenerationFailed: return "Could not generate a unique invite code. Please try again."
        }
    }
}
