import SwiftUI
import SwiftData
import PhotosUI

/// Sửa tay thông tin truyện: tên, tác giả và ảnh bìa (dán URL hoặc chọn ảnh trong máy).
///
/// Hai đường ảnh bìa loại trừ nhau ở thời điểm lưu:
/// - Chọn ảnh trong máy ⇒ ghi thẳng file `covers/<sha256(bookId)>.jpg`, `coverUrl` giữ nguyên
///   (`BookCoverView` ưu tiên file local nên bìa mới thắng).
/// - Đổi URL ⇒ xoá bìa local để `BookCoverView.triggerSaveLocalCover` tải lại từ URL mới.
struct BookInfoEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let bookId: String
    private let originalCoverUrl: String

    @State private var title: String
    @State private var author: String
    @State private var coverUrl: String

    @State private var pickedItem: PhotosPickerItem? = nil
    @State private var pickedData: Data? = nil
    @State private var pickedImage: UIImage? = nil
    @State private var isLoadingPickedImage = false
    @State private var isSaving = false
    @State private var errorMessage = ""

    init(bookId: String, title: String, author: String, coverUrl: String) {
        self.bookId = bookId
        self.originalCoverUrl = coverUrl
        self._title = State(initialValue: title)
        self._author = State(initialValue: author)
        self._coverUrl = State(initialValue: coverUrl)
    }

    var body: some View {
        NavigationStack {
            Form {
                infoSection
                coverSection
                if !errorMessage.isEmpty {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Sửa thông tin truyện")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Huỷ") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Lưu") { save() }
                        .disabled(isSaving || isLoadingPickedImage || trimmedTitle.isEmpty)
                }
            }
            .onChange(of: pickedItem) { _, newItem in
                loadPickedImage(from: newItem)
            }
        }
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @ViewBuilder
    private var infoSection: some View {
        Section("Thông tin") {
            VStack(alignment: .leading, spacing: 4) {
                Text("Tên truyện")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("Tên truyện", text: $title, axis: .vertical)
                    .lineLimit(1...3)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Tác giả")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("Tác giả", text: $author)
            }
        }
    }

    @ViewBuilder
    private var coverSection: some View {
        Section("Ảnh bìa") {
            HStack(alignment: .top, spacing: 14) {
                coverPreview
                VStack(alignment: .leading, spacing: 10) {
                    PhotosPicker(selection: $pickedItem, matching: .images, photoLibrary: .shared()) {
                        Label("Chọn ảnh trong máy", systemImage: "photo.on.rectangle")
                    }
                    if pickedData != nil {
                        Button(role: .destructive) {
                            pickedItem = nil
                            pickedData = nil
                            pickedImage = nil
                        } label: {
                            Label("Bỏ ảnh đã chọn", systemImage: "arrow.uturn.backward")
                        }
                        .font(.footnote)
                    }
                    if isLoadingPickedImage {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Địa chỉ ảnh bìa (URL)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("https://...", text: $coverUrl, axis: .vertical)
                    .lineLimit(1...3)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .disabled(pickedData != nil)
            }

            if pickedData != nil {
                Text("Đang dùng ảnh chọn từ máy — URL tạm thời bị bỏ qua.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else if coverUrl.trimmingCharacters(in: .whitespacesAndNewlines) != originalCoverUrl {
                Text("Bìa đã tải về sẽ bị xoá để tải lại theo URL mới.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var coverPreview: some View {
        if let image = pickedImage {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 72, height: 104)
                .clipped()
                .cornerRadius(6)
        } else {
            BookCoverView(bookId: bookId, coverUrl: coverUrl, width: 72, height: 104)
                .cornerRadius(6)
        }
    }

    private func loadPickedImage(from item: PhotosPickerItem?) {
        guard let item = item else { return }
        isLoadingPickedImage = true
        errorMessage = ""
        Task {
            let data = try? await item.loadTransferable(type: Data.self)
            await MainActor.run {
                self.isLoadingPickedImage = false
                guard let data = data, let image = UIImage(data: data) else {
                    self.errorMessage = "Không đọc được ảnh vừa chọn."
                    return
                }
                self.pickedData = data
                self.pickedImage = image
            }
        }
    }

    private func save() {
        let newTitle = trimmedTitle
        guard !newTitle.isEmpty else {
            errorMessage = "Tên truyện không được để trống."
            return
        }
        let newAuthor = author.trimmingCharacters(in: .whitespacesAndNewlines)
        let newCoverUrl = coverUrl.trimmingCharacters(in: .whitespacesAndNewlines)

        isSaving = true
        errorMessage = ""

        if let data = pickedData {
            guard ImageCacheManager.shared.saveCover(data: data, for: bookId) != nil else {
                isSaving = false
                errorMessage = "Không lưu được ảnh bìa đã chọn."
                return
            }
        } else if newCoverUrl != originalCoverUrl {
            do {
                try ImageCacheManager.shared.deleteCover(for: bookId)
            } catch {
                AppLogger.shared.log("⚠️ [BookInfoEdit] Không xoá được bìa cũ của \(bookId): \(error.localizedDescription)")
            }
        }

        let command = EditBookInfoCommand(
            bookId: bookId,
            title: newTitle,
            author: newAuthor,
            coverUrl: newCoverUrl
        )
        let result = BookTransactionCoordinator.shared.updateBookInfo(command: command, in: modelContext)
        isSaving = false
        switch result {
        case .success:
            dismiss()
        case .failure(let error):
            errorMessage = "Lỗi lưu thông tin: \(error.localizedDescription)"
        }
    }
}
