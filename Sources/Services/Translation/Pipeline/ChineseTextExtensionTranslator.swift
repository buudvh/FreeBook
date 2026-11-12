import Foundation

/// Bước "dịch" của `ChineseTextPipeline` khi bộ dịch của chỗ đó là **tiện ích dịch** (1.3.852), cho chữ **ngoài** nội
/// dung chương: tên chương ở đầu trang / mục lục, tên truyện / mô tả / thể loại / bình luận / đề xuất, khối OCR truyện
/// tranh, phụ đề, lời bài hát. Nội dung chương vẫn đi `TranslationExtensionChapterTranslator` (Reader + TTS).
///
/// Cùng thứ tự với pipeline: **phồn → giản trước** (theo `Options.converts`) ⇒ tiện ích ⇒ mẩu lỗi lùi về QT (theo
/// `Kind`), mẩu lỗi không có chữ Hán giữ chữ đã chuyển. Gửi qua `TranslationExtensionRunner.translateLines` nên được gom
/// lô theo `max_line` / `max_length`, dùng cache RAM theo dòng (cả lỗi gần đây 90 s) và gộp lượt trùng đang chạy.
///
/// - Chữ nhiều dòng (mô tả, bình luận) tách theo `\n` thành từng dòng gửi đi rồi ghép lại — một dòng gửi tiện ích
///   không được chứa `\n` (lô nối các dòng bằng `\n`).
/// - Mẩu trùng nhau chỉ gửi một lần.
/// - Chỉ ném `CancellationError`.
enum ChineseTextExtensionTranslator {
    /// Kiểu chữ — chỉ quyết định cách lùi về QT khi tiện ích lỗi.
    enum Kind: Sendable, Hashable {
        /// Tên truyện, mô tả, thể loại, bình luận… (`ChineseTextPipeline.meta`).
        case meta
        /// Tên chương / tập (`ChineseTextPipeline.chapterTitle`, có bộ rule tên chương).
        case chapterTitle
        /// Câu / đoạn (`ChineseTextPipeline.content`): khối OCR, phụ đề, lời.
        case content
    }

    /// Một lượt dịch: bộ dịch tiện ích + cấu hình chữ của màn + nhãn `source` của hợp đồng.
    struct Request: Sendable, Equatable {
        let engine: ResolvedTranslationEngine
        let options: ChineseTextPipeline.Options
        let source: TranslationExtensionSource
        /// Phạm vi cache theo truyện (`bookId`; màn chưa có truyện ⇒ `""`).
        let cacheBookId: String

        /// Bộ dịch dịch sang tiếng Việt — chỉ khi đó mới được dùng `title_trans` (bản QT tiếng Việt) thay tiện ích.
        var targetsVietnamese: Bool {
            let target = engine.selection.to.lowercased()
            return target == "vi" || target.hasPrefix("vi-") || target.hasPrefix("vi_")
        }
    }

    struct Output: Sendable {
        /// Cùng thứ tự đầu vào. `nil` = tiện ích lỗi cho mẩu đó (xem `translateWithFallback` để có sẵn bản QT).
        let texts: [String?]
        /// `nil` = không mẩu nào lỗi.
        let fallbackStatus: TranslationFallbackStatus?
    }

    /// Lượt dịch của một màn; `nil` khi màn không dịch (`options.translates` tắt) hoặc bộ dịch là QT ⇒ caller đi
    /// `ChineseTextPipeline` như cũ. Bộ dịch tra như popup dịch: truyện ⇒ nguồn ⇒ toàn cục (`TranslationEngineStore`).
    static func request(
        bookId: String?,
        packageId: String?,
        options: ChineseTextPipeline.Options,
        source: TranslationExtensionSource
    ) -> Request? {
        guard options.translates else { return nil }
        let engine = TranslationEngineStore.shared.resolve(
            bookId: bookId.flatMap { $0.isEmpty ? nil : $0 }, packageId: packageId
        )
        guard engine.usesExtension else { return nil }
        return Request(engine: engine, options: options, source: source, cacheBookId: bookId ?? "")
    }

    /// Dịch các mẩu bằng tiện ích. Mẩu không cần dịch (không có chữ cái) trả chữ đã chuyển; mẩu lỗi trả `nil`.
    static func translate(_ texts: [String], request: Request) async throws -> Output {
        let converted = texts.map { ChineseTextPipeline.convert($0, converts: request.options.converts) }
        guard let job = TranslationExtensionRunner.Job(
            engine: request.engine, bookId: request.cacheBookId, source: request.source
        ) else {
            return Output(texts: Array(repeating: nil, count: texts.count), fallbackStatus: nil)
        }

        // Tách dòng + bỏ trùng: mỗi dòng khác nhau gửi đúng một lần.
        var unique: [String] = []
        var idByLine: [String: Int] = [:]
        let segmented: [[String]] = converted.map { text in
            let parts = text.components(separatedBy: "\n")
            for part in parts where TranslationExtensionBatchPlanner.needsTranslation(part) && idByLine[part] == nil {
                idByLine[part] = unique.count
                unique.append(part)
            }
            return parts
        }
        guard !unique.isEmpty else { return Output(texts: converted, fallbackStatus: nil) }

        let lines = unique.enumerated().map { TranslationExtensionBatchPlanner.Line(id: $0.offset, text: $0.element) }
        let result = try await TranslationExtensionRunner.translateLines(lines, job: job)
        try Task.checkCancellation()

        var failedTexts = 0
        var keptOriginal = 0
        let outputs: [String?] = segmented.map { parts in
            var joined: [String] = []
            joined.reserveCapacity(parts.count)
            for part in parts {
                guard let id = idByLine[part] else { joined.append(part); continue }
                guard let translated = result.translations[id] else { return nil }
                joined.append(translated)
            }
            return joined.joined(separator: "\n")
        }
        for (index, output) in outputs.enumerated() where output == nil {
            failedTexts += 1
            if !TranslateUtils.containsChinese(converted[index]) { keptOriginal += 1 }
        }
        let status = failedTexts == 0 ? nil : TranslationFallbackStatus(
            engineName: result.engineName,
            message: result.errorMessage ?? "Không rõ lỗi",
            failedLineCount: failedTexts,
            requestedLineCount: texts.count,
            keptOriginalLineCount: keptOriginal
        )
        return Output(texts: outputs, fallbackStatus: status)
    }

    /// Như `translate`, mẩu lỗi lùi về QT theo `kind` (không có chữ Hán ⇒ chữ đã chuyển).
    static func translateWithFallback(
        _ texts: [String],
        kind: Kind,
        request: Request
    ) async throws -> (texts: [String], fallbackStatus: TranslationFallbackStatus?) {
        let output = try await translate(texts, request: request)
        let filled = zip(texts, output.texts).map { original, translated in
            translated ?? quickTranslation(original, kind: kind, options: request.options)
        }
        return (filled, output.fallbackStatus)
    }

    /// Bản QT của một mẩu (đường lùi; cũng là chữ hiện tạm trong lúc chờ tiện ích).
    static func quickTranslation(_ text: String, kind: Kind, options: ChineseTextPipeline.Options) -> String {
        switch kind {
        case .meta: return ChineseTextPipeline.meta(text, options)
        case .chapterTitle: return ChineseTextPipeline.chapterTitle(text, options)
        case .content: return ChineseTextPipeline.content(text, options)
        }
    }
}
