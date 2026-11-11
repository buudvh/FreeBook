import Foundation

/// Chuyển phồn → giản rồi dịch VietPhrase phụ đề phim (`VideoSubtitleCue`) và lời bài hát (`AudioLyricLine`) — phép biến đổi
/// **chỉ để hiển thị**, chạy **sau** khi parse: dữ liệu nguồn (`track.subtitles[].data`, nguồn lời) giữ nguyên văn, không qua
/// `ChapterTextNormalizer`, JunkFilter, bin hay TTS (bất biến "media không đi qua pipeline text"; tiền lệ: tên nhóm tập phim).
///
/// Đi đúng một đường `ChineseTextPipeline` (1.3.846), cấu hình ba cấp phim / album này ⇒ nguồn ⇒ Tất cả
/// (`ChineseTextPipeline.options(bookId:packageId:)`):
/// 1. **phồn → giản** nếu bật — chạy **cả khi tắt dịch**, kết quả là "chữ gốc" hiện ở kiểu Gốc / dòng phụ của Song ngữ;
/// 2. **dịch** khi công tắc dịch của phim / album bật **và** dòng có chữ Hán.
///
/// Cách gọi: từ **trong** task sẵn có của session (`subtitleTask` của phim, `lyricsTranslationTask` của nhạc) — không
/// `Task.detached`, để huỷ task của session là huỷ luôn lượt. Hai hàm `nonisolated async` nên chạy ngoài main.
/// `prepare` đọc cấu hình + chụp từ điển / rule **một lần** cho cả lượt; `translate` xử lý từng lô bằng đúng ảnh chụp đó.
enum MediaCaptionTranslator {
    /// Một lượt: cấu hình chuyển / dịch + ảnh chụp từ điển / rule (`TranslationReadContext`, chỉ khi dịch), dùng chung cho
    /// mọi lô của lượt.
    struct Pass: Sendable {
        let bookId: String
        let options: ChineseTextPipeline.Options
        fileprivate let context: TranslationReadContext?

        /// Lượt có dịch — lớp dịch đè lên hình (phụ đề cứng OCR) **chỉ** chạy khi cờ này bật; chỉ chuyển phồn → giản thì
        /// không vẽ gì lên hình.
        var translates: Bool { options.translates }

        /// Bản chỉ chuyển phồn → giản của lượt này (bỏ bước dịch) — phụ đề phim chuyển cả bộ trước rồi mới dịch theo lô.
        var convertOnly: Pass {
            var convertOptions = options
            convertOptions.translates = false
            return Pass(bookId: bookId, options: convertOptions, context: nil)
        }
    }

    /// Kết quả một dòng.
    struct LineResult: Sendable, Equatable {
        /// Chữ gốc đã chuyển phồn → giản; `nil` = y như nguyên văn (tắt chuyển / không có chữ phồn).
        let converted: String?
        /// Bản dịch; `nil` = không dịch (tắt dịch / không có chữ Hán / dịch ra y như chữ đã chuyển).
        let translation: String?

        static let unchanged = LineResult(converted: nil, translation: nil)
    }

    /// Số dòng phụ đề công bố mỗi lần (phim dịch từ dòng đang chiếu trở đi, hiện dần).
    static let batchSize = 50
    /// Kiểm huỷ sau mỗi chừng này dòng.
    private static let cancellationCheckInterval = 20

    /// Cổng bật dịch của phim/album — cùng luật với `prepare`. Cho dòng trạng thái "Đang bật / Đang tắt" của ngăn kéo.
    nonisolated static func shouldTranslate(bookId: String, packageId: String) -> Bool {
        ChineseTextPipeline.options(bookId: bookId, packageId: packageId).translates
    }

    /// Mở một lượt (đọc cấu hình + chụp từ điển, ngoài main). `nil` = tắt cả chuyển lẫn dịch, hoặc task đã bị huỷ.
    nonisolated static func prepare(bookId: String, packageId: String) async -> Pass? {
        guard !Task.isCancelled else { return nil }
        let options = ChineseTextPipeline.options(bookId: bookId, packageId: packageId)
        guard options.converts || options.translates else { return nil }
        let context = options.translates ? TranslationReadContext.capture(bookId: options.dictionaryBookId) : nil
        guard !Task.isCancelled else { return nil }
        return Pass(bookId: bookId, options: options, context: context)
    }

    /// Xử lý một lô dòng (cùng thứ tự). Trả `nil` cả lô khi task bị huỷ giữa chừng — chỗ gọi không được công bố kết quả dở.
    nonisolated static func translate(_ texts: [String], pass: Pass) async -> [LineResult]? {
        processBatch(texts, pass: pass)
    }

    // MARK: - Nội bộ

    /// Thân đồng bộ (gọi `TaskLocal.withValue` bản đồng bộ cho chắc): có dịch thì cả lô chạy trong ảnh chụp của lượt, nên
    /// `translateContent` không chụp lại từ điển mỗi dòng (`TranslationReadContext.withSnapshot` thấy `current` cùng `bookId`).
    private static func processBatch(_ texts: [String], pass: Pass) -> [LineResult]? {
        guard let context = pass.context else { return processLines(texts, pass: pass) }
        return TranslationReadContext.$current.withValue(context) { () -> [LineResult]? in
            processLines(texts, pass: pass)
        }
    }

    private static func processLines(_ texts: [String], pass: Pass) -> [LineResult]? {
        var results: [LineResult] = []
        results.reserveCapacity(texts.count)
        for (offset, text) in texts.enumerated() {
            if offset % cancellationCheckInterval == 0, Task.isCancelled { return nil }
            results.append(processLine(text, options: pass.options))
        }
        return Task.isCancelled ? nil : results
    }

    /// Chuyển cả dòng một lần, rồi dịch từng hàng (phụ đề 2 dòng nối `\n`); hàng không có chữ Hán giữ nguyên.
    /// `content` (không phải `chapterTitle`): phụ đề / lời là nội dung, không dùng bộ rule tên chương.
    private static func processLine(_ text: String, options: ChineseTextPipeline.Options) -> LineResult {
        guard TranslateUtils.containsChinese(text) else { return .unchanged }
        let source = ChineseTextPipeline.convert(text, converts: options.converts)
        let converted = source == text ? nil : source
        guard options.translates else { return LineResult(converted: converted, translation: nil) }
        let rowOptions = options.alreadyConverted
        let rows = source.components(separatedBy: "\n").map { ChineseTextPipeline.content($0, rowOptions) }
        let translated = rows.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        // Từ điển chưa nạp xong thì dịch trả nguyên văn ⇒ coi như chưa có bản dịch (so với chữ **đã chuyển**, kẻo chữ chỉ
        // đổi phồn → giản bị coi là "bản dịch").
        let translation = translated.isEmpty || translated == source ? nil : translated
        return LineResult(converted: converted, translation: translation)
    }
}
