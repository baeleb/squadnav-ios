import SwiftUI
import PhotosUI

struct FilesView: View {
    @StateObject private var viewModel: FilesViewModel
    @StateObject private var previewLoader = FilePreviewLoader()
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var showDocumentPicker = false

    init(fileService: FileStorageService, groupId: String) {
        self._viewModel = StateObject(wrappedValue: FilesViewModel(
            fileService: fileService,
            groupId: groupId
        ))
    }

    var body: some View {
        ZStack {
            AppTheme.backgroundDark

            VStack(spacing: 0) {
                // Upload bar
                uploadBar

                if viewModel.fileService.files.isEmpty {
                    emptyState
                } else {
                    filesList
                }
            }

            // Upload progress overlay
            if viewModel.fileService.isUploading {
                uploadProgressOverlay
            }
        }
        // Document picker (was previously never presented — dead button)
        .fileImporter(
            isPresented: $showDocumentPicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let didAccess = url.startAccessingSecurityScopedResource()
                defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
                do {
                    let data = try Data(contentsOf: url)
                    let fileName = url.lastPathComponent
                    let mimeType = FileStorageService.mimeType(for: url)
                    Task { await viewModel.uploadFileData(data, fileName: fileName, mimeType: mimeType) }
                } catch {
                    viewModel.error = "Couldn't read file: \(error.localizedDescription)"
                }
            case .failure(let error):
                viewModel.error = error.localizedDescription
            }
        }
        // Upload errors were previously swallowed into an unread property.
        .alert(
            "File Error",
            isPresented: Binding(
                get: { viewModel.error != nil },
                set: { if !$0 { viewModel.error = nil } }
            )
        ) {
            Button("OK") { viewModel.error = nil }
        } message: {
            Text(viewModel.error ?? "")
        }
        // Preview sheet (photos, PDFs, anything QuickLook supports)
        .sheet(
            isPresented: Binding(
                get: { previewLoader.localURL != nil },
                set: { if !$0 { previewLoader.clear() } }
            )
        ) {
            if let url = previewLoader.localURL {
                FilePreviewView(fileURL: url)
                    .ignoresSafeArea()
            }
        }
        // Preview download failures
        .alert(
            "Preview Error",
            isPresented: Binding(
                get: { previewLoader.error != nil },
                set: { if !$0 { previewLoader.clear() } }
            )
        ) {
            Button("OK") { previewLoader.clear() }
        } message: {
            Text(previewLoader.error ?? "")
        }
    }

    // MARK: - Upload Bar

    private var uploadBar: some View {
        HStack(spacing: 12) {
            PhotosPicker(
                selection: $selectedItems,
                maxSelectionCount: 10,
                matching: .any(of: [.images, .videos])
            ) {
                HStack(spacing: 6) {
                    Image(systemName: "photo.fill")
                        .font(.system(size: 14))
                    Text("Photos")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .foregroundColor(AppTheme.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(AppTheme.primary.opacity(0.1))
                        .overlay(Capsule().stroke(AppTheme.primary.opacity(0.3), lineWidth: 1))
                )
            }
            .onChange(of: selectedItems) { _, items in
                viewModel.selectedItems = items
                Task { await viewModel.uploadSelectedPhotos() }
            }

            Button {
                showDocumentPicker = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 14))
                    Text("Document")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .foregroundColor(AppTheme.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(AppTheme.accent.opacity(0.1))
                        .overlay(Capsule().stroke(AppTheme.accent.opacity(0.3), lineWidth: 1))
                )
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppTheme.backgroundCard.opacity(0.5))
    }

    // MARK: - Files List

    private var filesList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(viewModel.fileService.files) { file in
                    fileRow(file: file)
                }
            }
            .padding(16)
        }
    }

    private func fileRow(file: SharedFile) -> some View {
        HStack(spacing: 14) {
            // Tap-to-preview target wraps icon + info (not delete button)
            // File icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(AppTheme.backgroundElevated)
                    .frame(width: 44, height: 44)

                Image(systemName: file.iconSystemName)
                    .font(.system(size: 20))
                    .foregroundColor(AppTheme.primary)
            }

            // File info
            VStack(alignment: .leading, spacing: 3) {
                Text(file.name)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(file.formattedSize)
                    Text("•")
                    Text(file.uploadedByName)
                    Text("•")
                    Text(file.uploadedAt.timeAgoDisplay)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(AppTheme.textMuted)
            }

            Spacer()

            if previewLoader.isLoading {
                ProgressView()
                    .tint(AppTheme.primary)
                    .scaleEffect(0.8)
            }

            // Delete button
            if viewModel.canDeleteFile(file) {
                Button {
                    Task { await viewModel.deleteFile(file) }
                } label: {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.danger.opacity(0.7))
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(AppTheme.backgroundCard.opacity(0.4))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            Task { await previewLoader.load(file: file) }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "folder.fill")
                .font(.system(size: 48))
                .foregroundStyle(AppTheme.primaryGradient)

            Text("No files yet")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(.white)

            Text("Upload photos, documents, or other files for your trip.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
        }
    }

    // MARK: - Upload Progress

    private var uploadProgressOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView(value: viewModel.fileService.uploadProgress)
                    .tint(AppTheme.primary)
                    .scaleEffect(1.5)

                Text("Uploading... \(Int(viewModel.fileService.uploadProgress * 100))%")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
            }
            .padding(32)
            .glassCard()
        }
    }
}
