import Foundation

extension TTSManager {
    internal func playGoogleTTS(_ text: String) {
        let index = currentParagraphIndex
        let voice = selectedVoice
        let pitchToUse = pitch
        let playbackId = String(UUID().uuidString.prefix(4))
        self.currentPlaybackId = playbackId
        let expectedSessionID = sessionID
        let expectedChapterIndex = playingChapterIndex
        let expectedChapterURL = playingChapterUrl
        let service = googleService
        let synthesisKey = TTSSynthesisIdentity.computeKey(
            chapterURL: expectedChapterURL,
            chapterIndex: expectedChapterIndex,
            paragraphIndex: index,
            finalText: text,
            engine: "google",
            voice: voice,
            googlePitch: pitchToUse,
            extensionFingerprint: nil
        )

        let context = makePlaybackContext(paragraphIndex: index, playbackId: playbackId, engine: "google")
        if let cachedData = preloadedData[index] {
            recordPrefetchResult(sessionID: expectedSessionID, chapterIndex: expectedChapterIndex, engine: "google", index: index, outcome: "hit")
            self.playAudioData(cachedData, context: context)
            updatePrefetchWindow()
            return
        }

        let wasPrefetching = prefetchTasks[index] != nil
        remotePlaybackTask?.cancel()
        remotePlaybackTaskGeneration &+= 1
        let taskGeneration = remotePlaybackTaskGeneration
        let startWait = ProcessInfo.processInfo.systemUptime

        let audioSynthesisWorkerRef = self.audioSynthesisWorker

        remotePlaybackTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.remotePlaybackTaskGeneration == taskGeneration {
                    self.remotePlaybackTask = nil
                }
            }

            do {
                let mp3Data = try await audioSynthesisWorkerRef.synthesizeParagraph(
                    synthesisKey: synthesisKey,
                    engine: "google",
                    textLength: text.count,
                    priority: .current,
                    offset: 0,
                    prefetchDelayMs: 0
                ) {
                    try await service.synthesize(text: text, voice: voice, speed: 1.0, pitch: pitchToUse)
                }

                guard !Task.isCancelled,
                      self.isContextValid(context),
                      self.currentPlaybackId == playbackId,
                      self.selectedVoice == voice else { return }

                let waitMs = (ProcessInfo.processInfo.systemUptime - startWait) * 1000
                self.recordPrefetchResult(
                    sessionID: expectedSessionID,
                    chapterIndex: expectedChapterIndex,
                    engine: "google",
                    index: index,
                    outcome: wasPrefetching ? "hit_wait" : "miss",
                    waitMs: wasPrefetching ? waitMs : 0
                )
                self.playAudioData(mp3Data, context: context)
                self.updatePrefetchWindow()
            } catch is CancellationError {
                return
            } catch {
                guard self.currentPlaybackId == playbackId else { return }
                if index == 0 && self.activeTTSAutoAdvancePerf?.chapterIndex == self.playingChapterIndex {
                    let synMs = self.currentParagraph0SynthesisMs()
                    self.finishTTSAutoAdvancePerf(
                        outcome: "synthesis_failed",
                        endpoint: "error",
                        sessionID: self.sessionID,
                        generation: self.ttsProcessingGeneration,
                        chapterIndex: self.playingChapterIndex,
                        synthesisMs: synMs
                    )
                }
                AppLogger.shared.log("❌ Lỗi Google Cloud TTS: \(error.localizedDescription)")
                self.preloadedData.removeValue(forKey: index)
                self.currentPlaybackId = nil
                self.pause()
                TTSPresentationEventCenter.shared.send(.showToast(message: "Lỗi Google TTS: \(error.localizedDescription). Tạm dừng đọc.", type: .error))
            }
        }
    }

    internal func playExtensionTTS(_ text: String) {
        let index = currentParagraphIndex
        let voice = selectedVoice
        let localPath = extensionLocalPath
        let configJson = extensionConfigJson
        let playbackId = String(UUID().uuidString.prefix(4))
        self.currentPlaybackId = playbackId
        let expectedSessionID = sessionID
        let expectedChapterIndex = playingChapterIndex
        let expectedChapterURL = playingChapterUrl
        let engineName = tool
        let service = extService
        let extFingerprint = ExtensionManager.shared.getTTSRuntimeFingerprint(localPath: localPath, configJson: configJson)
        let synthesisKey = TTSSynthesisIdentity.computeKey(
            chapterURL: expectedChapterURL,
            chapterIndex: expectedChapterIndex,
            paragraphIndex: index,
            finalText: text,
            engine: engineName,
            voice: voice,
            googlePitch: nil,
            extensionFingerprint: extFingerprint
        )

        let context = makePlaybackContext(paragraphIndex: index, playbackId: playbackId, engine: engineName)
        if let cachedData = preloadedData[index] {
            recordPrefetchResult(sessionID: expectedSessionID, chapterIndex: expectedChapterIndex, engine: engineName, index: index, outcome: "hit")
            self.playAudioData(cachedData, context: context)
            updatePrefetchWindow()
            return
        }

        let wasPrefetching = prefetchTasks[index] != nil
        remotePlaybackTask?.cancel()
        remotePlaybackTaskGeneration &+= 1
        let taskGeneration = remotePlaybackTaskGeneration
        let startWait = ProcessInfo.processInfo.systemUptime

        let audioSynthesisWorkerRef = self.audioSynthesisWorker

        remotePlaybackTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.remotePlaybackTaskGeneration == taskGeneration {
                    self.remotePlaybackTask = nil
                }
            }

            do {
                let audioData = try await audioSynthesisWorkerRef.synthesizeParagraph(
                    synthesisKey: synthesisKey,
                    engine: engineName,
                    textLength: text.count,
                    priority: .current,
                    offset: 0,
                    prefetchDelayMs: 0
                ) {
                    try await service.synthesizeData(
                        text: text,
                        voice: voice,
                        localPath: localPath,
                        configJson: configJson
                    )
                }

                guard !Task.isCancelled,
                      self.isContextValid(context),
                      self.currentPlaybackId == playbackId,
                      self.selectedVoice == voice else { return }

                let waitMs = (ProcessInfo.processInfo.systemUptime - startWait) * 1000
                self.recordPrefetchResult(
                    sessionID: expectedSessionID,
                    chapterIndex: expectedChapterIndex,
                    engine: engineName,
                    index: index,
                    outcome: wasPrefetching ? "hit_wait" : "miss",
                    waitMs: wasPrefetching ? waitMs : 0
                )
                self.playAudioData(audioData, context: context)
                self.updatePrefetchWindow()
            } catch is CancellationError {
                return
            } catch {
                guard self.currentPlaybackId == playbackId else { return }
                if index == 0 && self.activeTTSAutoAdvancePerf?.chapterIndex == self.playingChapterIndex {
                    let synMs = self.currentParagraph0SynthesisMs()
                    self.finishTTSAutoAdvancePerf(
                        outcome: "synthesis_failed",
                        endpoint: "error",
                        sessionID: self.sessionID,
                        generation: self.ttsProcessingGeneration,
                        chapterIndex: self.playingChapterIndex,
                        synthesisMs: synMs
                    )
                }
                AppLogger.shared.log("❌ Lỗi Extension TTS: \(error.localizedDescription)")
                self.preloadedData.removeValue(forKey: index)
                self.currentPlaybackId = nil
                self.pause()
                TTSPresentationEventCenter.shared.send(.showToast(message: "Lỗi Extension TTS: \(error.localizedDescription). Tạm dừng đọc.", type: .error))
            }
        }
    }

    // MARK: - Displayed Metadata for UI & Widgets

    public var displayedBookTitle: String {
        let title = bookTitle.isEmpty ? "FreeBook" : bookTitle
        guard sessionTranslationEnabled && TranslateUtils.containsChinese(title) else { return title }
        return TranslateUtils.translateMeta(title, bookId: playingBookId, shouldConvertTraditionalToSimplified: sessionShouldConvertTraditionalToSimplified)
    }

    public var displayedAuthor: String {
        guard !playingAuthor.isEmpty else { return "" }
        guard sessionTranslationEnabled && TranslateUtils.containsChinese(playingAuthor) else { return playingAuthor }
        return TranslateUtils.translateMeta(playingAuthor, bookId: playingBookId, shouldConvertTraditionalToSimplified: sessionShouldConvertTraditionalToSimplified)
    }

    public var displayedChapterTitle: String {
        let raw = chapterTitle.isEmpty ? (chaptersQueue.first(where: { $0.index == playingChapterIndex })?.title ?? "Chương hiện tại") : chapterTitle
        guard sessionTranslationEnabled && TranslateUtils.containsChinese(raw) else { return raw }
        return TranslateUtils.translateChapterTitle(raw, bookId: playingBookId, shouldConvertTraditionalToSimplified: sessionShouldConvertTraditionalToSimplified)
    }

    public func displayTitle(for chapter: TTSChapterInfo) -> String {
        let raw = chapter.title
        guard sessionTranslationEnabled && TranslateUtils.containsChinese(raw) else { return raw }
        return TranslateUtils.translateChapterTitle(raw, bookId: playingBookId, shouldConvertTraditionalToSimplified: sessionShouldConvertTraditionalToSimplified)
    }

    // MARK: - Navigation Control

    public func jumpToChapter(at targetIndex: Int) {
        guard let targetChapter = chaptersQueue.first(where: { $0.index == targetIndex }) else { return }
        let currentBookId = playingBookId
        guard !currentBookId.isEmpty else { return }
        let currentCover = playingCoverUrl
        let currentBookTitle = bookTitle
        let currentAuthor = playingAuthor
        let currentDetailUrl = playingBookDetailUrl
        let currentSourceName = playingBookSourceName
        let currentExtInfo = extensionInfo
        let queue = chaptersQueue

        let targetTitle = displayTitle(for: targetChapter)
        TTSPresentationEventCenter.shared.send(.showToast(message: "Đang chuyển sang \(targetTitle)...", type: .info))

        Task { @MainActor [weak self] in
            guard let self else { return }
            let request = ChapterContentRequest(
                bookId: currentBookId,
                chapterIndex: targetIndex,
                title: targetChapter.title,
                url: targetChapter.url,
                host: targetChapter.host,
                bookMetadata: nil,
                extensionInfo: currentExtInfo,
                forceRefresh: false
            )
            do {
                let result = try await ChapterContentRepository.shared.load(request)
                guard self.playingBookId == currentBookId else { return }
                self.startSpeaking(
                    bookId: currentBookId,
                    chapters: queue,
                    currentIndex: targetIndex,
                    chapterContent: result.document.text.content,
                    startParagraphIndex: 0,
                    startTextOffset: 0,
                    bookTitle: currentBookTitle,
                    coverUrl: currentCover,
                    bookDetailUrl: currentDetailUrl,
                    bookSourceName: currentSourceName,
                    extensionInfo: currentExtInfo,
                    author: currentAuthor
                )
            } catch {
                guard self.playingBookId == currentBookId else { return }
                TTSPresentationEventCenter.shared.send(.showToast(message: "❌ Không thể tải chương: \(error.localizedDescription)", type: .error))
            }
        }
    }
}
