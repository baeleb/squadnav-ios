import Foundation
import FirebaseFirestore

struct SharedFile: Identifiable, Codable, Equatable {
    @DocumentID var id: String?
    var name: String
    var url: String
    var size: Int64
    var mimeType: String
    var uploadedBy: String
    var uploadedByName: String
    var uploadedAt: Date

    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    var iconSystemName: String {
        if mimeType.hasPrefix("image/") { return "photo.fill" }
        if mimeType.hasPrefix("video/") { return "video.fill" }
        if mimeType.contains("pdf") { return "doc.fill" }
        if mimeType.contains("text") { return "doc.text.fill" }
        if mimeType.contains("spreadsheet") || mimeType.contains("csv") { return "tablecells.fill" }
        if mimeType.contains("presentation") { return "rectangle.fill.on.rectangle.fill" }
        return "doc.fill"
    }

    init(
        id: String? = nil,
        name: String,
        url: String,
        size: Int64,
        mimeType: String = "application/octet-stream",
        uploadedBy: String,
        uploadedByName: String,
        uploadedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.size = size
        self.mimeType = mimeType
        self.uploadedBy = uploadedBy
        self.uploadedByName = uploadedByName
        self.uploadedAt = uploadedAt
    }
}
