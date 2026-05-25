import Foundation
import FirebaseFirestore

enum MessageType: String, Codable {
    case text
    case system
    case alert
}

struct Message: Identifiable, Codable, Equatable {
    @DocumentID var id: String?
    var senderId: String
    var senderName: String
    var text: String
    var type: MessageType
    var timestamp: Date

    init(
        id: String? = nil,
        senderId: String,
        senderName: String,
        text: String,
        type: MessageType = .text,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.senderId = senderId
        self.senderName = senderName
        self.text = text
        self.type = type
        self.timestamp = timestamp
    }
}
