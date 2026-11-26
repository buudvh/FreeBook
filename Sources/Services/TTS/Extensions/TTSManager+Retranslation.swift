import Combine
import Foundation

/// Sửa rule dịch / VP / Name lúc truyện đang nghe (đang phát **hoặc** tạm dừng) ⇒ TTS đọc bản dịch mới từ **dòng** (đoạn)
/// sau dòng đang đọc mà không cắt tiếng (anh Bửu, 2026-11-19). Trước đây hai observer ở `init` chỉ bỏ bản chuẩn bị sẵn
/// (`invalidatePreparedTranslationState`) ⇒ phần còn lại của chương vẫn đọc bản cũ trong khi Reader đổi chữ ⇒ lệch highlight.
/// Chỉ **tiếng** giữ chữ cũ ở dòng đang đọc — Reader luôn hiện bản mới, dòng TTS còn đọc chữ cũ được tô cả đoạn
/// (`TTSRetranslationCoordinator`, 2026-11-20); TTS không chờ Reader.
///
/// Luồng: gộp sự kiện 400 ms (rule riêng truyện bắn **cả hai** thông báo) → chờ lượt dựng chương đang chạy (nếu có) → tải
/// chương thô qua `ChapterContentRepository` + dựng lại bằng **cùng đường** dựng chương (`processChapterWithEngine`, cờ của
/// phiên) → nối trong một nhịp main (`TTSManager+RetranslationSplice`). Không bao giờ đổi `sessionID` /
/// `ttsProcessingGeneration` (đổi là lượt tổng hợp đoạn đang đọc bị bỏ ⇒ im tiếng) và không xoá cả bộ đệm.
extension TTSManager {
    /// Cấu hình dựng chương của phiên — đổi giữa chừng (đổi cài đặt, bật/tắt dịch…) ⇒ bản dịch lại không còn đúng, bỏ.
    struct RetranslationInputs: Equatable {
        let bookId: String
        let chapterIndex: Int
        let chapterUrl: String
        let packageId: String?
        let translates: Bool
        let convertsTraditional: Bool
        let chunkLength: Int
        let includeChapterTitle: Bool
        let removeDuplicatedTitle: Bool
    }

    /// Thay hai observer cũ ở `init` (cùng bộ lọc truyện / phạm vi): vẫn bỏ bản chuẩn bị sẵn ngay, rồi dịch lại chương đang đọc.
    func installTranslationChangeObservers() {
        NotificationCenter.default.publisher(for: .translationDictionariesDidUpdate)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self else { return }
                let updatedBookId = notification.userInfo?["bookId"] as? String
                let scope = notification.userInfo?["scope"] as? DictionaryInvalidationScope ?? .globalReload
                guard updatedBookId == nil || updatedBookId == self.playingBookId,
                      scope.affects(bookId: self.playingBookId) else { return }
                self.invalidatePreparedTranslationState()
                self.scheduleChapterRetranslation(reason: "từ điển")
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .quickTranslationRulesDidUpdate)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self else { return }
                let updatedBookId = notification.userInfo?["bookId"] as? String
                guard updatedBookId == nil || updatedBookId == self.playingBookId else { return }
                self.invalidatePreparedTranslationState()
                self.scheduleChapterRetranslation(reason: "rule dịch")
            }
            .store(in: &cancellables)
    }

    /// `didSet` của `paragraphs`: ghi chủ của mảng chunk (phiên / truyện / chương lúc gán) + báo sheet nghe mini dựng lại "N/M".
    func noteParagraphsReplaced() {
        TTSRetranslationCoordinator.shared.noteTTSParagraphsChanged(owner: currentChunkOwner)
    }

    private var currentChunkOwner: TTSRetranslationCoordinator.ChunkOwner {
        TTSRetranslationCoordinator.ChunkOwner(sessionID: sessionID, bookId: playingBookId, chapterIndex: playingChapterIndex)
    }

    /// `paragraphs` thuộc đúng phiên + chương đang phát. `false` ⇔ một lượt dựng chương đang chạy dở (`startSpeaking` đã đổi
    /// phiên / chương nhưng chưa gán chunk mới) hoặc đã dừng hẳn — chỉ số chunk lúc này trỏ vào chunk cũ.
    var isChunkLayoutCurrent: Bool {
        TTSRetranslationCoordinator.shared.ttsChunkOwner == currentChunkOwner
    }

    /// Chữ TTS đang đọc của dòng `lineId` (đã trim; tên chương = -1) — `ReaderTTSHighlightReader` so với chữ Reader đang hiện:
    /// khác nhau (dịch lại khi đang nghe: dòng đang đọc giữ chữ cũ, hoặc Reader chưa dựng lại vì panel đang mở) ⇒ tô cả đoạn.
    func spokenLineText(lineId: Int) -> String? {
        guard lineId >= 0 else {
            guard lineId == -1, paragraphs.first?.paragraphIndex == -1 else { return nil }
            return chapterTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let lines = normalizedChapterText.lines
        var low = 0
        var high = lines.count - 1
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].id == lineId { return lines[mid].text }
            if lines[mid].id < lineId { low = mid + 1 } else { high = mid - 1 }
        }
        return nil
    }

    func currentRetranslationInputs() -> RetranslationInputs {
        let titleKey = "showChapterTitle_\(playingBookId)"
        let showTitle = UserDefaults.standard.object(forKey: titleKey) != nil ? UserDefaults.standard.bool(forKey: titleKey) : true
        return RetranslationInputs(
            bookId: playingBookId,
            chapterIndex: playingChapterIndex,
            chapterUrl: playingChapterUrl,
            packageId: sessionTranslationPackageId,
            translates: sessionTranslationEnabled,
            convertsTraditional: sessionShouldConvertTraditionalToSimplified,
            chunkLength: chunkLength,
            includeChapterTitle: showTitle,
            removeDuplicatedTitle: readRemoveDuplicatedTitle(for: playingBookId)
        )
    }

    /// Có phiên TTS (đang phát hoặc tạm dừng) và truyện bật dịch ⇒ gộp sự kiện rồi dịch lại chương đang đọc. Tắt dịch thì
    /// từ điển / rule không đổi chữ TTS đọc ⇒ bỏ qua.
    ///
    /// Đổi nguồn tại chỗ (`TTSManager+SourceChange`) dùng chung lượt này để nối chữ của nguồn mới: `evenWithoutTranslation`
    /// (chữ đổi theo nguồn cả khi truyện tắt dịch), `debounceNanoseconds: 0` (không có sự kiện nào cần gộp).
    func scheduleChapterRetranslation(
        reason: String,
        evenWithoutTranslation: Bool = false,
        debounceNanoseconds: UInt64 = 400_000_000
    ) {
        guard showFloatingWidget, !playingBookId.isEmpty, playingChapterIndex >= 0,
              sessionTranslationEnabled || evenWithoutTranslation else { return }
        let coordinator = TTSRetranslationCoordinator.shared
        let bookId = playingBookId
        let chapterIndex = playingChapterIndex
        coordinator.retranslationTask?.cancel()
        coordinator.retranslationTask = Task { @MainActor [weak self] in
            if debounceNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: debounceNanoseconds)
            }
            guard let self, !Task.isCancelled else { return }
            await self.awaitChapterBuildsInFlight()
            guard !Task.isCancelled else { return }
            await self.retranslateCurrentChapter(
                bookId: bookId, chapterIndex: chapterIndex, reason: reason, requiresTranslation: !evenWithoutTranslation
            )
        }
    }

    /// `startSpeaking` áp kết quả dựng mà không so token ⇒ để lượt dựng chương đang chạy (đọc lại, "Nghe từ đây", bật/tắt
    /// dịch, chuyển chương) xong rồi mới dịch lại / nối trên chữ nó vừa đặt — nối vào mảng sắp bị thay thì tiếng nạp trước
    /// theo phiên mới có thể sống sót với chữ sai. Task đã xong thì `value` trả ngay (hai task này không được gán `nil` khi
    /// xong); lượt mới chen vào trong lúc chờ ⇒ chờ tiếp.
    func awaitChapterBuildsInFlight() async {
        var start: Task<Void, Never>?
        var advance: Task<Void, Never>?
        repeat {
            start = startSpeakingTask
            advance = chapterAdvanceTask
            await start?.value
            await advance?.value
        } while !Task.isCancelled && (startSpeakingTask != start || chapterAdvanceTask != advance)
    }

    /// `requiresTranslation`: lượt của từ điển / rule chỉ chạy khi phiên bật dịch; lượt đổi nguồn dựng theo cờ dịch của
    /// phiên (`inputs.translates`), bật hay tắt.
    private func retranslateCurrentChapter(
        bookId: String, chapterIndex: Int, reason: String, requiresTranslation: Bool
    ) async {
        guard playingBookId == bookId, playingChapterIndex == chapterIndex,
              sessionTranslationEnabled || !requiresTranslation,
              !paragraphs.isEmpty,
              let chapter = chaptersQueue.first(where: { $0.index == chapterIndex }) else { return }
        let startUptime = ProcessInfo.processInfo.systemUptime
        let inputs = currentRetranslationInputs()
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
        let processed: ProcessedChapterDTO
        do {
            // Cùng nguồn chữ thô với `rereadCurrentChapter` / chuyển chương (Reader cũng đưa `document.text.content`).
            let result = try await ChapterContentRepository.shared.load(request)
            try Task.checkCancellation()
            processed = try await TTSBackgroundProcessor().processChapterWithEngine(
                bookId: bookId, packageId: inputs.packageId,
                chapterIndex: chapter.index,
                chapterTitle: chapter.title,
                rawContent: result.document.text.content,
                chunkLength: inputs.chunkLength,
                shouldTranslateRawContent: inputs.translates,
                shouldConvertTraditionalToSimplified: inputs.convertsTraditional,
                includeChapterTitle: inputs.includeChapterTitle,
                removeDuplicatedTitle: inputs.removeDuplicatedTitle,
                sessionID: sessionID,
                generation: ttsProcessingGeneration
            )
        } catch is CancellationError {
            return
        } catch {
            AppLogger.shared.log("❌ [TTSRetranslate] Không dịch lại được chương \(chapterIndex + 1) (\(reason)): \(error.localizedDescription)")
            return
        }

        // Người dùng đọc lại chương trong lúc tải / dịch ⇒ nối lên chữ của lượt dựng mới.
        await awaitChapterBuildsInFlight()

        // `inputs.translates` nằm trong phép so ⇒ bật / tắt dịch giữa chừng là bỏ.
        guard !Task.isCancelled, !paragraphs.isEmpty, isChunkLayoutCurrent,
              currentRetranslationInputs() == inputs,
              TranslateUtils.translationGenerationToken(for: bookId) == processed.translationToken else {
            AppLogger.shared.log("🔁 [TTSRetranslate] Bỏ bản dịch lại chương \(chapterIndex + 1): phiên / cấu hình / từ điển đã đổi")
            return
        }
        applyRetranslatedChapter(processed, startUptime: startUptime, reason: reason)
    }
}
