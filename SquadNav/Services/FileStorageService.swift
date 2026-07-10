import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import UniformTypeIdentifiers

@MainActor
class FileStorageService: ObservableObject {
    @Published var files: [SharedFile] = []
    @Published var uploadProgress: Double = 0
    @Published var isUploading: Bool = false

    private let db = FirestoreService.shared.db
    private let storage = Storage.storage()
    private var listener: ListenerRegistration?

    deinit {
        listener?.remove()
    }

    // MARK: - Upload

    func uploadFile(
        groupId: String,
        data: Data,
        fileName: String,
        mimeType: String
    ) async throws {
        guard let user = Auth.auth().currentUser else { return }

        isUploading = true
        uploadProgress = 0
        defer {
            isUploading = false
            uploadProgress = 0
        }

        let fileId = UUID().uuidString
        let storagePath = "groups/\(groupId)/files/\(fileId)_\(fileName)"
        let storageRef = storage.reference().child(storagePath)

        let metadata = StorageMetadata()
        metadata.contentType = mimeType

        // Upload with progress
        let uploadTask = storageRef.putData(data, metadata: metadata)

        uploadTask.observe(.progress) { [weak self] snapshot in
            guard let progress = snapshot.progress else { return }
            Task { @MainActor in
                self?.uploadProgress = Double(progress.completedUnitCount) / Double(progress.totalUnitCount)
            }
        }

        _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<StorageMetadata, Error>) in
            uploadTask.observe(.success) { snapshot in
                continuation.resume(returning: snapshot.metadata ?? StorageMetadata())
            }
            uploadTask.observe(.failure) { snapshot in
                continuation.resume(throwing: snapshot.error ?? NSError(domain: "FileStorage", code: -1))
            }
        }

        // Get download URL
        let downloadURL = try await storageRef.downloadURL()

        // Save metadata to Firestore
        let file = SharedFile(
            name: fileName,
            url: downloadURL.absoluteString,
            size: Int64(data.count),
            mimeType: mimeType,
            uploadedBy: user.uid,
            uploadedByName: user.displayName ?? "Driver",
            uploadedAt: Date()
        )

        try db.collection("groups").document(groupId)
            .collection("files")
            .addDocument(from: file)
    }

    // MARK: - Delete

    func deleteFile(groupId: String, file: SharedFile) async throws {
        guard let fileId = file.id else { return }

        // Delete from Firestore
        try await db.collection("groups").document(groupId)
            .collection("files").document(fileId).delete()

        // Delete from Storage
        let storageRef = storage.reference(forURL: file.url)
        try await storageRef.delete()
    }

    // MARK: - Listen

    func listenToFiles(groupId: String) {
        listener?.remove()

        listener = db.collection("groups").document(groupId)
            .collection("files")
            .order(by: "uploadedAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let documents = snapshot?.documents else { return }
                self?.files = documents.compactMap { try? $0.data(as: SharedFile.self) }
            }
    }

    func stopListening() {
        listener?.remove()
        files = []
    }

    // MARK: - Helpers

    static func mimeType(for url: URL) -> String {
        if let utType = UTType(filenameExtension: url.pathExtension) {
            return utType.preferredMIMEType ?? "application/octet-stream"
        }
        return "application/octet-stream"
    }
}
