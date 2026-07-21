import SwiftUI
import QuickLook

/// QuickLook-backed preview for shared files (photos, PDFs, and anything
/// else QLPreviewController supports). Files download to a temp location
/// first — QLPreviewController needs a local URL.
struct FilePreviewView: UIViewControllerRepresentable {
    let fileURL: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
        uiViewController.reloadData()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(fileURL: fileURL)
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let fileURL: URL

        init(fileURL: URL) {
            self.fileURL = fileURL
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(
            _ controller: QLPreviewController,
            previewItemAt index: Int
        ) -> QLPreviewItem {
            fileURL as QLPreviewItem
        }
    }
}

/// Handles download → temp file → present. Used by FilesView row taps.
@MainActor
final class FilePreviewLoader: ObservableObject {
    @Published var localURL: URL?
    @Published var isLoading = false
    @Published var error: String?

    func load(file: SharedFile) async {
        guard let remoteURL = URL(string: file.url) else {
            error = "Invalid file URL"
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let (data, _) = try await URLSession.shared.data(from: remoteURL)
            // Keep the extension so QuickLook picks the right preview type.
            let ext = (file.name as NSString).pathExtension
            let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("\(file.id ?? UUID().uuidString).\(ext)")
            try data.write(to: tempURL, options: .atomic)
            localURL = tempURL
        } catch {
            self.error = "Couldn't download file: \(error.localizedDescription)"
        }
    }

    func clear() {
        localURL = nil
        error = nil
    }
}
