import Foundation

extension TTSManager {
    internal func makeNextChapterKey(for chapter: TTSChapterInfo) -> TTSPreparedNextChapterKey {
        let key = "showChapterTitle_\(playingBookId)"
        let showTitle = UserDefaults.standard.object(forKey: key) != nil ? UserDefaults.standard.bool(forKey: key) : true
        let extFingerprint: String?
        if !TTSManager.isExtensionTool(tool) {
            extFingerprint = nil
        } else {
            extFingerprint = ExtensionManager.shared.getTTSRuntimeFingerprint(
                localPath: extensionLocalPath, configJson: extensionConfigJson)
        }
        return TTSPreparedNextChapterKey(
            bookId: playingBookId, chapterIndex: chapter.index, chapterUrl: chapter.url,
            chapterHost: chapter.host, chapterTitle: chapter.title,
            tool: tool, selectedVoice: selectedVoice, googlePitch: tool == "google" ? pitch : nil,
            chunkLength: chunkLength, includeChapterTitle: showTitle,
            removeDuplicatedTitle: readRemoveDuplicatedTitle(for: playingBookId),
            isTranslationEnabled: sessionTranslationEnabled,
            shouldConvertTraditionalToSimplified: sessionShouldConvertTraditionalToSimplified,
            translationToken: TranslateUtils.translationGenerationToken(for: playingBookId),
            extensionLocalPath: extensionLocalPath, extensionConfigJson: extensionConfigJson,
            extensionFingerprint: extFingerprint)
    }

    /// Bỏ mọi thứ đã dịch sẵn theo trạng thái cũ của truyện đang phát (chương chuẩn bị trước, chunk đang claim,
    /// prefetch chương sau, metadata Now Playing) — khi từ điển, rule dịch nhanh hoặc công tắc dịch đổi.
    internal func invalidatePreparedTranslationState() {
        preparationGeneration &+= 1
        prepareSpeakingTask?.cancel()
        prepareSpeakingTask = nil
        preparedChapterKey = nil
        preparedChapter = nil
        claimedSynthesisTask?.cancel()
        claimedSynthesisTask = nil
        claimedSynthesisTaskKey = nil
        nextChapterPrefetcher.cancel()
        resetNextChapterPrefixCache()
        nowPlayingUpdateGeneration &+= 1
        nowPlayingMetadataTask?.cancel()
        nowPlayingMetadataTask = nil
        nowPlayingMetadataTaskKey = nil
        nowPlayingStaticMetadata = nil
        if showFloatingWidget {
            updateNowPlayingInfo()
        }
    }

    /// Reader vừa bật/tắt dịch cho truyện đang phát. `TTSParagraph.range` tính trên chuỗi Reader đang hiển thị, nên chữ
    /// TTS đọc phải đổi cùng Reader, nếu không vệt highlight lệch chữ: đang phát ⇒ đọc lại chương hiện tại từ đầu đoạn
    /// đang đọc theo trạng thái mới; đang dừng ⇒ chỉ áp từ chương sau (phần còn lại của chương giữ chữ cũ).
    ///
    /// Cờ phiên đổi **ngay** (trước khi tải chương) để bấm bật/tắt liên tiếp thì chỉ lượt cuối được đọc lại.
    public func updateTranslationSetting(for bookId: String, enabled: Bool) {
        guard playingBookId == bookId, sessionTranslationEnabled != enabled else { return }
        sessionTranslationEnabled = enabled
        invalidatePreparedTranslationState()
        guard isPlaying, let chapter = chaptersQueue.first(where: { $0.index == playingChapterIndex }) else { return }

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
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let result = try await ChapterContentRepository.shared.load(request)
                guard self.playingBookId == bookId,
                      self.playingChapterIndex == chapter.index,
                      self.sessionTranslationEnabled == enabled,
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
                    author: self.playingAuthor,
                    translationEnabled: enabled
                )
            } catch {
                guard self.playingBookId == bookId else { return }
                AppLogger.shared.log("❌ [TTSManager] Không đọc lại được chương sau khi đổi công tắc dịch: \(error.localizedDescription)")
            }
        }
    }
}
