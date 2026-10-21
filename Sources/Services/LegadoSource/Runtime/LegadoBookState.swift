import Foundation

/// Trạng thái theo truyện của một sách nguồn Legado (spec §5.7): `tocUrl` lấy từ thông tin sách, kho biến của sách và
/// kho biến theo chương. Giữ trong bộ nhớ bởi `LegadoBookStateStore`; sách đã lên kệ được ghi bền thành
/// `legado_state/<sha256(bookId)>.json`.
struct LegadoBookState: Codable, Sendable, Equatable {
    /// Bản chụp vài trường thông tin sách để JS của mục lục/nội dung đọc `book.kind`, `book.coverUrl`…
    struct Info: Codable, Sendable, Equatable {
        var name: String
        var author: String
        var kind: String
        var coverUrl: String
        var intro: String
        var latestChapterTitle: String
        var wordCount: String
    }

    var packageId: String
    /// URL trang chi tiết nguyên văn (kể cả khối option `,{…}`).
    var bookUrl: String
    /// `nil` = chưa chạy thông tin sách; `""` = mục lục nằm ngay trên trang sách (spec §5.3.1 bước 5).
    var tocUrl: String?
    var info: Info?
    /// Kho `book.putVariable`.
    var variables: [String: String]
    /// Kho `java.put` / `@put` khi có ngữ cảnh sách.
    var ruleVariables: [String: String]
    /// Kho `chapter.putVariable`, khoá = URL chương nguyên văn (`ChapterResult.url`).
    var chapterVariables: [String: [String: String]]

    init(packageId: String, bookUrl: String) {
        self.packageId = packageId
        self.bookUrl = bookUrl
        self.tocUrl = nil
        self.info = nil
        self.variables = [:]
        self.ruleVariables = [:]
        self.chapterVariables = [:]
    }

    /// Có gì đáng ghi bền: đã biết `tocUrl` hoặc có biến.
    var hasContent: Bool {
        tocUrl != nil || !variables.isEmpty || !ruleVariables.isEmpty || !chapterVariables.isEmpty
    }

    /// `overlay` (mới hơn, trong bộ nhớ) đè lên `base` (đọc từ đĩa) theo từng khoá.
    static func merged(base: LegadoBookState, overlay: LegadoBookState) -> LegadoBookState {
        var result = base
        if !overlay.packageId.isEmpty { result.packageId = overlay.packageId }
        if !overlay.bookUrl.isEmpty { result.bookUrl = overlay.bookUrl }
        if let tocUrl = overlay.tocUrl { result.tocUrl = tocUrl }
        if let info = overlay.info { result.info = info }
        result.variables.merge(overlay.variables) { _, new in new }
        result.ruleVariables.merge(overlay.ruleVariables) { _, new in new }
        for (url, values) in overlay.chapterVariables {
            result.chapterVariables[url, default: [:]].merge(values) { _, new in new }
        }
        return result
    }
}
