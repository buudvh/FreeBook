import SwiftUI
import SwiftData

/// Thêm **nhiều** truyện vào một bộ sưu tập — sheet "Thêm vào bộ sưu tập" của chế độ chọn nhiều ở Kệ Sách / Lịch Sử
/// (`ShelfSelectionActionBar`, anh Bửu duyệt mockup https://claude.ai/artifact/Es6YfEe94Zyi2uigCzMTPX).
///
/// Khác `CollectionPickerSheet` (một truyện, đặt lại **toàn bộ** bộ của truyện qua `setMemberships`): ở đây **chỉ thêm** —
/// chạm một bộ ⇒ `BookCollectionCoordinator.addBooks` (một lần lưu), đóng sheet, toast; không gỡ truyện khỏi bộ nào.
/// "Tạo bộ sưu tập mới" tạo xong thêm luôn. Truyện ở Lịch sử vào bộ là lên kệ (bất biến của coordinator) — dòng đầu báo số
/// đó. Cùng khuôn với `PlaylistAddSheet`: không có nút chỉ để đóng (vuốt xuống), nơi trình bày gắn `.appGlassSheet()`.
struct CollectionBatchAddSheet: View {
    let books: [Book]
    /// Đã thêm xong (sheet tự đóng) — nơi trình bày thoát chế độ chọn khi sheet đóng hẳn.
    let onAdded: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: [SortDescriptor(\BookCollection.sortOrder), SortDescriptor(\BookCollection.createdAt)])
    private var collections: [BookCollection]

    @State private var showingCreateAlert = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List { Group {
                Section {
                    summaryRow
                }
                Section {
                    Button {
                        newName = ""
                        showingCreateAlert = true
                    } label: {
                        Label("Tạo bộ sưu tập mới", systemImage: "folder.badge.plus")
                    }
                    ForEach(collections) { collection in
                        collectionRow(collection)
                    }
                } header: {
                    Text("Bộ sưu tập")
                }
            }.glassSheetRows() }
            .listStyle(.insetGrouped)
            .pageTitle("Thêm vào bộ sưu tập")
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .alert("Bộ sưu tập mới", isPresented: $showingCreateAlert) {
            TextField("Tên bộ sưu tập", text: $newName)
                .textInputAutocapitalization(.sentences)
            Button("Tạo") { createAndAdd() }
            Button("Hủy", role: .cancel) { newName = "" }
        } message: {
            Text("\(books.count) truyện sẽ được thêm vào bộ sưu tập vừa tạo.")
        }
    }

    // MARK: - Hàng

    /// Bìa chồng của tối đa 3 truyện đầu + "N truyện"; có truyện ở Lịch sử thì dòng phụ báo số sẽ lên kệ.
    private var summaryRow: some View {
        let offShelf = books.filter { !$0.isOnShelf }.count
        return HStack(spacing: 12) {
            HStack(spacing: -14) {
                ForEach(Array(books.prefix(3))) { book in
                    BookCoverView(
                        bookId: book.bookId,
                        coverUrl: book.coverUrl,
                        width: 30,
                        height: 42,
                        host: book.host,
                        extensionPackageId: book.extensionPackageId
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(books.count) truyện")
                    .font(.headline)
                if offShelf > 0 {
                    Text("\(offShelf) truyện ở Lịch sử sẽ lên kệ")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func collectionRow(_ collection: BookCollection) -> some View {
        Button {
            add(to: collection.collectionId, name: collection.name)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "folder")
                    .foregroundColor(.primary)
                Text(collection.name)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("\(collection.books.count) truyện")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Thao tác

    private func createAndAdd() {
        let name = newName
        newName = ""
        switch BookCollectionCoordinator.shared.createCollection(name: name, in: modelContext) {
        case .success(let collection):
            add(to: collection.collectionId, name: collection.name)
        case .failure(let error):
            ToastManager.shared.show(message: error.localizedDescription, type: .error)
        }
    }

    private func add(to collectionId: String, name: String) {
        let bookIds = books.map(\.bookId)
        switch BookCollectionCoordinator.shared.addBooks(bookIds: bookIds, toCollection: collectionId, in: modelContext) {
        case .success(let added):
            dismiss()
            if added > 0 {
                ToastManager.shared.show(message: "Đã thêm \(added) truyện vào \(name)", type: .success)
            } else {
                ToastManager.shared.show(message: "Đã có sẵn trong \(name)", type: .info)
            }
            onAdded()
        case .failure(let error):
            AppLogger.shared.log("❌ [CollectionBatchAdd] Lỗi thêm \(bookIds.count) truyện vào bộ sưu tập: \(error.localizedDescription)")
            ToastManager.shared.show(message: "Không thể thêm vào bộ sưu tập: \(error.localizedDescription)", type: .error)
        }
    }
}
