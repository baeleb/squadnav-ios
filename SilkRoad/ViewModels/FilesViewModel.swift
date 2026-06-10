import Foundation
import Combine
import PhotosUI
import SwiftUI
import FirebaseAuth

@MainActor
class FilesViewModel: ObservableObject {
    @Published var selectedItems: [PhotosPickerItem] = []
    @Published var error: String?

    let fileService: FileStorageService
    let groupId: String

    private var cancellables: Set<AnyCancellable> = []

    init(fileService: FileStorageService, groupId: String) {
        self.fileService = fileService
        self.groupId = groupId

        // Forward nested service changes so views observing this view model update.
        fileService.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func uploadSelectedPhotos() async {
        for item in selectedItems {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }

                let mimeType: String
                let fileName: String

                if let contentType = item.supportedContentTypes.first {
                    mimeType = contentType.preferredMIMEType ?? "application/octet-stream"
                    let ext = contentType.preferredFilenameExtension ?? "bin"
                    fileName = "photo_\(UUID().uuidString.prefix(8)).\(ext)"
                } else {
                    mimeType = "image/jpeg"
                    fileName = "photo_\(UUID().uuidString.prefix(8)).jpg"
                }

                try await fileService.uploadFile(
                    groupId: groupId,
                    data: data,
                    fileName: fileName,
                    mimeType: mimeType
                )
            } catch {
                self.error = error.localizedDescription
            }
        }
        selectedItems = []
    }

    func uploadFileData(_ data: Data, fileName: String, mimeType: String) async {
        do {
            try await fileService.uploadFile(
                groupId: groupId,
                data: data,
                fileName: fileName,
                mimeType: mimeType
            )
        } catch {
            self.error = error.localizedDescription
        }
    }

    func deleteFile(_ file: SharedFile) async {
        do {
            try await fileService.deleteFile(groupId: groupId, file: file)
        } catch {
            self.error = error.localizedDescription
        }
    }

    var canDelete: Bool {
        Auth.auth().currentUser?.uid != nil
    }

    func canDeleteFile(_ file: SharedFile) -> Bool {
        guard let userId = Auth.auth().currentUser?.uid else { return false }
        return file.uploadedBy == userId
    }
}
