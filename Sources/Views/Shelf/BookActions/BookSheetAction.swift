import Foundation
import UIKit

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

    /// Ngưỡng nhấn giữ dùng chung cho **mọi** hàng truyện (kệ sách, lịch sử, bộ sưu tập, màn tìm kiếm)
    /// và cho phần đầu của sheet.
    ///
    /// 0.25s chứ không phải 0.35–0.4s như trước: `.contextMenu` của hệ thống phóng to bản xem trước
    /// **ngay khi** ngón tay chạm nên nó *cảm giác* nhanh, còn menu tự dựng ở đây không có gì báo cho
    /// tới lúc sheet hiện ra. Ngưỡng ngắn hơn + một nhịp rung đóng đúng khoảng cảm giác đó. `maximumDistance`
    /// mặc định (10pt) vẫn huỷ cử chỉ khi người dùng đang cuộn, nên hạ ngưỡng không sinh ra kích hoạt oan.
    static let longPressMinimumDuration: Double = 0.25

    /// Nhịp rung phát **đúng lúc** cử chỉ đạt ngưỡng — cùng cường độ với các chỗ rung khác trong app.
    @MainActor
    static func playLongPressFeedback() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}
