import SwiftUI

/// Sheet **sắp xếp lại** thứ tự các bộ sưu tập.
///
/// Vì sao là sheet riêng: `LazyVGrid` của tab Bộ sưu tập không có `onMove`, mà kéo-thả trong grid thì
/// phải tự dựng. Giữ lại đúng cơ chế `List` + `.onMove` đã chạy đúng ở bản trước, chỉ dời sang một màn.
///
/// Không tự ghi SwiftData: gọi đúng `BookCollectionCoordinator.reorderCollections(orderedIds:in:)`.
struct CollectionsReorderSheet: View {
    let collections: [BookCollection]
    /// Trả về `nil` khi thành công, hoặc câu lỗi để màn chủ phát toast.
    let onReorder: (IndexSet, Int) -> String?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(collections) { collection in
                        HStack(spacing: 10) {
                            Image(systemName: "folder.fill")
                                .foregroundColor(.accentColor)
                            Text(collection.name)
                                .font(.subheadline)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text("\(collection.books.count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .onMove(perform: move)
                } footer: {
                    Text("Kéo tay nắm bên phải để đổi thứ tự. Thứ tự này là thứ tự hiện ở tab Bộ sưu tập.")
                }
            }
            // Luôn ở chế độ sửa: màn này chỉ có một việc, không cần bấm thêm nút Sửa.
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Sắp xếp lại")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Xong") { dismiss() }
                }
            }
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        if let message = onReorder(source, destination) {
            ToastManager.shared.show(message: message, type: .error)
        }
    }
}
