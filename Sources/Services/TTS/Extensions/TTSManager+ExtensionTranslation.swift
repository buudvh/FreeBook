import Foundation

/// TTS theo kịp khi bản dịch bằng **tiện ích dịch** của truyện đang phát đổi giữa chừng: đổi bộ dịch / ngôn ngữ / model /
/// kiểu, "Thử lại" ở dải báo / popup, "Tải lại chương" ở Reader. `TTSParagraph.range` là offset trên chữ Reader đang
/// hiện, nên Reader dựng lại mà TTS giữ chữ cũ thì vệt highlight lệch ⇒ đọc lại chương đang phát từ đầu đoạn đang đọc,
/// y nhánh `updateTranslationSetting` (đang dừng ⇒ chỉ bỏ bản chuẩn bị sẵn, áp từ lần đọc sau).
///
/// Người nghe sự kiện: `TTSExtensionTranslationObserver` (đổi bộ dịch, Thử lại) và Reader (Tải lại chương).
extension TTSManager {
    /// Dấu vân tay bộ dịch đang hiệu lực của truyện đang phát: QT, hoặc tiện ích + ngôn ngữ + model + kiểu.
    func translationEngineFingerprint() -> String {
        let engine = TranslationEngineStore.shared.resolve(bookId: playingBookId, packageId: sessionTranslationPackageId)
        guard let packageId = engine.selection.packageId else { return "qt" }
        let settings = TranslationExtensionSettingsStore.shared
        return [
            packageId, engine.selection.from, engine.selection.to,
            settings.model(packageId: packageId), settings.style(packageId: packageId)
        ].joined(separator: "|")
    }

    /// "Thử lại" / "Tải lại chương" trên một chương của truyện dịch bằng tiện ích. Khoá bản chuẩn bị sẵn
    /// (`TTSPreparedChapterKey`) không có vân tay bản dịch ⇒ phải bỏ, nếu không bấm nghe vẫn đọc bản cũ. TTS đang phát
    /// đúng chương đó ⇒ đọc lại.
    func refreshExtensionTranslation(bookId: String, chapterIndex: Int) {
        guard playingBookId == bookId else {
            guard preparedChapterKey?.bookId == bookId else { return }
            preparationGeneration &+= 1
            prepareSpeakingTask?.cancel()
            prepareSpeakingTask = nil
            preparedChapterKey = nil
            preparedChapter = nil
            return
        }
        guard sessionTranslationEnabled,
              TranslationEngineStore.shared.resolve(bookId: bookId, packageId: sessionTranslationPackageId).usesExtension
        else { return }
        rereadCurrentChapterForTranslationChange(onlyChapter: chapterIndex, reason: "dịch lại chương")
    }

    /// Bỏ mọi thứ dịch sẵn của truyện đang phát; đang phát (đúng `onlyChapter` nếu có) ⇒ tải chương hiện tại và đọc lại
    /// từ đầu đoạn đang đọc. Lần đổi sau chồng lên lần trước thì lượt đọc lại cũ tự bỏ (`preparationGeneration`).
    func rereadCurrentChapterForTranslationChange(onlyChapter: Int?, reason: String) {
        invalidatePreparedTranslationState()
        guard isPlaying,
              onlyChapter == nil || onlyChapter == playingChapterIndex,
              let chapter = chaptersQueue.first(where: { $0.index == playingChapterIndex }) else { return }

        let bookId = playingBookId
        let generation = preparationGeneration
        let paragraphIndex = currentParentParagraphIndex
        let request = ChapterContentRequest(
            bookId: bookId,
            chapterIndex: chapter.index,
            title: chapter.title,
            url: chapter.url,
            host: chapter.host,
            bookMetadata: nil,
            extensionInfo: extensionInfo,
            forceRefresh: false
        )
        AppLogger.shared.log("🌐 [ExtTranslate] TTS đọc lại chương \(chapter.index + 1) (\(reason))")
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let result = try await ChapterContentRepository.shared.load(request)
                guard self.playingBookId == bookId,
                      self.playingChapterIndex == chapter.index,
                      self.preparationGeneration == generation,
                      self.isPlaying else { return }
                self.startSpeaking(
                    bookId: bookId,
                    chapters: self.chaptersQueue,
                    currentIndex: chapter.index,
                    chapterContent: result.document.text.content,
                    startParagraphIndex: paragraphIndex,
                    bookTitle: self.bookTitle,
                    coverUrl: self.playingCoverUrl,
                    bookDetailUrl: self.playingBookDetailUrl,
                    bookSourceName: self.playingBookSourceName,
                    extensionInfo: self.extensionInfo,
                    translationPackageId: self.sessionTranslationPackageId,
                    author: self.playingAuthor,
                    translationEnabled: self.sessionTranslationEnabled
                )
            } catch {
                guard self.playingBookId == bookId else { return }
                AppLogger.shared.log("❌ [TTSManager] Không đọc lại được chương sau khi \(reason): \(error.localizedDescription)")
            }
        }
    }
}
