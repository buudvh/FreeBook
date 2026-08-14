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
        let expectedBookID = playingBookId
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
        let expectedBookID = playingBookId
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
}
