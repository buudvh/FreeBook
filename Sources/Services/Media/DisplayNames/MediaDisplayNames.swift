import Foundation

/// Tên hiển thị của phim / album đang phát: chữ đã qua `ChineseTextPipeline` — phồn → giản nếu bật (**cả khi tắt dịch**)
/// rồi dịch nếu bật, cấu hình ba cấp phim / album này ⇒ nguồn ⇒ Tất cả (`ChineseTextPipeline.options(bookId:packageId:)`).
///
/// **Chỉ để vẽ** (trình phát, màn xem, màn nghe, hub, đĩa góc dưới, màn khoá). Tên gốc (`bookTitle`, `albumTitle`,
/// `albumAuthor`, `Episode.title`, `Track.title`, `Track.artist`) giữ nguyên văn vì còn ghi mục lục / `Book`, playlist, ngữ
/// cảnh nguồn (`SourceRuntimeContext.bookName`), từ điển truyện, ô tìm.
///
/// Tra theo **chuỗi gốc**, chỉ giữ mục đổi: tên gốc đổi giữa chừng (chi tiết về sau) ⇒ tra không thấy ⇒ hiện tên gốc tới lượt
/// tính kế. Tên phim / album đi `meta`, tác giả / nghệ sĩ đi `author`, tên tập / nhóm tập / bài đi `chapterTitle`.
/// Tính ngoài main bằng `make` (thuần, không đọc cấu hình); session giữ bản mới nhất và gắn tên tập / bài vào `shownTitle`.
struct MediaDisplayNames: Sendable, Equatable {
    let options: ChineseTextPipeline.Options
    private(set) var titles: [String: String] = [:]
    private(set) var authors: [String: String] = [:]
    private(set) var items: [String: String] = [:]

    init(options: ChineseTextPipeline.Options) {
        self.options = options
    }

    static let passthrough = MediaDisplayNames(options: .passthrough)

    /// Tắt cả chuyển lẫn dịch ⇒ mọi tên giữ nguyên, khỏi tính.
    var isPassthrough: Bool { !options.converts && !options.translates }

    func title(_ raw: String) -> String { titles[raw] ?? raw }
    func author(_ raw: String) -> String { authors[raw] ?? raw }
    /// Tên tập / bài đã chuyển; `nil` = giữ tên gốc.
    func item(_ raw: String) -> String? { items[raw] }

    /// Dựng bảng tên (gọi ngoài main — mục lục dài thì `chapterTitle` từng mục không rẻ). Có dịch thì chụp từ điển / rule
    /// **một lần** cho cả lượt (`TranslationReadContext`), như `MediaCaptionTranslator`.
    static func make(
        titles: [String],
        authors: [String],
        items: [String],
        options: ChineseTextPipeline.Options
    ) -> MediaDisplayNames {
        let compute = { () -> MediaDisplayNames in
            var names = MediaDisplayNames(options: options)
            guard !names.isPassthrough else { return names }
            names.titles = Self.changed(titles) { ChineseTextPipeline.meta($0, options) }
            names.authors = Self.changed(authors) { ChineseTextPipeline.author($0, options) }
            names.items = Self.changed(items) { ChineseTextPipeline.chapterTitle($0, options) }
            return names
        }
        guard options.translates else { return compute() }
        let context = TranslationReadContext.capture(bookId: options.dictionaryBookId)
        return TranslationReadContext.$current.withValue(context, operation: compute)
    }

    /// Chỉ chuỗi có chữ Hán mới qua pipeline; chỉ giữ mục đổi khác tên gốc.
    private static func changed(_ raws: [String], _ transform: (String) -> String) -> [String: String] {
        var result: [String: String] = [:]
        for raw in Set(raws) where !raw.isEmpty && TranslateUtils.containsChinese(raw) {
            let shown = transform(raw)
            if !shown.isEmpty, shown != raw { result[raw] = shown }
        }
        return result
    }
}
