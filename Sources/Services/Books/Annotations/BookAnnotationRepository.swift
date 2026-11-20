import Foundation
import Observation

/// Lối đọc / ghi dấu trang + ghi chú cho View (Reader, mục lục) — 1.3.1040. Giữ bản RAM của các truyện đã mở trong phiên;
/// mỗi lần sửa thì cập nhật RAM rồi ghi file ngay (`BookAnnotationStore`, file nhỏ). Việc nền (đổi nguồn, xoá truyện, khôi
/// phục sao lưu) ghi thẳng store rồi gọi `invalidate(bookId:)` để lần đọc sau nạp lại từ đĩa.
@MainActor
@Observable
final class BookAnnotationRepository {
    static let shared = BookAnnotationRepository()

    /// Bản RAM — **không** quan sát: lần đọc đầu nạp đĩa rồi ghi vào đây ngay trong `body`, ghi vào thuộc tính quan sát
    /// lúc đó là sửa state giữa lượt vẽ. View phụ thuộc `revision` (tăng khi sửa / bỏ cache) thay cho chính cache.
    @ObservationIgnored private var cache: [String: BookAnnotations] = [:]
    private(set) var revision = 0

    private init() {}

    func annotations(for bookId: String) -> BookAnnotations {
        _ = revision
        if let cached = cache[bookId] { return cached }
        let loaded = BookAnnotationStore.load(bookId: bookId)
        cache[bookId] = loaded
        return loaded
    }

    func invalidate(bookId: String) {
        cache[bookId] = nil
        revision += 1
    }

    /// Khôi phục sao lưu ghi nhiều truyện một lượt.
    func invalidateAll() {
        cache.removeAll()
        revision += 1
    }

    // MARK: - Tra nhanh cho Reader / mục lục

    func isBookmarked(bookId: String, chapterIndex: Int) -> Bool {
        annotations(for: bookId).bookmark(chapterIndex: chapterIndex) != nil
    }

    /// Số ghi chú theo `paragraphIndex` (id dòng) của một chương — Reader dựng một lần mỗi chương để gắn dấu đoạn.
    func noteCounts(bookId: String, chapterIndex: Int) -> [Int: Int] {
        var counts: [Int: Int] = [:]
        for note in annotations(for: bookId).notes where note.chapterIndex == chapterIndex {
            counts[note.paragraphIndex, default: 0] += 1
        }
        return counts
    }

    // MARK: - Ghi

    /// Bật / tắt dấu trang của chương. Trả `true` khi chương **vừa được** đánh dấu.
    @discardableResult
    func toggleBookmark(bookId: String, chapterIndex: Int, chapterTitle: String, chapterUrl: String) -> Bool {
        var value = annotations(for: bookId)
        let added: Bool
        if let index = value.bookmarks.firstIndex(where: { $0.chapterIndex == chapterIndex }) {
            value.bookmarks.remove(at: index)
            added = false
        } else {
            value.bookmarks.append(.init(
                id: UUID(), chapterIndex: chapterIndex, chapterTitle: chapterTitle, chapterUrl: chapterUrl, createdAt: Date()
            ))
            added = true
        }
        commit(value, bookId: bookId)
        AppLogger.shared.log("🔖 [Annotations] \(added ? "Đánh dấu" : "Bỏ dấu") chương \(chapterIndex + 1)")
        return added
    }

    func deleteBookmark(bookId: String, id: UUID) {
        var value = annotations(for: bookId)
        value.bookmarks.removeAll { $0.id == id }
        commit(value, bookId: bookId)
    }

    /// Thêm mới (`note.id` chưa có) hoặc cập nhật nội dung ghi chú.
    func saveNote(bookId: String, note: BookAnnotations.Note) {
        var value = annotations(for: bookId)
        var saved = note
        saved.quote = String(note.quote.prefix(BookAnnotations.quoteLimit))
        if let index = value.notes.firstIndex(where: { $0.id == note.id }) {
            saved.updatedAt = Date()
            value.notes[index] = saved
        } else {
            value.notes.append(saved)
        }
        commit(value, bookId: bookId)
        AppLogger.shared.log("🔖 [Annotations] Lưu ghi chú chương \(note.chapterIndex + 1), đoạn \(note.paragraphNumber)")
    }

    func deleteNote(bookId: String, id: UUID) {
        var value = annotations(for: bookId)
        value.notes.removeAll { $0.id == id }
        commit(value, bookId: bookId)
    }

    private func commit(_ value: BookAnnotations, bookId: String) {
        cache[bookId] = value
        revision += 1
        BookAnnotationStore.save(value, bookId: bookId)
    }
}
