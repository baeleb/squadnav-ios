import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
class ChatService: ObservableObject {
    @Published var messages: [Message] = []

    private let db = FirestoreService.shared.db
    private var listener: ListenerRegistration?

    deinit {
        listener?.remove()
    }

    // MARK: - Send Messages

    func sendMessage(groupId: String, text: String) async throws {
        guard let user = Auth.auth().currentUser else { return }

        let message = Message(
            senderId: user.uid,
            senderName: user.displayName ?? "Driver",
            text: text,
            type: .text,
            timestamp: Date()
        )

        try db.collection("groups").document(groupId)
            .collection("messages")
            .addDocument(from: message)
    }

    func sendSystemAlert(groupId: String, text: String) async throws {
        let message = Message(
            senderId: "system",
            senderName: "Silk Road",
            text: text,
            type: .alert,
            timestamp: Date()
        )

        try db.collection("groups").document(groupId)
            .collection("messages")
            .addDocument(from: message)
    }

    func sendSystemMessage(groupId: String, text: String) async throws {
        let message = Message(
            senderId: "system",
            senderName: "Silk Road",
            text: text,
            type: .system,
            timestamp: Date()
        )

        try db.collection("groups").document(groupId)
            .collection("messages")
            .addDocument(from: message)
    }

    // MARK: - Listen

    func listenToMessages(groupId: String) {
        listener?.remove()

        listener = db.collection("groups").document(groupId)
            .collection("messages")
            .order(by: "timestamp", descending: false)
            .limit(toLast: 200)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let documents = snapshot?.documents else { return }
                self?.messages = documents.compactMap { try? $0.data(as: Message.self) }
            }
    }

    func stopListening() {
        listener?.remove()
        messages = []
    }
}
