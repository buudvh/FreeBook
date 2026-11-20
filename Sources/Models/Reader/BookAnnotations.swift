import Foundation

/// Dấu trang + ghi chú của **một** truyện chữ (1.3.1040, anh Bửu duyệt mockup): một file JSON mỗi truyện
/// (`BookAnnotationStore`), đọc / ghi qua `BookAnnotationRepository`.
///
/// Dấu trang theo **chương** (chạm ⇒ mở đầu chương); ghi chú theo **đoạn** (chạm ⇒ tới đúng đoạn). Chương neo bằng chỉ số
/// + tên đang hiện lúc tạo + link (`chapterUrl`) — mở lại mà chỉ số không còn trỏ đúng link (mục lục đổi, đổi nguồn) thì
/// Reader tra chương theo link. Đoạn neo bằng `paragraphIndex` = `ChapterTextLine.id` (id **thưa**, tên chương = -1 —
/// cùng hệ với `ParagraphItem.id`), kèm `paragraphNumber` (thứ tự hiển thị "Đoạn N") và đoạn chữ trích.
struct BookAnnotations: Codable, Sendable, Equatable {
    struct Bookmark: Codable, Sendable, Equatable, Identifiable {
        var id: UUID
        var chapterIndex: Int
        var chapterTitle: String
        var chapterUrl: String
        var createdAt: Date
    }

    struct Note: Codable, Sendable, Equatable, Identifiable {
        var id: UUID
        var chapterIndex: Int
        var chapterTitle: String
        var chapterUrl: String
        /// `ChapterTextLine.id` của đoạn (thưa, không phải chỉ số mảng); -1 = tên chương.
        var paragraphIndex: Int
        /// Thứ tự đoạn trong chương lúc tạo (1-based, tên chương = 0) — chỉ để hiện "Đoạn N".
        var paragraphNumber: Int
        /// Chữ đang hiện (bản dịch khi bật dịch) của vùng bôi đen lúc tạo, đã cắt bớt.
        var quote: String
        var text: String
        var createdAt: Date
        var updatedAt: Date
    }

    var bookmarks: [Bookmark] = []
    var notes: [Note] = []

    var isEmpty: Bool { bookmarks.isEmpty && notes.isEmpty }

    /// Độ dài tối đa của đoạn trích lưu kèm ghi chú.
    static let quoteLimit = 300

    func bookmark(chapterIndex: Int) -> Bookmark? {
        bookmarks.first { $0.chapterIndex == chapterIndex }
    }

    /// Gộp `other` vào bản này theo `id`: mục đã có giữ nguyên (bản trên máy thắng), mục thiếu thì thêm. Dấu trang trùng
    /// chương với dấu đã có cũng bỏ (mỗi chương một dấu).
    func merging(_ other: BookAnnotations) -> BookAnnotations {
        var result = self
        let bookmarkIds = Set(bookmarks.map(\.id))
        let bookmarkedChapters = Set(bookmarks.map(\.chapterIndex))
        result.bookmarks += other.bookmarks.filter { !bookmarkIds.contains($0.id) && !bookmarkedChapters.contains($0.chapterIndex) }
        let noteIds = Set(notes.map(\.id))
        result.notes += other.notes.filter { !noteIds.contains($0.id) }
        return result
    }

    /// Dấu trang theo thứ tự chương.
    var sortedBookmarks: [Bookmark] {
        bookmarks.sorted { ($0.chapterIndex, $0.createdAt) < ($1.chapterIndex, $1.createdAt) }
    }

    /// Một nhóm của tab Ghi chú.
    struct ChapterNotes: Identifiable {
        let chapterIndex: Int
        let chapterTitle: String
        let notes: [Note]
        var id: Int { chapterIndex }
    }

    /// Ghi chú nhóm theo chương (thứ tự chương), trong chương theo thứ tự đoạn rồi thời điểm tạo.
    var notesByChapter: [ChapterNotes] {
        let grouped = Dictionary(grouping: notes, by: \.chapterIndex)
        return grouped.keys.sorted().map { index in
            let items = (grouped[index] ?? []).sorted {
                ($0.paragraphNumber, $0.createdAt) < ($1.paragraphNumber, $1.createdAt)
            }
            return ChapterNotes(chapterIndex: index, chapterTitle: items.first?.chapterTitle ?? "", notes: items)
        }
    }
}
