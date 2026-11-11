import Foundation

struct ReaderParagraphBuildResult: Equatable, Sendable {
    let translatedTitle: String
    let translatedContent: String
    let paragraphItems: [ParagraphItem]
    /// Tiện ích dịch lỗi ở một số dòng (đã lùi QT / giữ gốc); `nil` với QT, dịch tắt hoặc tiện ích dịch đủ.
    var fallbackStatus: TranslationFallbackStatus? = nil
}
