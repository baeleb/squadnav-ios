import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
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

        // Add creator as leader. Dictionary write (not Codable): joinedAt
        // needs an explicit serverTimestamp — a plain Date? model field
        // would encode nil as "key omitted".
        try await docRef.collection("members").document(userId).setData([
            "displayName": displayName,
            "role": "leader",
            "latitude": 0.0,
            "longitude": 0.0,
            "heading": 0.0,
            "speed": 0.0,
            "lastUpdated": FieldValue.serverTimestamp(),
            "joinedAt": FieldValue.serverTimestamp(),
            "status": DriverStatus.idle.rawValue,
            "currentStepIndex": 0
        ])

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

        // Add as driver (dictionary write — see createGroup for why)
        try await doc.reference.collection("members").document(userId).setData([
            "displayName": displayName,
            "role": "driver",
            "latitude": 0.0,
            "longitude": 0.0,
            "heading": 0.0,
            "speed": 0.0,
            "lastUpdated": FieldValue.serverTimestamp(),
            "joinedAt": FieldValue.serverTimestamp(),
            "status": DriverStatus.idle.rawValue,
            "currentStepIndex": 0
        ])
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

    // MARK: - Delete Group (leader)

    /// Deletes a group for everyone: Storage blobs, then members/messages/
    /// files subcollection docs, then the group doc itself. Best-effort —
    /// a failure partway leaves orphans that the cleanupGroups Cloud
    /// Function sweeps on its next daily run.
    func deleteGroup(groupId: String) async throws {
        guard Auth.auth().currentUser?.uid != nil else {
            throw GroupError.notAuthenticated
        }

        let groupRef = db.collection("groups").document(groupId)

        // 1. Storage blobs (need file docs for URLs before deleting them)
        let fileDocs = try await groupRef.collection("files").getDocuments()
        for doc in fileDocs.documents {
            if let file = try? doc.data(as: SharedFile.self) {
                try? await Storage.storage().reference(forURL: file.url).delete()
            }
        }

        // 2. Subcollections
        for subcollection in ["members", "messages", "files"] {
            let docs = try await groupRef.collection(subcollection).getDocuments()
            for doc in docs.documents {
                try await doc.reference.delete()
            }
        }

        // 3. Group doc
        try await groupRef.delete()
    }

    // MARK: - Leadership Succession

    /// How long the leader's location may be stale before the group is
    /// considered leaderless (involuntary leave: crash, connection loss).
    static let leaderStalenessThreshold: TimeInterval = 180

    /// Voluntary handoff: current leader promotes another member, then
    /// typically leaves. Two writes (not atomic — acceptable: a crash
    /// between them is covered by the involuntary-claim path).
    func transferLeadership(groupId: String, newLeaderId: String) async throws {
        guard Auth.auth().currentUser?.uid != nil else {
            throw GroupError.notAuthenticated
        }
        let groupRef = db.collection("groups").document(groupId)
        let oldLeaderId = try await groupRef.getDocument().data()?["createdBy"] as? String

        // Role write first: rules only let the CURRENT leader write
        // `role` on another member's doc — after the createdBy write
        // the caller is no longer leader and would be denied.
        try await groupRef.collection("members").document(newLeaderId)
            .updateData(["role": "leader"])
        try await groupRef.updateData(["createdBy": newLeaderId])

        // Demote the old leader's role, or the members list shows two
        // leaders (createdBy moved, but their role stayed "leader").
        // After the createdBy write the new leader holds role-write
        // permission, so this also works on the involuntary-claim path.
        // try?: old leader's doc may already be gone (voluntary leave).
        if let oldLeaderId, oldLeaderId != newLeaderId {
            try? await groupRef.collection("members").document(oldLeaderId)
                .updateData(["role": "driver"])
        }
    }

    /// Involuntary handoff: if the leader's member doc is missing (left
    /// without transfer — e.g. older app version) or stale (crashed /
    /// lost connection), the earliest-joined remaining member claims
    /// leadership by writing createdBy to themselves.
    func claimLeadershipIfNeeded(groupId: String) async {
        guard let userId = Auth.auth().currentUser?.uid,
              let group = activeGroup,
              group.createdBy != userId else { return }

        let leaderDoc = members.first { $0.id == group.createdBy }
        let leaderIsGone: Bool
        if let leaderDoc {
            // Missing lastUpdated (old doc) counts as stale.
            leaderIsGone = leaderDoc.lastUpdated
                .map { Date().timeIntervalSince($0) > Self.leaderStalenessThreshold } ?? true
        } else {
            leaderIsGone = true
        }
        guard leaderIsGone else { return }

        guard Self.firstJoinedMemberId(members: members) == userId else { return }

        try? await transferLeadership(groupId: groupId, newLeaderId: userId)
    }

    /// Earliest-joined member wins; members without joinedAt (pre-field
    /// docs) sort last so they never outrank timestamped members.
    static func firstJoinedMemberId(members: [MemberLocation]) -> String? {
        members
            .filter { $0.id != nil }
            .sorted { ($0.joinedAt ?? .distantFuture) < ($1.joinedAt ?? .distantFuture) }
            .first?.id ?? nil
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

    /// Clears the shared destination + route (leader only, enforced by
    /// rules: only createdBy can update these fields).
    func clearDestination(groupId: String) async throws {
        try await db.collection("groups").document(groupId).updateData([
            "destinationLatitude": FieldValue.delete(),
            "destinationLongitude": FieldValue.delete(),
            "destinationName": FieldValue.delete(),
            "routePolyline": FieldValue.delete()
        ])
    }

    func startNavigation(groupId: String) async throws {
        try await db.collection("groups").document(groupId).updateData([
            "isNavigating": true,
            // Activity signal for the cleanupGroups Cloud Function
            // (14-day nav-stale deletion).
            "lastNavigatedAt": FieldValue.serverTimestamp()
        ])
    }

    func stopNavigation(groupId: String) async throws {
        try await db.collection("groups").document(groupId).updateData([
            "isNavigating": false
        ])
    }

    // MARK: - Presence Heartbeat

    private var presenceTimer: Timer?

    /// While a member has the group screen open, touch their member doc's
    /// lastUpdated every 60s. This makes the leadership-staleness check
    /// meaningful: without it, an online-but-not-navigating leader never
    /// uploads and would look "gone" after a few minutes.
    func startPresence(groupId: String) {
        stopPresence()
        writePresence(groupId: groupId)
        presenceTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.writePresence(groupId: groupId) }
        }
    }

    func stopPresence() {
        presenceTimer?.invalidate()
        presenceTimer = nil
    }

    private func writePresence(groupId: String) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        Task {
            try? await db.collection("groups").document(groupId)
                .collection("members").document(userId)
                .updateData(["lastUpdated": FieldValue.serverTimestamp()])
        }
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
                guard let self, let documents = snapshot?.documents else { return }
                self.members = documents.compactMap { try? $0.data(as: MemberLocation.self) }
                // Every membership/location refresh is a chance to notice a
                // leaderless group and claim it (involuntary succession).
                Task { await self.claimLeadershipIfNeeded(groupId: groupId) }
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
