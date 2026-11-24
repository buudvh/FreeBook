import SwiftUI

/// Dải "Đọc tiếp" ở đầu sheet tuỳ chọn truyện (`BookActionSheet`; anh Bửu duyệt mockup
/// https://claude.ai/artifact/KGiBWCBGdKdrc5z7MJ8rWg, phương án A): section riêng ngay dưới phần đầu, dải viền màu nhấn
/// `BookActionStrip` hai dòng. Bấm ⇒ sheet phát `.continueReading`, màn gọi sheet mở nội dung **y như chạm thẻ** của màn đó
/// (`ShelfReaderRoute(resuming:)` → `BookContentDestination`).
///
/// - Nhãn theo loại: Đọc (chữ, truyện tranh) / Xem (phim) / Nghe (âm thanh) + "tiếp"; vị trí đang lưu ở đầu chương / tập /
///   bài đầu tiên ⇒ "… ngay" như "Đọc ngay" của Chi tiết. Xét theo **vị trí**, không theo `isHistory` (tiện ích tắt Lưu lịch
///   sử, truyện thêm kệ từ Chi tiết đều không bật cờ đó).
/// - Dòng phụ: chữ / truyện tranh **chỉ tên chương** đã lưu (dịch như tên chương "Đang đọc"), không có tiền tố "Ch. N"
///   (1.3.1055, anh Bửu: không hiển thị kiểu "Ch. stt"); tên rỗng mới lùi về "Chương N" như widget TTS (1.3.804). Phim / âm
///   thanh: "Tập N" / "Bài N" (`BookListRowSize.progressLabel`) + chỗ đang dở m:ss (`currentChapterPage` là số giây). Không có
///   phần trăm: `Book` không lưu tổng số chương lẫn số đoạn của chương.
/// - TTS đang đọc chính truyện này: tiến độ ghi trễ (debounce) nên dòng phụ có thể chậm một nhịp, như dòng tiến độ của thẻ.
struct BookContinueReadingStrip: View {
    let book: Book
    let action: () -> Void

    var body: some View {
        // Cùng luật suy loại với router mở nội dung (ghi đè loại của nguồn Legado thắng loại của nguồn).
        let kind = BookContentKindResolver.kind(bookId: book.bookId, packageId: book.extensionPackageId)
        let atStart = book.currentChapterIndex == 0 && book.currentChapterPage <= 0
        BookActionStrip(
            title: Self.title(kind: kind, atStart: atStart),
            systemImage: Self.systemImage(kind: kind, atStart: atStart),
            subtitle: detail(kind: kind),
            action: action
        )
    }

    private static func title(kind: ExtensionContentKind, atStart: Bool) -> String {
        let verb: String
        switch kind {
        case .video: verb = "Xem"
        case .audio: verb = "Nghe"
        case .text, .comic, .unsupported: verb = "Đọc"
        }
        return "\(verb) \(atStart ? "ngay" : "tiếp")"
    }

    /// Chữ / truyện tranh theo nút đọc của Chi tiết: "tiếp" `book.fill`, "ngay" `play.fill`.
    private static func systemImage(kind: ExtensionContentKind, atStart: Bool) -> String {
        switch kind {
        case .video: return "play.fill"
        case .audio: return "headphones"
        case .text, .comic, .unsupported: return atStart ? "play.fill" : "book.fill"
        }
    }

    private func detail(kind: ExtensionContentKind) -> String {
        switch kind {
        case .video, .audio:
            let progress = BookListRowSize.progressLabel(kind: kind, chapterIndex: book.currentChapterIndex)
            guard book.currentChapterPage > 0 else { return progress }
            return "\(progress) · \(VideoTimelineRow.format(Double(book.currentChapterPage)))"
        case .text, .comic, .unsupported:
            // Chỉ tên chương, không "Ch. N" phía trước (1.3.1055). Tên rỗng mới lùi về "Chương N".
            let raw = book.currentChapterTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { return "Chương \(book.currentChapterIndex + 1)" }
            return BookDisplayTranslation.chapterTitle(raw, BookDisplayTranslation.options(for: book))
        }
    }
}
