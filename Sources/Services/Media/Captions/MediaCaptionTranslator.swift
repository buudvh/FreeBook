import Foundation

/// Dịch VietPhrase phụ đề phim (`VideoSubtitleCue`) và lời bài hát (`AudioLyricLine`) — phép biến đổi **chỉ để hiển thị**,
/// chạy **sau** khi parse: dữ liệu nguồn (`track.subtitles[].data`, nguồn lời) giữ nguyên văn, không qua
/// `ChapterTextNormalizer`, JunkFilter, bin hay TTS (bất biến "media không đi qua pipeline text"; tiền lệ: tên nhóm tập phim).
///
/// Cổng giống truyện chữ: dịch khi `TranslationConfigStore.isTranslationEnabled(bookId:packageId:)` (phim/album này > nguồn
/// > nguồn tự nhận tiếng Trung > toàn cục) **và** dòng có chữ Hán. Phồn→giản theo
/// `convertsTraditionalToSimplified(bookId:packageId:)` (chỉ phim/nhạc dùng).
///
/// Cách gọi: từ **trong** task sẵn có của session (`subtitleTask` của phim, `lyricsTranslationTask` của nhạc) — không
/// `Task.detached`, để huỷ task của session là huỷ luôn lượt dịch. Hai hàm `nonisolated async` nên chạy ngoài main.
/// `prepare` chụp từ điển / rule **một lần** cho cả lượt; `translate` dịch từng lô bằng đúng ảnh chụp đó.
enum MediaCaptionTranslator {
    /// Một lượt dịch: ảnh chụp từ điển / rule (`TranslationReadContext`) + cờ phồn→giản, dùng chung cho mọi lô của lượt.
    struct Pass: Sendable {
        let bookId: String
        let convertsTraditional: Bool
        fileprivate let context: TranslationReadContext
    }

    /// Số dòng phụ đề công bố mỗi lần (phim dịch từ dòng đang chiếu trở đi, hiện dần).
    static let batchSize = 50
    /// Kiểm huỷ sau mỗi chừng này dòng.
    private static let cancellationCheckInterval = 20

    /// Cổng bật dịch của phim/album — y như Reader.
    nonisolated static func shouldTranslate(bookId: String, packageId: String) -> Bool {
        TranslationConfigStore.shared.isTranslationEnabled(bookId: bookId, packageId: packageId)
    }

    /// Mở một lượt dịch (đọc cấu hình + chụp từ điển, ngoài main). `nil` = cổng đang tắt hoặc task đã bị huỷ.
    nonisolated static func prepare(bookId: String, packageId: String) async -> Pass? {
        guard !Task.isCancelled, shouldTranslate(bookId: bookId, packageId: packageId) else { return nil }
        let converts = TranslationConfigStore.shared.convertsTraditionalToSimplified(bookId: bookId, packageId: packageId)
        let context = TranslationReadContext.capture(bookId: bookId)
        guard !Task.isCancelled else { return nil }
        return Pass(bookId: bookId, convertsTraditional: converts, context: context)
    }

    /// Dịch một lô dòng (cùng thứ tự). Mỗi phần tử: bản dịch, hoặc `nil` khi dòng không có chữ Hán / dịch ra y nguyên.
    /// Trả `nil` cả lô khi task bị huỷ giữa chừng — chỗ gọi không được công bố kết quả dở.
    nonisolated static func translate(_ texts: [String], pass: Pass) async -> [String?]? {
        translateBatch(texts, pass: pass)
    }

    // MARK: - Nội bộ

    /// Thân đồng bộ (gọi `TaskLocal.withValue` bản đồng bộ cho chắc): cả lô chạy trong ảnh chụp của lượt, nên
    /// `translateContent` không chụp lại từ điển mỗi dòng (`TranslationReadContext.withSnapshot` thấy `current` cùng `bookId`).
    private static func translateBatch(_ texts: [String], pass: Pass) -> [String?]? {
        TranslationReadContext.$current.withValue(pass.context) { () -> [String?]? in
            var results: [String?] = []
            results.reserveCapacity(texts.count)
            for (offset, text) in texts.enumerated() {
                if offset % cancellationCheckInterval == 0, Task.isCancelled { return nil }
                results.append(translateLine(text, pass: pass))
            }
            return Task.isCancelled ? nil : results
        }
    }

    /// Dòng nhiều hàng (phụ đề 2 dòng nối `\n`) ⇒ dịch từng hàng rồi nối lại; hàng không có chữ Hán giữ nguyên.
    /// `translateContent` (không phải `translateChapterTitle`): phụ đề / lời là nội dung, không dùng bộ rule tên chương.
    private static func translateLine(_ text: String, pass: Pass) -> String? {
        guard TranslateUtils.containsChinese(text) else { return nil }
        let rows = text.components(separatedBy: "\n").map { row -> String in
            guard TranslateUtils.containsChinese(row) else { return row }
            return TranslateUtils.translateContent(
                row,
                bookId: pass.bookId,
                shouldConvertTraditionalToSimplified: pass.convertsTraditional
            )
        }
        let translated = rows.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        // Từ điển chưa nạp xong thì `translateContent` trả nguyên văn ⇒ coi như chưa có bản dịch.
        return translated.isEmpty || translated == text ? nil : translated
    }
}
