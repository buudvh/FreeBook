import Foundation

/// Đổi nguồn lúc đang nghe truyện cũ (1.3.946, anh Bửu chọn "tự chuyển nghe sang truyện mới"). Trước đây đang nghe thì
/// lượt đổi nguồn **giữ** truyện cũ để khỏi ngắt quãng ⇒ hai truyện tách đôi: TTS và Reader mở từ đĩa nghe vẫn là truyện
/// cũ, VP / Name riêng lưu lúc đó vào truyện cũ, truyện mới không bao giờ nhận được.
///
/// 1.3.1063 (anh Bửu: "nghe xong đoạn đang phát và phát đoạn tiếp theo (đoạn chứ không phải chunk)"): bản 1.3.946 dừng
/// phiên rồi đọc lại từ đầu dòng ⇒ tiếng bị cắt giữa câu, im 1–3 s, nghe lại cả dòng. Nay phiên (đang phát **hoặc** tạm
/// dừng) chuyển sang truyện mới **tại chỗ** — không đổi `sessionID` / `ttsProcessingGeneration`, không bỏ bộ đệm — rồi nối
/// chữ của nguồn mới từ **dòng sau** dòng đang đọc bằng chính lượt nối của dịch lại (`TTSManager+RetranslationSplice`).
/// Chương đã tải được chép nguyên văn ⇒ chữ trùng, không bỏ tiếng nào, chuyển liền mạch.
extension TTSManager {
    /// `BookSourceChangeCoordinator` gọi ngay sau mốc chốt và **chờ** Task trả về xong rồi mới dọn truyện cũ:
    /// `deleteBooksAsync` bỏ qua truyện TTS đang phát ⇒ dọn lúc phiên còn ở truyện cũ là giữ lại vĩnh viễn một bản trùng.
    /// Bình thường Task xong ngay (một nhịp main); chỉ chờ lâu khi đúng lúc đó một lượt dựng chương đang chạy.
    @discardableResult
    func continueListeningAfterSourceChange(
        fromBookId oldBookId: String,
        toBookId newBookId: String,
        source: BookSourceChangeCoordinator.SourceSnapshot,
        ext: Extension
    ) -> Task<Void, Never>? {
        guard !oldBookId.isEmpty, playingBookId == oldBookId, showFloatingWidget || isPlaying else { return nil }
        let queue = source.chapters.map { TTSChapterInfo(title: $0.title, url: $0.url, index: $0.index, host: $0.host) }
        let extensionInfo = TTSExtensionInfo(
            packageId: ext.packageId, localPath: ext.localPath, downloadUrl: ext.downloadUrl, configJson: ext.configJson
        )
        let book = source.createSnapshot
        return Task { @MainActor [weak self] in
            guard let self else { return }
            // Đang chuyển chương / vừa bấm nghe: lượt đó đóng dấu truyện cũ + mục lục cũ (đổi giữa chừng là nó tự bỏ ⇒ im
            // tiếng) ⇒ để nó xong rồi mới chuyển, như lượt dịch lại.
            await self.awaitChapterBuildsInFlight()
            // Người dùng đã dừng / mở truyện khác trong lúc chờ ⇒ thôi.
            guard self.playingBookId == oldBookId, self.showFloatingWidget || self.isPlaying else { return }
            let chapterIndex = self.playingChapterIndex
            guard queue.contains(where: { $0.index == chapterIndex }) else {
                AppLogger.shared.log("❌ [SourceChange] Nguồn mới không có chương \(chapterIndex + 1) ⇒ dừng nghe")
                self.stop()
                TTSPresentationEventCenter.shared.send(.showToast(
                    message: "Nguồn mới không có chương \(chapterIndex + 1) — đã dừng nghe", type: .error
                ))
                return
            }
            guard self.isChunkLayoutCurrent else {
                AppLogger.shared.log("[SourceChange] TTS chưa dựng xong chương ⇒ dừng phiên của truyện cũ \(oldBookId)")
                self.stop()
                TTSPresentationEventCenter.shared.send(.showToast(
                    message: "Đã chuyển sang nguồn mới — bấm nghe để đọc tiếp", type: .info
                ))
                return
            }
            self.handOffSession(toBookId: newBookId, queue: queue, extensionInfo: extensionInfo, book: book)
            AppLogger.shared.log(
                "[SourceChange] TTS chuyển tại chỗ \(oldBookId) → \(newBookId), chương \(chapterIndex + 1), "
                    + "dòng \(self.currentParentParagraphIndex), đang phát=\(self.isPlaying ? "có" : "không")"
            )
            // Chữ của nguồn mới từ dòng sau dòng đang đọc — cả khi truyện tắt dịch, không gộp sự kiện.
            self.scheduleChapterRetranslation(reason: "đổi nguồn", evenWithoutTranslation: true, debounceNanoseconds: 0)
        }
    }

    /// `bookId` đóng dấu trên việc đang bay (context phát, task phát NghiTTS / VieNeu, refill, nạp trước remote) vẫn là
    /// truyện đang phát: bằng `playingBookId`, hoặc là truyện cũ của lần đổi nguồn tại chỗ **trong chính phiên này** —
    /// thiếu nó thì chunk đang phát xong không gọi được đoạn kế (im luôn) và tiếng đang nạp bị vứt. Chỗ kiểm mới của việc
    /// đang bay theo truyện / link chương thì dùng hàm này / `isPlayingChapterUrl`.
    func isPlayingBook(_ bookId: String) -> Bool {
        if bookId == playingBookId { return true }
        guard !playingBookId.isEmpty, let former = sourceChangeFormerBook else { return false }
        return former.sessionID == sessionID && former.bookId == bookId
    }

    /// Như `isPlayingBook` cho link chương đóng dấu trên việc đang bay: link nguồn cũ của chương đang đọc lúc đổi nguồn tại
    /// chỗ vẫn khớp trong chính phiên này (bên gọi kiểm thêm `playingChapterIndex` ⇒ sang chương sau là hết khớp).
    func isPlayingChapterUrl(_ url: String) -> Bool {
        if url == playingChapterUrl { return true }
        guard !playingBookId.isEmpty, let former = sourceChangeFormerBook else { return false }
        return former.sessionID == sessionID && former.chapterUrl == url
    }

    /// Đổi danh tính phiên sang truyện mới trong **một** nhịp main. `playingChapterUrl` = link chương đang đọc trong mục lục
    /// mới (bất biến chung: `ProtectedTTSChapter` khi làm mới mục lục truyện mới dò theo nó); link cũ nằm trong
    /// `sourceChangeFormerBook` cho việc đang bay. Lượt tổng hợp đang bay mang khoá tính theo link cũ ⇒ lượt mới cùng đoạn
    /// không gộp được với nó (chỉ vài đoạn quanh lúc chuyển, không sai tiếng).
    private func handOffSession(
        toBookId newBookId: String,
        queue: [TTSChapterInfo],
        extensionInfo: TTSExtensionInfo,
        book: TOCBookCreateSnapshot
    ) {
        sourceChangeFormerBook = (sessionID: sessionID, bookId: playingBookId, chapterUrl: playingChapterUrl)
        if let chapterUrl = queue.first(where: { $0.index == playingChapterIndex })?.url {
            playingChapterUrl = chapterUrl
        }
        let packageId = extensionInfo.packageId
        sessionTranslationPackageId = packageId
        sessionTranslationEnabled = TranslationConfigStore.shared.isTranslationEnabled(bookId: newBookId, packageId: packageId)
        sessionShouldConvertTraditionalToSimplified = TranslationConfigStore.shared.convertsTraditionalToSimplified(
            bookId: newBookId, packageId: packageId
        )
        playingBookId = newBookId
        chaptersQueue = queue
        self.extensionInfo = extensionInfo
        bookTitle = book.title
        playingCoverUrl = book.coverUrl
        playingAuthor = book.author
        playingBookDetailUrl = book.detailUrl
        playingBookSourceName = book.sourceName

        // Chủ mảng chunk ⇒ truyện mới (`isChunkLayoutCurrent` cho lượt nối, tua đoạn, sheet nghe mini).
        noteParagraphsReplaced()
        // Chương chuẩn bị sẵn, chương kế nạp trước, đầu chương kế, Now Playing đều theo truyện cũ / mục lục cũ.
        invalidatePreparedTranslationState()
        publishLifecycleState(isPlaying: isPlaying)
        Task { await ReadingProgressStore.shared.claim(bookId: newBookId, owner: .tts) }
        checkpointProgress()
    }
}
