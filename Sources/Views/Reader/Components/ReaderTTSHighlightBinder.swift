import SwiftUI

/// Bọc **một hàng đoạn văn** của Reader: quan sát `ReaderTTSHighlightReader` và đưa vệt TTS / vệt chuẩn bị của
/// đúng đoạn này vào `content`. Nhờ vậy nhịp highlight chỉ làm các hàng đang mount tính lại (rẻ: so vài số rồi
/// dựng lại giá trị `ParagraphCardView`, vốn `Equatable` nên chỉ thẻ có vệt đổi mới chạm UIKit), thay vì cả thân
/// ReaderView như trước 1.3.513.
///
/// Quy tắc chọn vệt giữ nguyên logic cũ của `ReaderView.chapterContentView`: vệt TTS chỉ khi đúng truyện, đúng
/// chương, đúng đoạn và có `highlightRange`; vệt chuẩn bị chỉ khi không có vệt TTS; đang điều hướng sang chương mới
/// (`isSuppressed`) thì không vệt nào. `ParagraphItem.id` là id dòng **thưa**, so theo id, không theo vị trí.
///
/// **Tô cả đoạn** (2026-11-20, anh Bửu chọn khi sửa VP / Name / rule lúc đang nghe): chữ TTS đang đọc của đoạn này
/// (`currentSpokenText` / `preparingSpokenText`) khác chữ đoạn đang hiện — TTS giữ chữ cũ ở dòng đang đọc trong khi Reader
/// đã hiện bản mới, hoặc Reader chưa dựng lại vì panel đang mở — ⇒ vệt theo câu là offset trên chữ khác, đặt lên là lệch ⇒
/// tô cả đoạn bằng kiểu vệt chuẩn bị (nhạt hơn). Chữ trùng ⇒ vệt câu như thường.
struct ReaderTTSHighlightBinder<Content: View>: View {
    @ObservedObject var reader: ReaderTTSHighlightReader
    let bookId: String
    let chapterIndex: Int
    let paragraph: ParagraphItem
    let isTranslationEnabled: Bool
    let isSuppressed: Bool
    @ViewBuilder let content: (_ ttsRange: NSRange?, _ preparingRange: NSRange?) -> Content

    var body: some View {
        let snapshot = reader.snapshot
        let paragraphId = paragraph.id
        let ownsChapter = !isSuppressed &&
            snapshot.playingBookId == bookId &&
            snapshot.playingChapterIndex == chapterIndex
        let isReading = ownsChapter && paragraphId == snapshot.currentParentParagraphIndex && snapshot.highlightRange != nil
        let isPreparing = ownsChapter && snapshot.preparingParentParagraphIndex == .some(paragraphId)
        let wholeRange = isReading ? mismatchWholeRange(snapshot.currentSpokenText)
            : (isPreparing ? mismatchWholeRange(snapshot.preparingSpokenText) : nil)
        let ttsRange: NSRange? = (wholeRange == nil && isReading) ? snapshot.highlightRange : nil
        let preparingRange: NSRange? = wholeRange ?? ((ttsRange == nil && isPreparing) ? snapshot.preparingHighlightRange : nil)
        content(ttsRange, preparingRange)
    }

    /// Cả đoạn đang hiện, khi TTS đọc đoạn này bằng chữ khác chữ đang hiện; `nil` ⇒ vệt câu như thường (kể cả khi chưa biết
    /// chữ TTS).
    private func mismatchWholeRange(_ spokenText: String?) -> NSRange? {
        guard let ttsText = spokenText else { return nil }
        let shown = ParagraphCardView.displayText(for: paragraph, isTranslationEnabled: isTranslationEnabled)
        guard shown.trimmingCharacters(in: .whitespacesAndNewlines) != ttsText else { return nil }
        let length = (shown as NSString).length
        return length > 0 ? NSRange(location: 0, length: length) : nil
    }
}
