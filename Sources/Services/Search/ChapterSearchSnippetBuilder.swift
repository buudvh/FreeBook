import Foundation

/// Đổi một hàng thô của chỉ mục thành `ChapterSearchHit`: định vị đoạn chứa từ khoá và cắt đoạn
/// xem trước.
///
/// Vì sao gọi `ChapterTextNormalizer.normalize` (bản **có** lọc rác) chứ không phải
/// `normalizeProcessedContent`: `ChapterContentRepository.makeDocument` cũng dùng đúng `normalize`
/// khi dựng `ChapterDocument` cho Reader. Chỉ khi đi qua cùng một hàm thì `ChapterTextLine.id`
/// tính ra ở đây mới **trùng** với `ParagraphItem.id` mà Reader sẽ có, tức mở Reader mới nhảy đúng
/// đoạn. Không tự tách dòng ở đây — bất biến "chỉ `ChapterTextNormalizer` được chuẩn hoá text".
///
/// Hệ quả có ý thức: nếu luật lọc rác ăn mất dòng chứa từ khoá thì hit bị **bỏ**, đúng bằng việc
/// Reader cũng sẽ không hiển thị dòng đó.
internal enum ChapterSearchSnippetBuilder {
    /// Trả `nil` khi không định vị được từ khoá trong bất kỳ dòng nào sau chuẩn hoá.
    internal static func makeHit(row: ChapterSearchIndexDatabase.Row, query: String) -> ChapterSearchHit? {
        let normalized = ChapterTextNormalizer.normalize(row.content)
        for line in normalized.lines {
            guard let matchRange = line.text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else {
                continue
            }
            return ChapterSearchHit(
                bookId: row.bookId,
                chapterIndex: row.chapterIndex,
                chapterUrl: row.chapterUrl,
                chapterTitle: row.chapterTitle,
                paragraphIndex: line.id,
                snippet: snippet(in: line.text, around: matchRange)
            )
        }
        return nil
    }

    /// Cắt cửa sổ `±ChapterSearchPolicy.snippetRadius` ký tự quanh vùng khớp, thêm `…` ở đầu/cuối
    /// nếu có phần bị cắt.
    internal static func snippet(in text: String, around matchRange: Range<String.Index>) -> String {
        let radius = ChapterSearchPolicy.snippetRadius
        let start = text.index(matchRange.lowerBound, offsetBy: -radius, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(matchRange.upperBound, offsetBy: radius, limitedBy: text.endIndex) ?? text.endIndex
        var result = String(text[start..<end])
        if start > text.startIndex { result = "…" + result }
        if end < text.endIndex { result += "…" }
        return result
    }
}
