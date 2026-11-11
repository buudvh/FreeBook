import Foundation

internal struct TTSPreparedChapter: Sendable {
    let normalizedContent: String
    let paragraphs: [TTSParagraph]
    /// Tên chương đã dịch lúc chuẩn bị (`ProcessedChapterDTO.chapterTitle`: QT hoặc tiện ích dịch) — bắt đầu đọc từ bản
    /// chuẩn bị sẵn thì dùng y tên này, không dịch QT lại.
    let chapterTitle: String
}
