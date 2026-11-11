import Foundation

/// Dịch **một chương** bằng tiện ích dịch — điểm vào chung của Reader và TTS để hai bên ra cùng một chữ cho cùng một
/// dòng (vệt highlight TTS là offset trên chữ đang hiển thị).
///
/// - Nội dung: mọi dòng có chữ gửi tiện ích (`source = chapterContent`), không chỉ dòng có chữ Hán. Dòng lỗi ⇒ có chữ
///   Hán thì dịch QT (`ChineseTextPipeline.contentWithMapping`), không thì giữ chữ gốc. Bản dịch tiện ích không có span.
/// - Tên chương: `title_trans` đã lưu (khớp đúng tên gốc) ⇒ dùng; không có ⇒ tiện ích (`source = tableOfContent`); lỗi
///   ⇒ QT (`translateChapterTitle`) nếu có chữ Hán, không thì giữ nguyên.
/// - Phồn → giản của truyện áp **trước** khi gửi tiện ích (như QT): dòng nội dung nhận vào **đã** chuyển (dòng của
///   `ChineseTextPipeline.normalizeChapter`, Reader và TTS cùng dựng — 1.3.846) nên không chuyển lại; tên chương nhận
///   vào còn thô (để so `title_trans` với tên gốc đã lưu) ⇒ chuyển ở đây theo `titleConvertsTraditional`.
/// - Chỉ ném `CancellationError` (và lỗi dạng khi caller gọi với bộ dịch QT — caller phải kiểm `usesExtension` trước).
enum TranslationExtensionChapterTranslator {
    struct Output: Sendable {
        /// Bản dịch theo `ChapterTextLine.id`, đủ mọi dòng đầu vào.
        let lines: [Int: TranslatedTextResult]
        /// `nil` khi không xin dịch tên chương.
        let title: TranslatedTextResult?
        /// `nil` = không dòng nào phải lùi.
        let fallbackStatus: TranslationFallbackStatus?
    }

    static func translate(
        lines: [ChapterTextLine],
        title: String?,
        chapterIndex: Int,
        bookId: String,
        engine: ResolvedTranslationEngine,
        titleConvertsTraditional: Bool
    ) async throws -> Output {
        guard let job = TranslationExtensionRunner.Job(engine: engine, bookId: bookId, source: .chapterContent) else {
            throw TranslationExtensionResultParser.ShapeError(detail: "Bộ dịch đang là QT")
        }
        let requests = lines.map { TranslationExtensionBatchPlanner.Line(id: $0.id, text: $0.text) }
        let result = try await TranslationExtensionRunner.translateLines(requests, job: job)

        var titleOutcome: (result: TranslatedTextResult, failed: Bool, error: String?)?
        if let title, !title.isEmpty {
            titleOutcome = try await translateTitle(
                title, chapterIndex: chapterIndex, bookId: bookId, engine: engine, convertsTraditional: titleConvertsTraditional,
                skipsExtension: result.hadCallError
            )
        }

        var output: [Int: TranslatedTextResult] = [:]
        var keptOriginal = 0
        let qtLineOptions = ChineseTextPipeline.Options(converts: false, translates: true, dictionaryBookId: bookId)
        TranslationReadContext.withSnapshot(bookId: bookId) { () -> Void in
            for line in lines {
                if let translated = result.translations[line.id] {
                    output[line.id] = TranslatedTextResult(text: translated, spans: [])
                } else if result.failedLineIds.contains(line.id) && TranslateUtils.containsChinese(line.text) {
                    output[line.id] = ChineseTextPipeline.contentWithMapping(line.text, qtLineOptions)
                } else {
                    if result.failedLineIds.contains(line.id) { keptOriginal += 1 }
                    output[line.id] = TranslateUtils.untranslatedTextResult(line.text)
                }
            }
        }

        let titleFailed = titleOutcome?.failed == true
        let failedCount = result.failedLineIds.count + (titleFailed ? 1 : 0)
        var status: TranslationFallbackStatus?
        if failedCount > 0 {
            let titleKeptOriginal = titleFailed && !(title.map(TranslateUtils.containsChinese) ?? false)
            status = TranslationFallbackStatus(
                engineName: result.engineName,
                message: result.errorMessage ?? titleOutcome?.error ?? "Không rõ lỗi",
                failedLineCount: failedCount,
                requestedLineCount: result.requestedLineCount + (titleOutcome == nil ? 0 : 1),
                keptOriginalLineCount: keptOriginal + (titleKeptOriginal ? 1 : 0)
            )
        }
        return Output(lines: output, title: titleOutcome?.result, fallbackStatus: status)
    }

    /// Tên chương theo thứ tự `title_trans` ⇒ tiện ích ⇒ QT / giữ nguyên. Spans rỗng trừ khi lùi về QT.
    ///
    /// `title_trans` là bản QT (tiếng Việt) nên chỉ dùng khi tiện ích cũng dịch sang tiếng Việt — dịch sang ngôn ngữ
    /// khác mà hiện tên chương tiếng Việt là sai. `skipsExtension` (nội dung vừa gặp lỗi gọi tiện ích, vd bị giới hạn
    /// lượt) ⇒ khỏi gọi thêm, lùi QT luôn và tính là lỗi.
    static func translateTitle(
        _ title: String,
        chapterIndex: Int,
        bookId: String,
        engine: ResolvedTranslationEngine,
        convertsTraditional: Bool,
        skipsExtension: Bool = false
    ) async throws -> (result: TranslatedTextResult, failed: Bool, error: String?) {
        if Self.targetsVietnamese(engine),
           let stored = await storedTitleTranslation(title, chapterIndex: chapterIndex, bookId: bookId) {
            return (TranslatedTextResult(text: stored, spans: []), false, nil)
        }
        guard let job = TranslationExtensionRunner.Job(engine: engine, bookId: bookId, source: .tableOfContent) else {
            return (qtTitle(title, bookId: bookId, convertsTraditional: convertsTraditional), false, nil)
        }
        if skipsExtension {
            return (qtTitle(title, bookId: bookId, convertsTraditional: convertsTraditional), true, nil)
        }
        let input = ChineseTextPipeline.convert(title, converts: convertsTraditional)
        guard TranslationExtensionBatchPlanner.needsTranslation(input) else {
            return (TranslateUtils.untranslatedTextResult(input), false, nil)
        }
        do {
            let translated = try await TranslationExtensionRunner.translateText(input, job: job)
            return (TranslatedTextResult(text: translated, spans: []), false, nil)
        } catch {
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            let message = TranslationExtensionResultParser.shortMessage(for: error)
            AppLogger.shared.log("❌ [ExtTranslate] Tên chương \(chapterIndex + 1) lỗi — \(message)")
            return (qtTitle(title, bookId: bookId, convertsTraditional: convertsTraditional), true, message)
        }
    }

    private static func targetsVietnamese(_ engine: ResolvedTranslationEngine) -> Bool {
        let target = engine.selection.to.lowercased()
        return target == "vi" || target.hasPrefix("vi-") || target.hasPrefix("vi_")
    }

    /// Tên thô ⇒ chuyển (nếu bật) rồi QT; không có chữ Hán ⇒ tên đã chuyển nguyên văn.
    private static func qtTitle(_ title: String, bookId: String, convertsTraditional: Bool) -> TranslatedTextResult {
        ChineseTextPipeline.chapterTitleWithMapping(
            title, ChineseTextPipeline.Options(converts: convertsTraditional, translates: true, dictionaryBookId: bookId)
        )
    }

    /// `title_trans` của chương ở `ChapterStore` — chỉ khi tên gốc đã lưu trùng tên đang dịch (truyện chưa lưu / mục lục
    /// đã đổi thì bỏ qua).
    private static func storedTitleTranslation(_ title: String, chapterIndex: Int, bookId: String) async -> String? {
        guard chapterIndex >= 0,
              let stored = try? await ChapterStore.shared.fetchRange(bookId: bookId, startIndex: chapterIndex, count: 1).first,
              stored.index == chapterIndex,
              stored.title.trimmingCharacters(in: .whitespacesAndNewlines) == title.trimmingCharacters(in: .whitespacesAndNewlines),
              let translated = stored.titleTrans?.trimmingCharacters(in: .whitespacesAndNewlines),
              !translated.isEmpty else {
            return nil
        }
        return translated
    }
}
