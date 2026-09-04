import Foundation

/// Nạp trước **gộp nhiều đoạn trong một request** cho Google TTS, và phần dọn task nạp trước dùng
/// chung cho mọi engine remote.
///
/// Vì sao chỉ Google: API `generateAudioDocStream` nhận `textParts` là mảng và trả về một `audio` cho
/// **mỗi** part (đo trên thiết bị thật: 1 đoạn ≈ 370 ms, 10 đoạn/1 request ≈ 735 ms). Ext TTS đi qua
/// `execute(text, voice)` của JavaScript — một lần gọi một đoạn, không có chỗ để gộp.
///
/// Bất biến giữ nguyên: mọi lượt tổng hợp remote vẫn đi qua `RemoteTTSSynthesisCoordinator` (một lượt
/// tại một thời điểm), và **retry vẫn chỉ ở một tầng** — bên trong `GoogleTTSService`.
@MainActor
extension TTSManager {

    /// Một lượt gộp: các đoạn **liền kề trong cửa sổ** còn thiếu audio và có text khác rỗng.
    internal struct GoogleBatchPrefetch {
        let indices: [Int]
        let texts: [String]
        /// Khoá cho coordinator — nối khoá từng đoạn nên hai lượt gộp giống nhau tự dedupe.
        let key: String
    }

    /// Dọn task nạp trước ngoài cửa sổ. **Không** huỷ task còn phục vụ một index trong cửa sổ: một task
    /// gộp nằm ở nhiều index, và cửa sổ trượt một nhịp là nó rơi ra khỏi index cũ nhất — huỷ theo index
    /// sẽ giết luôn phần đang cần cho các đoạn còn lại.
    internal func pruneRemotePrefetchTasks(keeping targetIndices: [Int]) {
        let keep = Set(targetIndices)
        let keptTasks = Set(prefetchTasks.filter { keep.contains($0.key) }.map { $0.value })

        for (index, task) in Array(prefetchTasks) where !keep.contains(index) {
            if !keptTasks.contains(task) {
                task.cancel()
            }
            prefetchTasks.removeValue(forKey: index)
            prefetchTaskGenerations.removeValue(forKey: index)
        }
    }

    /// Cửa vào duy nhất của việc xếp hàng nạp trước cho engine remote.
    internal func dispatchRemotePrefetch(for targetIndices: [Int]) {
        let missing = targetIndices.filter { preloadedData[$0] == nil && prefetchTasks[$0] == nil }
        guard !missing.isEmpty else { return }

        guard tool == "google",
              let batch = makeGoogleBatch(for: missing),
              batch.indices.count >= 2 else {
            for index in missing {
                startPrefetchTask(for: index)
            }
            return
        }

        startGoogleBatchPrefetch(batch)

        // Đoạn bị loại khỏi lượt gộp (text rỗng sau khi áp quy tắc thay thế) vẫn đi đường một-đoạn;
        // `startPrefetchTask` tự bỏ qua text rỗng nên đây là no-op cho chúng, không phải đường chết.
        let batched = Set(batch.indices)
        for index in missing where !batched.contains(index) {
            startPrefetchTask(for: index)
        }
    }

    /// `nil` khi không gom được gì. Text lấy **đúng** cách của `startPrefetchTask` để hai đường không
    /// bao giờ tổng hợp hai chuỗi khác nhau cho cùng một đoạn.
    private func makeGoogleBatch(for indices: [Int]) -> GoogleBatchPrefetch? {
        var batchIndices: [Int] = []
        var texts: [String] = []
        var keys: [String] = []

        for index in indices {
            guard index >= 0, index < paragraphs.count else { continue }
            let text = TTSReplacementManager.shared.applyReplacements(to: paragraphs[index].text)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            batchIndices.append(index)
            texts.append(text)
            keys.append(
                TTSSynthesisIdentity.computeKey(
                    chapterURL: playingChapterUrl,
                    chapterIndex: playingChapterIndex,
                    paragraphIndex: index,
                    finalText: text,
                    engine: "google",
                    voice: selectedVoice,
                    googlePitch: pitch,
                    extensionFingerprint: nil
                )
            )
        }

        guard !batchIndices.isEmpty else { return nil }
        return GoogleBatchPrefetch(
            indices: batchIndices,
            texts: texts,
            key: "gbatch|" + keys.joined(separator: "|")
        )
    }

    private func startGoogleBatchPrefetch(_ batch: GoogleBatchPrefetch) {
        nextPrefetchTaskGeneration += 1
        let taskGen = nextPrefetchTaskGeneration
        for index in batch.indices {
            prefetchTaskGenerations[index] = taskGen
        }

        let expectedSessionID = sessionID
        let expectedBookId = playingBookId
        let expectedChapterIndex = playingChapterIndex
        let expectedChapterURL = playingChapterUrl
        let voice = selectedVoice
        let pitchToUse = pitch
        let toolBeforeStart = tool
        let service = googleService
        let worker = audioSynthesisWorker
        let delayMs = prefetchDelayMs
        let offset = max(0, (batch.indices.first ?? 0) - currentParagraphIndex)
        let totalCharacters = batch.texts.reduce(0) { $0 + $1.count }
        // Chỉ đưa **mảng chuỗi** vào closure `@Sendable` của worker, không đưa cả `batch`: giữ phần
        // băng qua ranh giới isolation ở mức kiểu đơn giản, khỏi phụ thuộc suy luận Sendable của struct.
        let batchTexts = batch.texts

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.finishBatchPrefetch(batch.indices, taskGen: taskGen) }

            @MainActor
            func isValidSession() -> Bool {
                if Task.isCancelled { return false }
                if !self.isPlaying { return false }
                if self.sessionID != expectedSessionID { return false }
                if self.playingBookId != expectedBookId { return false }
                if self.playingChapterIndex != expectedChapterIndex { return false }
                if self.playingChapterUrl != expectedChapterURL { return false }
                if self.selectedVoice != voice { return false }
                if self.tool != toolBeforeStart { return false }
                return true
            }

            guard isValidSession() else { return }

            do {
                let packed = try await worker.synthesizeParagraph(
                    synthesisKey: batch.key,
                    engine: toolBeforeStart,
                    textLength: totalCharacters,
                    priority: .prefetch,
                    offset: offset,
                    prefetchDelayMs: delayMs
                ) {
                    let audios = try await service.synthesizeBatch(
                        parts: batchTexts,
                        voice: voice,
                        speed: 1.0,
                        pitch: pitchToUse
                    )
                    return TTSBatchAudioPayload.encode(audios)
                }

                guard isValidSession() else { return }

                guard let audios = TTSBatchAudioPayload.decode(packed),
                      audios.count == batch.indices.count else {
                    AppLogger.shared.log("⚠️ [TTSPerf] BatchPayloadInvalid chapter=\(expectedChapterIndex) indices=\(batch.indices.count)")
                    self.fallbackToPerParagraphPrefetch(batch.indices)
                    return
                }

                for (position, index) in batch.indices.enumerated() {
                    self.preloadedData[index] = audios[position]
                }
                if AppLogger.shared.isLoggingEnabled {
                    AppLogger.shared.log("[TTSPerf] BatchPrefetch chapter=\(expectedChapterIndex) count=\(batch.indices.count) chars=\(totalCharacters)")
                }
            } catch is CancellationError {
                return
            } catch {
                guard isValidSession() else { return }
                AppLogger.shared.log("⚠️ [TTSPerf] BatchPrefetchFailure chapter=\(expectedChapterIndex) count=\(batch.indices.count): \(error.localizedDescription)")
                self.fallbackToPerParagraphPrefetch(batch.indices)
            }
        }

        for index in batch.indices {
            prefetchTasks[index] = task
        }
    }

    /// Một lượt gộp thất bại **không** được làm mất cả cửa sổ: quay về một-đoạn-một-request cho đúng
    /// những index đó. `startPrefetchTask` tự bump generation nên phần dọn của task gộp không xoá đè.
    private func fallbackToPerParagraphPrefetch(_ indices: [Int]) {
        for index in indices where preloadedData[index] == nil {
            startPrefetchTask(for: index)
        }
    }

    private func finishBatchPrefetch(_ indices: [Int], taskGen: UInt64) {
        for index in indices where prefetchTaskGenerations[index] == taskGen {
            prefetchTasks.removeValue(forKey: index)
            prefetchTaskGenerations.removeValue(forKey: index)
        }
        checkAndPromoteNextChapterAudioIfNeeded()
    }
}
