import Foundation

/// Cách hiển thị tên chương của lượt quét tên riêng đang gửi — dải tiến độ, tiêu đề tác vụ, toast khi dừng.
///
/// Cùng luật với danh sách chương Reader và sheet chọn phạm vi (`AIBookDataInspector.nameScanChapters`), qua
/// `ChineseTextPipeline.chapterTitle`: phồn → giản theo Reader (chạy cả khi tắt dịch, 1.3.846), rồi bật dịch tên chương
/// và tên còn chữ Hán ⇒ dịch (từ điển riêng của truyện); dịch ra rỗng thì giữ tên đã chuyển. Vòng lượt (`runTurns`) gọi
/// **một lần mỗi lượt**, ngoài main thread — không bao giờ dịch trong `body`.
public struct AINameScanChapterTitleStyle: Sendable, Equatable {
    public let bookId: String
    public let translatesTitles: Bool
    public let convertsTraditionalToSimplified: Bool

    public init(bookId: String, translatesTitles: Bool = false, convertsTraditionalToSimplified: Bool = false) {
        self.bookId = bookId
        self.translatesTitles = translatesTitles
        self.convertsTraditionalToSimplified = convertsTraditionalToSimplified
    }

    /// Tên hiển thị của một tên gốc; tên rỗng ⇒ rỗng (chỉ còn số chương).
    public func displayTitle(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        let options = ChineseTextPipeline.Options(
            converts: convertsTraditionalToSimplified, translates: translatesTitles, dictionaryBookId: bookId
        )
        let translated = ChineseTextPipeline.chapterTitle(trimmed, options)
        return translated.isEmpty ? ChineseTextPipeline.convert(trimmed, converts: options.converts) : translated
    }
}
