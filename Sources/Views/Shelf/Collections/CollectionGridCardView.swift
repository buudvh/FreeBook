import SwiftUI

/// Một thẻ bộ sưu tập trong grid: ảnh ghép bìa + tên viết hoa bên dưới.
///
/// Không biết `modelContext`: hai việc Đổi tên / Xoá nhận vào bằng closure để `CollectionsTabView` giữ
/// nguyên vai trò chủ mọi thao tác ghi (đi qua `BookCollectionCoordinator`).
///
/// Nhấn giữ vẫn ra đúng hai việc đó — `.contextMenu` thêm ở 1.3.336 được giữ, vì grid không còn
/// `swipeActions` như bản `List` cũ.
struct CollectionGridCardView: View {
    let collection: BookCollection
    let size: CGFloat
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        NavigationLink(destination: CollectionDetailView(collectionId: collection.collectionId)) {
            VStack(alignment: .leading, spacing: 8) {
                CollectionCoverMosaicView(
                    books: Self.previewBooks(from: collection.books),
                    totalCount: collection.books.count,
                    size: size
                )

                Text(collection.name)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(width: size, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: onRename) {
                Label("Đổi tên", systemImage: "pencil")
            }
            Button(role: .destructive, action: onDelete) {
                Label("Xoá bộ sưu tập", systemImage: "trash")
            }
        }
    }

    /// Ghim trước, rồi mới đọc trước — cùng thứ tự `CollectionDetailView` dùng, để bìa trên thẻ khớp
    /// những quyển đầu tiên người dùng thấy khi mở bộ.
    ///
    /// Chọn bằng **một pass** thay vì `sorted()` cả mảng: hàm này chạy lại mỗi lần vẽ mỗi thẻ, bộ vài
    /// trăm quyển mà sort đủ thì grid giật khi cuộn.
    static func previewBooks(from books: [Book], limit: Int = 3) -> [Book] {
        guard books.count > limit else {
            return books.sorted(by: isOrderedBefore)
        }

        var picked: [Book] = []
        for book in books {
            if picked.count < limit {
                picked.append(book)
                picked.sort(by: isOrderedBefore)
                continue
            }
            if let last = picked.last, isOrderedBefore(book, last) {
                picked.removeLast()
                picked.append(book)
                picked.sort(by: isOrderedBefore)
            }
        }
        return picked
    }

    private static func isOrderedBefore(_ lhs: Book, _ rhs: Book) -> Bool {
        if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
        return lhs.lastReadDate > rhs.lastReadDate
    }
}
