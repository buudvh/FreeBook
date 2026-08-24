import Foundation

/// Bộ khớp tìm-trong-Reader thuần: tìm chuỗi con **không phân biệt dấu và hoa thường** trong text
/// gốc và text đã dịch của các đoạn **đã nạp sẵn trong RAM**. Không đọc đĩa/mạng, không dựng chỉ mục
/// — vì vậy không có đường crash như phân hệ tìm toàn văn cũ.
///
/// Đầu vào cố ý phẳng (`Chapter`/`Paragraph` chỉ chứa `String`) để helper không phụ thuộc kiểu của
/// tầng View; `ReaderSearchView` dựng chúng từ `ParagraphItem` của các chương `state == .loaded`.
enum ReaderSearchMatcher {
    /// Một đoạn đã nạp.
    struct Paragraph {
        let paragraphIndex: Int
        let isTitle: Bool
        let original: String
        let translated: String
    }

    /// Một chương đã nạp.
    struct Chapter {
        let chapterIndex: Int
        let paragraphs: [Paragraph]
    }

    /// Một khớp: vị trí (chương, đoạn) + đoạn trích ngắn quanh chỗ khớp.
    struct Hit: Identifiable, Equatable {
        /// Chỉ số chương thật trong mục lục.
        let chapterIndex: Int
        /// `ParagraphItem.id` — chỉ số dòng thô, **thưa** (không phải array index).
        let paragraphIndex: Int
        let isTitle: Bool
        let snippet: String
        /// `true` khi khớp trên chuỗi đã dịch; `false` khi khớp trên chuỗi gốc.
        let matchedInTranslated: Bool

        var id: String { "\(chapterIndex).\(paragraphIndex).\(matchedInTranslated)" }
    }

    /// Vệt tô của kết quả tìm mà người dùng vừa nhảy tới. Là value type bất biến nên `ReaderView`
    /// giữ nó trong `@State` mà không tạo thêm chủ sở hữu trạng thái nào.
    ///
    /// Cố ý **không** mang theo `NSRange`: range phải tính lại trên đúng chuỗi đang hiển thị (bản
    /// dịch hay bản gốc, tuỳ công tắc dịch lúc render), nên chỉ `query` mới an toàn để lưu.
    struct Highlight: Equatable {
        let chapterIndex: Int
        /// `ParagraphItem.id` — chỉ số dòng thô, **thưa** (không phải array index).
        let paragraphIndex: Int
        let query: String
    }

    /// `range(of:options:)` giữ toạ độ index trên chính haystack nên đoạn trích cắt được ngay trên
    /// chuỗi gốc — an toàn hơn tự fold rồi dò lại vì fold có thể đổi độ dài chuỗi.
    private static let options: String.CompareOptions = [.diacriticInsensitive, .caseInsensitive]

    /// Tìm mọi khớp; kết quả sắp theo `(chapterIndex, paragraphIndex)` tăng dần. Mỗi đoạn chỉ tạo
    /// **một** hit (ưu tiên chuỗi hiển thị/đã dịch) để danh sách gọn.
    static func search(query rawQuery: String, in chapters: [Chapter], maxHits: Int = 500) -> [Hit] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }

        var hits: [Hit] = []
        let sortedChapters = chapters.sorted { $0.chapterIndex < $1.chapterIndex }
        for chapter in sortedChapters {
            for paragraph in chapter.paragraphs {
                if !paragraph.translated.isEmpty,
                   let range = paragraph.translated.range(of: query, options: options, range: nil, locale: .current) {
                    hits.append(Hit(
                        chapterIndex: chapter.chapterIndex,
                        paragraphIndex: paragraph.paragraphIndex,
                        isTitle: paragraph.isTitle,
                        snippet: snippet(from: paragraph.translated, around: range),
                        matchedInTranslated: true
                    ))
                } else if let range = paragraph.original.range(of: query, options: options, range: nil, locale: .current) {
                    hits.append(Hit(
                        chapterIndex: chapter.chapterIndex,
                        paragraphIndex: paragraph.paragraphIndex,
                        isTitle: paragraph.isTitle,
                        snippet: snippet(from: paragraph.original, around: range),
                        matchedInTranslated: false
                    ))
                }
                if hits.count >= maxHits { return hits }
            }
        }
        return hits
    }

    /// Tìm khớp **đầu tiên** của `query` trong `text` và trả về `NSRange` hệ **UTF-16** — đúng hệ
    /// toạ độ mà `ReaderTextView` dùng để tô nền. Dùng `NSString.range(of:)` nên range luôn nằm
    /// trên chính `text`, kể cả khi bỏ dấu làm đổi độ dài chuỗi gấp.
    ///
    /// Caller phải truyền **chuỗi đang hiển thị** của đoạn (bản dịch khi bật VietPhrase, bản gốc
    /// khi tắt), vì đó là chuỗi mà `UITextView` đang giữ.
    static func firstHighlightRange(of rawQuery: String, in text: String) -> NSRange? {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !text.isEmpty else { return nil }
        let nsText = text as NSString
        let found = nsText.range(
            of: query,
            options: options,
            range: NSRange(location: 0, length: nsText.length),
            locale: .current
        )
        guard found.location != NSNotFound, found.length > 0 else { return nil }
        return found
    }

    /// Cắt đoạn trích ~`context` ký tự mỗi phía quanh chỗ khớp, thêm dấu `…` khi bị cắt và gộp mọi
    /// khoảng trắng/xuống dòng thành một dấu cách để hiển thị một dòng.
    private static func snippet(from text: String, around match: Range<String.Index>, context: Int = 32) -> String {
        let lower = text.index(match.lowerBound, offsetBy: -context, limitedBy: text.startIndex) ?? text.startIndex
        let upper = text.index(match.upperBound, offsetBy: context, limitedBy: text.endIndex) ?? text.endIndex
        var piece = String(text[lower..<upper])
        piece = piece.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if lower > text.startIndex { piece = "…" + piece }
        if upper < text.endIndex { piece = piece + "…" }
        return piece
    }
}
