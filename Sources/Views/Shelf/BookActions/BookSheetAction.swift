import Foundation

/// Các mục trong sheet nhấn-giữ một cuốn sách. Sheet chỉ **phát** hành động, người trình bày (kệ sách
/// hoặc màn bộ sưu tập) mới thực thi — vì mấy hành động phải mở tiếp sheet/navigation của riêng nó.
enum BookSheetAction: Equatable {
    case openDetail
    case checkNewChapters
    case changeSource
    case editInfo
    case download
    case exportEbook
    case retranslateChapterTitles
    case togglePin
    case removeFromShelfOnly
    case deleteBook
    case addToShelf
    case removeFromHistory
    case removeFromCurrentCollection

    /// Ngữ cảnh mở sheet, quyết định hiện những mục nào.
    enum Mode: Equatable {
        case shelf
        case history
        /// Mở từ trong một bộ sưu tập — thêm mục "Bỏ khỏi bộ sưu tập này".
        case collection(collectionId: String)

        var tag: String {
            switch self {
            case .shelf: return "shelf"
            case .history: return "history"
            case .collection(let id): return "collection_\(id)"
            }
        }
    }

    /// Mục tiêu của một lần mở sheet. Dùng cho `.sheet(item:)` nên phải `Identifiable`.
    struct Target: Identifiable {
        let book: Book
        let mode: Mode

        var id: String { "\(book.bookId)_\(mode.tag)" }
    }
}
