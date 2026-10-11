import SwiftUI

/// Bọc **một hàng đoạn văn** của Reader: quan sát `ReaderTTSHighlightReader` và đưa vệt TTS / vệt chuẩn bị của
/// đúng đoạn này vào `content`. Nhờ vậy nhịp highlight chỉ làm các hàng đang mount tính lại (rẻ: so vài số rồi
/// dựng lại giá trị `ParagraphCardView`, vốn `Equatable` nên chỉ thẻ có vệt đổi mới chạm UIKit), thay vì cả thân
/// ReaderView như trước 1.3.513.
///
/// Quy tắc chọn vệt giữ nguyên logic cũ của `ReaderView.chapterContentView`: vệt TTS chỉ khi đúng truyện, đúng
/// chương, đúng đoạn và có `highlightRange`; vệt chuẩn bị chỉ khi không có vệt TTS; đang điều hướng sang chương mới
/// (`isSuppressed`) thì không vệt nào. `ParagraphItem.id` là id dòng **thưa**, so theo id, không theo vị trí.
struct ReaderTTSHighlightBinder<Content: View>: View {
    @ObservedObject var reader: ReaderTTSHighlightReader
    let bookId: String
    let chapterIndex: Int
    let paragraphId: Int
    let isSuppressed: Bool
    @ViewBuilder let content: (_ ttsRange: NSRange?, _ preparingRange: NSRange?) -> Content

    var body: some View {
        let snapshot = reader.snapshot
        let ownsChapter = !isSuppressed &&
            snapshot.playingBookId == bookId &&
            snapshot.playingChapterIndex == chapterIndex
        let ttsRange: NSRange? = (ownsChapter && paragraphId == snapshot.currentParentParagraphIndex)
            ? snapshot.highlightRange
            : nil
        let preparingRange: NSRange? = (ttsRange == nil && ownsChapter &&
            snapshot.preparingParentParagraphIndex == .some(paragraphId))
            ? snapshot.preparingHighlightRange
            : nil
        content(ttsRange, preparingRange)
    }
}
