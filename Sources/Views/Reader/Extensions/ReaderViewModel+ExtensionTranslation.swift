import Foundation

/// Dịch nội dung chương bằng **tiện ích dịch** (`translate.js`) khi bộ dịch của truyện là tiện ích.
///
/// - Chỉ nội dung chương truyện chữ + tên chương ở header Reader; mục lục, Chi tiết, Khám phá, xuất TXT vẫn QT.
/// - Đi qua đúng một cửa `TranslationExtensionChapterTranslator` (cache RAM theo dòng dùng chung với TTS) nên Reader và
///   TTS ra cùng một chữ cho cùng một dòng — vệt highlight TTS là offset trên chữ Reader đang hiển thị.
/// - Dòng tiện ích lỗi đã được lùi về QT / giữ chữ gốc ở translator; `fallbackStatus` của kết quả được ghi vào
///   `TranslationFallbackStatusStore` lúc áp bản dựng (`applyPreparedTranslation`) ⇒ dải báo đầu chương.
extension ReaderViewModel {
    /// Bộ dịch tiện ích của truyện khi đang bật dịch; `nil` = dựng bằng QT như cũ. Tra lại mỗi lượt dựng (đổi bộ dịch
    /// làm generation dịch đổi ⇒ vòng `processAndSaveChapter` dựng lại và tra lại).
    func extensionTranslationEngine(isTranslationEnabled: Bool) -> ResolvedTranslationEngine? {
        guard isTranslationEnabled else { return nil }
        let engine = TranslationEngineStore.shared.resolve(bookId: bookId, packageId: extensionPackageId)
        return engine.usesExtension ? engine : nil
    }

    /// Dịch các dòng sẽ dựng đoạn (đã bỏ tên chương trùng — **cùng** hàm với `buildCancellable`) + tên chương.
    /// Chạy trong `context` đã chụp để phần lùi QT dùng đúng bộ từ điển mà lượt dựng dùng. `nil` khi không dùng tiện ích.
    /// `normalizedText` đã qua phồn → giản (`ChineseTextPipeline.normalizeChapter`) nên dòng gửi đi y như dòng Reader dựng;
    /// tên chương còn thô ⇒ phồn → giản chỉ áp cho tên (`titleConvertsTraditional`).
    nonisolated func translateChapterWithExtension(
        _ normalizedText: NormalizedChapterText,
        originalTitle: String,
        removeDuplicatedTitle: Bool,
        shouldConvertTraditionalToSimplified: Bool,
        bookId: String,
        chapterIndex: Int,
        engine: ResolvedTranslationEngine?,
        context: TranslationReadContext
    ) async throws -> TranslationExtensionChapterTranslator.Output? {
        guard let engine, engine.usesExtension else { return nil }
        let lines = ChapterTextNormalizer.contentLines(of: normalizedText, removingDuplicatedTitle: removeDuplicatedTitle)
        let title = originalTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : originalTitle
        return try await TranslationReadContext.$current.withValue(context) {
            try await TranslationExtensionChapterTranslator.translate(
                lines: lines,
                title: title,
                chapterIndex: chapterIndex,
                bookId: bookId,
                engine: engine,
                titleConvertsTraditional: shouldConvertTraditionalToSimplified
            )
        }
    }

    /// Đổi bộ dịch / ngôn ngữ / model / kiểu (`TranslationEngineStore.didChangeNotification`). Store đã `invalidateCache`
    /// nên generation dịch của truyện bị ảnh hưởng đã đổi: chương đang hiện dựng lại ngay, chương khác khi tới, báo QT cũ
    /// của truyện bỏ đi. Đổi riêng cho truyện khác thì generation của truyện này giữ nguyên ⇒ không làm gì.
    func handleTranslationEngineChange() {
        let token = TranslateUtils.translationGenerationToken(for: bookId)
        if let cached = cache.cache[displayedChapterIndex], cached.state == .loaded, cached.translationToken == token {
            return
        }
        TranslationFallbackStatusStore.shared.clear(bookId: bookId)
        updateCachedTranslatedContent(bookId: bookId, scope: .globalReload)
    }

    /// "Thử lại" ở dải báo / popup: dựng lại chương dù generation không đổi. Cache dịch của truyện (cả lỗi đã nhớ) đã
    /// được `requestRetry` xoá trước khi báo ⇒ lượt dựng này gọi lại tiện ích; TTS đọc lại cùng lúc thì lượt trùng được
    /// gộp (`TranslationExtensionInflight`) nên hai bên ra cùng chữ.
    func handleTranslationRetry(_ request: TranslationFallbackStatusStore.RetryRequest) {
        guard request.bookId == bookId else { return }
        guard request.chapterIndex == displayedChapterIndex else {
            cache.cache[request.chapterIndex]?.translationToken = 0
            return
        }
        AppLogger.shared.log("🌐 [ExtTranslate] Thử lại chương \(request.chapterIndex + 1)")
        refreshParagraphItems()
    }
}
