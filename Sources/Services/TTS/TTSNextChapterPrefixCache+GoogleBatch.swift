import Foundation

/// Nhánh **gộp nhiều chunk vào một request Google** của bộ đệm prefix chương kế tiếp.
///
/// Tách sang file riêng vì `TTSNextChapterPrefixCache.swift` không có baseline dòng nên trần cứng là
/// 400. Vì vậy một số thành viên của lớp đó phải là `internal` thay vì `private` — `private` trong
/// Swift là phạm vi **file**, đúng bẫy đã làm CI đỏ ở 1.3.331.
///
/// Bất biến giữ nguyên so với đường một-chunk-một-lượt: kết quả vẫn về qua `finishSynthesis` từng
/// index (ba lớp guard `generation` / `activeKey` / `token`), và lỗi cả lượt thì rơi về `startSynthesis`
/// từng chunk thay vì tiêu một attempt của cả nhóm.
@MainActor
extension TTSNextChapterPrefixCache {

    /// Gộp prefix Google: một request cho nhiều chunk, một `Task` đứng tên **mọi** index nó phục vụ.
    ///
    /// Kết quả vẫn đi qua `finishSynthesis` từng index nên ba lớp guard (`generation`, `activeKey`,
    /// `token`) và toàn bộ luật lỗi/chặn của bộ đệm giữ nguyên. Lỗi cả lượt thì **rơi về một-chunk-một
    /// -lượt** cho đúng những index đó, thay vì tiêu một attempt của cả nhóm.
    internal func startGoogleBatchSynthesis(
        key: TTSPreparedNextChapterKey,
        indices: [Int],
        playbackParagraphs: [TTSParagraph],
        prefetchDelayMs: Int,
        googleService: GoogleTTSService,
        extService: ExtTTSService,
        audioWorker: TTSAudioSynthesisWorker
    ) {
        var batchIndices: [Int] = []
        var texts: [String] = []
        var synthesisKeys: [String] = []

        for index in indices {
            guard index < playbackParagraphs.count else { continue }
            let text = TTSReplacementManager.shared.applyReplacements(to: playbackParagraphs[index].text)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            batchIndices.append(index)
            texts.append(text)
            synthesisKeys.append(
                TTSSynthesisIdentity.computeKey(
                    chapterURL: key.chapterUrl,
                    chapterIndex: key.chapterIndex,
                    paragraphIndex: index,
                    finalText: text,
                    engine: key.tool,
                    voice: key.selectedVoice,
                    googlePitch: key.googlePitch,
                    extensionFingerprint: key.extensionFingerprint
                )
            )
        }

        guard batchIndices.count >= 2 else {
            for index in batchIndices {
                startSynthesis(
                    key: key,
                    index: index,
                    paragraph: playbackParagraphs[index],
                    prefetchDelayMs: prefetchDelayMs,
                    nghiService: nil,
                    googleService: googleService,
                    extService: extService,
                    audioWorker: audioWorker
                )
            }
            return
        }

        let expectedGeneration = generation
        nextTaskToken &+= 1
        let token = nextTaskToken
        for index in batchIndices {
            taskTokens[index] = token
        }

        let batchKey = "gbatch|" + synthesisKeys.joined(separator: "|")
        let firstIndex = batchIndices[0]

        let task = Task { @MainActor [weak self] in
            do {
                let audios = try await TTSNextChapterPrefixSynthesizer.googleBatch(
                    key: key,
                    texts: texts,
                    batchKey: batchKey,
                    offset: firstIndex,
                    prefetchDelayMs: prefetchDelayMs,
                    googleService: googleService,
                    audioWorker: audioWorker
                )
                for (position, index) in batchIndices.enumerated() {
                    self?.finishSynthesis(
                        index: index,
                        key: key,
                        token: token,
                        textToSpeak: texts[position],
                        data: audios[position],
                        error: nil,
                        expectedGeneration: expectedGeneration
                    )
                }
            } catch is CancellationError {
                return
            } catch {
                self?.recoverBatchFailure(
                    key: key,
                    indices: batchIndices,
                    playbackParagraphs: playbackParagraphs,
                    prefetchDelayMs: prefetchDelayMs,
                    googleService: googleService,
                    extService: extService,
                    audioWorker: audioWorker,
                    error: error,
                    expectedGeneration: expectedGeneration
                )
            }
        }

        for index in batchIndices {
            tasks[index] = task
        }
    }

    /// Lượt gộp hỏng: dọn chỗ rồi xếp lại từng chunk. `startSynthesis` tự cấp token mới nên
    /// `finishSynthesis` của lượt gộp không còn khớp và không xoá đè entry mới.
    private func recoverBatchFailure(
        key: TTSPreparedNextChapterKey,
        indices: [Int],
        playbackParagraphs: [TTSParagraph],
        prefetchDelayMs: Int,
        googleService: GoogleTTSService,
        extService: ExtTTSService,
        audioWorker: TTSAudioSynthesisWorker,
        error: Error,
        expectedGeneration: UInt64
    ) {
        guard generation == expectedGeneration, activeKey == key else { return }
        logFailure(key: key, index: indices.first ?? -1, attempt: 0, reason: "batch_failed", action: "retry_per_chunk")
        AppLogger.shared.log("⚠️ [TTSPerf] NextChapterPrefixBatchFailure chapter=\(key.chapterIndex) count=\(indices.count): \(error.localizedDescription)")

        for index in indices {
            tasks.removeValue(forKey: index)
            taskTokens.removeValue(forKey: index)
        }
        for index in indices where chunks[index] == nil {
            startSynthesis(
                key: key,
                index: index,
                paragraph: playbackParagraphs[index],
                prefetchDelayMs: prefetchDelayMs,
                nghiService: nil,
                googleService: googleService,
                extService: extService,
                audioWorker: audioWorker
            )
        }
    }
}
