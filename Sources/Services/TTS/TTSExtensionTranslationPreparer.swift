import Foundation

/// Chuẩn bị bản dịch cho TTS khi bộ dịch của truyện là **tiện ích dịch**: dịch các dòng (sau khi bỏ tên chương trùng —
/// cùng hàm với Reader) + tên chương qua `TranslationExtensionChapterTranslator`, rồi dựng `TTSPretranslatedSnapshot`
/// để `TTSBackgroundProcessor` dùng thay cho QT.
///
/// - Reader và TTS đi chung một cửa dịch (cache RAM theo dòng + gộp lượt trùng) nên ra cùng một chữ cho cùng một dòng —
///   vệt highlight là offset trên chữ Reader đang hiển thị. Snapshot hợp lệ do Reader đưa ⇒ dùng y nguyên, cả tên chương
///   Reader đã dịch (không gọi tiện ích lần nữa).
/// - Không bọc thêm vòng thử lại: phần lùi QT / giữ gốc đã nằm trong translator.
/// - Mỗi lượt ghi báo lùi QT (hoặc xoá báo) vào `TTSTranslationFallbackNotifier`; toast chỉ khi TTS thật sự đọc tới
///   chương đó.
enum TTSExtensionTranslationPreparer {
    struct Prepared: Sendable {
        let snapshot: TTSPretranslatedSnapshot
        /// `nil` khi chương không có tên.
        let translatedTitle: String?
    }

    /// Chạy **trong** `TranslationReadContext` đã chụp (`token` = generation của context đó): phần lùi QT dùng đúng bộ từ
    /// điển, và `processChapter` chạy ngay sau trong cùng context sẽ nhận snapshot dù generation sống đổi giữa chừng
    /// (caller tự so token của DTO như với QT).
    ///
    /// `requiresReaderSnapshot` (lượt chuẩn bị sẵn khi Reader vừa hiện chương, người dùng chưa bấm nghe): không có bản
    /// dịch hợp lệ của Reader ⇒ ném `CancellationError`, không gọi tiện ích trước — tránh tốn lượt gọi và tránh dịch
    /// song song với chính Reader (tiện ích kiểu AI có thể ra chữ khác ⇒ vệt highlight lệch).
    static func prepare(
        bookId: String,
        chapterIndex: Int,
        chapterTitle: String,
        rawContent: String,
        removeDuplicatedTitle: Bool,
        convertsTraditional: Bool,
        engine: ResolvedTranslationEngine,
        readerSnapshot: TTSPretranslatedSnapshot?,
        requiresReaderSnapshot: Bool = false,
        token: Int
    ) async throws -> Prepared {
        let normalized = ChapterTextNormalizer.normalize(rawContent)
        let lines = ChapterTextNormalizer.contentLines(of: normalized, removingDuplicatedTitle: removeDuplicatedTitle)
        let title = chapterTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : chapterTitle
        try Task.checkCancellation()

        if let readerSnapshot,
           readerSnapshot.matches(lines: lines, isTranslationEnabled: true, convertsTraditional: convertsTraditional, token: token) {
            var translatedTitle: String?
            if let title {
                if let readerTitle = readerTranslatedTitle(readerSnapshot, for: title) {
                    translatedTitle = readerTitle
                } else if !requiresReaderSnapshot {
                    translatedTitle = try await TranslationExtensionChapterTranslator.translateTitle(
                        title, chapterIndex: chapterIndex, bookId: bookId, engine: engine,
                        convertsTraditional: convertsTraditional
                    ).result.text
                }
            }
            // Đọc y bản Reader đã dựng: báo lùi QT (nếu có) là dải báo của Reader.
            await MainActor.run {
                TTSTranslationFallbackNotifier.shared.recordProcessed(nil, bookId: bookId, chapterIndex: chapterIndex)
            }
            return Prepared(snapshot: readerSnapshot, translatedTitle: translatedTitle)
        }
        if requiresReaderSnapshot { throw CancellationError() }
        if readerSnapshot != nil {
            AppLogger.shared.log("🌐 [ExtTranslate] TTS chương \(chapterIndex + 1): bản dịch của Reader không khớp ⇒ tự dịch")
        }

        let output = try await TranslationExtensionChapterTranslator.translate(
            lines: lines,
            title: title,
            chapterIndex: chapterIndex,
            bookId: bookId,
            engine: engine,
            convertsTraditional: convertsTraditional
        )
        let entries = lines.map { line -> TTSLineEntry in
            let result = output.lines[line.id] ?? TranslateUtils.untranslatedTextResult(line.text)
            return TTSLineEntry(lineId: line.id, originalText: line.text, translatedText: result.text, spans: result.spans)
        }
        let status = output.fallbackStatus
        await MainActor.run {
            TTSTranslationFallbackNotifier.shared.recordProcessed(status, bookId: bookId, chapterIndex: chapterIndex)
        }
        let snapshot = TTSPretranslatedSnapshot(
            isTranslationEnabled: true,
            shouldConvertTraditionalToSimplified: convertsTraditional,
            translationToken: token,
            entries: entries
        )
        return Prepared(snapshot: snapshot, translatedTitle: output.title?.text)
    }

    /// Tên chương Reader đã dịch, chỉ khi tên gốc Reader dùng trùng tên TTS đang đọc.
    private static func readerTranslatedTitle(_ snapshot: TTSPretranslatedSnapshot, for title: String) -> String? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let original = snapshot.originalTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              original == trimmedTitle,
              let translated = snapshot.translatedTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              !translated.isEmpty else { return nil }
        return translated
    }
}

extension TTSBackgroundProcessor {
    /// Cửa vào của 4 chỗ dựng chương TTS: như `processChapter`, nhưng khi dịch bật và bộ dịch của truyện (`packageId` =
    /// tiện ích nguồn) là tiện ích dịch thì dịch bằng tiện ích trước (`TTSExtensionTranslationPreparer`). QT / tắt dịch ⇒
    /// gọi thẳng `processChapter` như cũ. `requiresReaderSnapshot`: xem `TTSExtensionTranslationPreparer.prepare` (chỉ
    /// lượt chuẩn bị sẵn `prepareSpeaking` bật; ném `CancellationError` thay vì gọi tiện ích).
    nonisolated func processChapterWithEngine(
        bookId: String,
        packageId: String?,
        chapterIndex: Int,
        chapterTitle: String,
        rawContent: String,
        chunkLength: Int,
        shouldTranslateRawContent: Bool,
        shouldConvertTraditionalToSimplified: Bool = false,
        includeChapterTitle: Bool,
        removeDuplicatedTitle: Bool,
        sessionID: UUID,
        generation: Int,
        snapshot: TTSPretranslatedSnapshot? = nil,
        requiresReaderSnapshot: Bool = false
    ) async throws -> ProcessedChapterDTO {
        let engine = shouldTranslateRawContent ? TranslationEngineStore.shared.resolve(bookId: bookId, packageId: packageId) : nil
        let usesExtension = engine?.usesExtension == true
        await MainActor.run {
            // TTS đã dựng chương có dịch ⇒ có cái để đọc lại khi bộ dịch đổi / Thử lại.
            if shouldTranslateRawContent { TTSExtensionTranslationObserver.shared.installIfNeeded() }
            // QT / tắt dịch ⇒ báo lùi QT còn chờ của chương (từ lượt dựng bằng tiện ích trước đó) không còn đúng.
            if !usesExtension {
                TTSTranslationFallbackNotifier.shared.recordProcessed(nil, bookId: bookId, chapterIndex: chapterIndex)
            }
        }
        guard let engine, usesExtension else {
            return try await processChapter(
                bookId: bookId, chapterIndex: chapterIndex, chapterTitle: chapterTitle, rawContent: rawContent,
                chunkLength: chunkLength, shouldTranslateRawContent: shouldTranslateRawContent,
                shouldConvertTraditionalToSimplified: shouldConvertTraditionalToSimplified,
                includeChapterTitle: includeChapterTitle, removeDuplicatedTitle: removeDuplicatedTitle,
                sessionID: sessionID, generation: generation, snapshot: snapshot
            )
        }
        let context = TranslationReadContext.capture(bookId: bookId)
        return try await TranslationReadContext.$current.withValue(context) {
            let prepared = try await TTSExtensionTranslationPreparer.prepare(
                bookId: bookId, chapterIndex: chapterIndex, chapterTitle: chapterTitle, rawContent: rawContent,
                removeDuplicatedTitle: removeDuplicatedTitle, convertsTraditional: shouldConvertTraditionalToSimplified,
                engine: engine, readerSnapshot: snapshot, requiresReaderSnapshot: requiresReaderSnapshot,
                token: context.generation
            )
            return try await processChapter(
                bookId: bookId, chapterIndex: chapterIndex, chapterTitle: chapterTitle, rawContent: rawContent,
                chunkLength: chunkLength, shouldTranslateRawContent: true,
                shouldConvertTraditionalToSimplified: shouldConvertTraditionalToSimplified,
                includeChapterTitle: includeChapterTitle, removeDuplicatedTitle: removeDuplicatedTitle,
                sessionID: sessionID, generation: generation, snapshot: prepared.snapshot,
                translatedTitleOverride: prepared.translatedTitle
            )
        }
    }
}

extension TTSPretranslatedSnapshot {
    /// Snapshot dùng được cho đúng dãy dòng này: cùng công tắc dịch, phồn → giản, generation dịch, và id + chữ gốc của
    /// từng dòng khớp. `TTSBackgroundProcessor` và `TTSExtensionTranslationPreparer` kiểm bằng cùng hàm này.
    func matches(lines: [ChapterTextLine], isTranslationEnabled: Bool, convertsTraditional: Bool, token: Int) -> Bool {
        self.isTranslationEnabled == isTranslationEnabled
            && shouldConvertTraditionalToSimplified == convertsTraditional
            && translationToken == token
            && entries.count == lines.count
            && zip(entries, lines).allSatisfy { $0.0.lineId == $0.1.id && $0.0.originalText == $0.1.text }
    }
}
