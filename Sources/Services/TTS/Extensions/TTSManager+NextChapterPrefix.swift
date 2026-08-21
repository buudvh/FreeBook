import Foundation

extension TTSManager {
    /// Bối cảnh nạp prefix chương kế: chỉ hợp lệ khi DTO văn bản đã dựng xong **và**
    /// chunk 0 đã được đưa vào tổng hợp (hoặc đã xong). Nhờ điều kiện thứ hai, chunk 0
    /// luôn được xếp hàng trước các chunk prefix ở cùng mức ưu tiên.
    ///
    /// Phép chunk hoá lấy tham số **từ chính key** (không lấy giá trị hiện hành của
    /// manager), nên index của chunk prefix luôn nhất quán với key mà nó được lưu dưới.
    private func nextChapterPrefixContext() -> (key: TTSPreparedNextChapterKey, paragraphs: [TTSParagraph])? {
        let state = nextChapterPrefetcher.currentState
        let key: TTSPreparedNextChapterKey
        let processed: ProcessedChapterDTO
        switch state {
        case .synthesizingAudio(let stateKey, _, let dto, _, _, _, _),
             .audioReady(let stateKey, _, let dto, _, _, _, _):
            key = stateKey
            processed = dto
        default:
            return nil
        }

        guard key.tool != "system" else { return nil }
        if key.tool == "nghitts" {
            return (key, NghiUtteranceSegmenter.expand(processed.paragraphs, maximumLength: key.chunkLength))
        }
        return (key, processed.paragraphs)
    }

    private func requestNextChapterPrefix(capacity: Int) {
        guard let context = nextChapterPrefixContext() else { return }
        TTSNextChapterPrefixCache.shared.request(
            key: context.key,
            playbackParagraphs: context.paragraphs,
            capacity: capacity,
            prefetchDelayMs: prefetchDelayMs,
            nghiService: nghiTTSService,
            googleService: googleService,
            extService: extService,
            audioWorker: audioSynthesisWorker
        )
    }

    /// Google/Ext: mượn đúng số slot mà cửa sổ `[N, N + count]` đang bỏ trống vì chương
    /// hiện tại đã hết chunk. Trừ thêm 1 slot cho chunk 0 do `TTSChapterPrefetcher` giữ,
    /// nên tổng payload audio vẫn không vượt `count + 1` như lúc đang ở giữa chương.
    internal func requestRemoteNextChapterPrefixIfNeeded(windowCount: Int, inChapterTargetCount: Int) {
        guard isPlaying, tool != "system", tool != "nghitts" else { return }
        requestNextChapterPrefix(capacity: max(0, windowCount - inChapterTargetCount - 1))
    }

    /// NghiTTS: prefix chương kế là phần **kéo dài của cùng một watermark cached-time**.
    /// Khi chương hiện tại đã hết ứng viên mà `cachedTime` vẫn dưới ngưỡng, bộ đệm được
    /// nạp tiếp bằng chunk đầu chương kế cho tới khi đủ ngưỡng — nhưng chỉ trong phần
    /// trần `NghiSynthesisPolicy.maxTotalAudioPayloads` còn trống, nên trần payload không
    /// bị nới ra. Đạt ngưỡng thì dừng nạp và **giữ** những chunk đã có (không thu hồi).
    internal func requestNghiNextChapterPrefixIfNeeded(currentIndex: Int, blockedIndices: Set<Int>) {
        guard isPlaying, tool == "nghitts" else { return }

        let hasInChapterCandidate = TTSManager.selectNghiOptionalRefillCandidate(
            currentParagraphIndex: currentIndex,
            paragraphsCount: paragraphs.count,
            preloadedIndices: Set(preloadedData.keys),
            blockedIndices: blockedIndices
        ) != nil

        // Chương hiện tại vẫn còn chunk để nạp: nhường toàn bộ trần lại cho nó.
        guard !hasInChapterCandidate else {
            requestNextChapterPrefix(capacity: 0)
            return
        }

        guard calculateNghiCachedTime() < nghittsSafeCachedTimeThreshold else { return }

        let heldPayloads = preloadedData.count
            + (nghiAudioPlayerQueue.hasPreparedNext ? 1 : 0)
            + (nextChapterPrefetcher.reservesNghiAudioSlot ? 1 : 0)
        let capacity = max(0, NghiSynthesisPolicy.maxTotalAudioPayloads - heldPayloads)
        requestNextChapterPrefix(capacity: capacity)
    }

    /// Thời lượng chuỗi chunk prefix liên tục ngay sau chunk 0 của chương kế, dùng để
    /// `calculateNghiCachedTime()` đo được chuỗi phát liên tục **vượt qua biên chương**.
    internal func nextChapterPrefixContiguousDuration(matching key: TTSPreparedNextChapterKey) -> Double {
        TTSNextChapterPrefixCache.shared.contiguousDuration(matching: key)
    }

    /// Nhồi các chunk prefix đã sẵn sàng vào cửa sổ đoạn văn của chương vừa chuyển tới.
    /// Key được dựng lại từ chính `chapter` nên mọi thay đổi cấu hình (giọng, pitch,
    /// chunkLength, cờ dịch, từ điển) giữa lúc nạp trước và lúc chuyển chương đều làm
    /// dữ liệu cũ bị loại thay vì phát sai cấu hình.
    ///
    /// Ngoài key, mỗi chunk còn phải khớp **đúng văn bản** của `paragraphs[index]` sau
    /// `applyReplacements`. Đây là điều kiện bảo đảm highlight không thể lệch: highlight
    /// do `commitAudibleParagraphState` phát ra từ `paragraphs[index].range`, nên audio ở
    /// `index` buộc phải là audio của đúng đoạn đó. Chunk không khớp bị bỏ, chương mới
    /// tổng hợp lại như bình thường.
    internal func mergeNextChapterPrefixAudio(for chapter: TTSChapterInfo) {
        let prefix = TTSNextChapterPrefixCache.shared.consume(matching: makeNextChapterKey(for: chapter))
        guard !prefix.isEmpty else { return }

        var applied = 0
        var mismatched = 0
        for (index, chunk) in prefix where index > 0 && index < paragraphs.count {
            guard preloadedData[index] == nil else { continue }
            let expectedText = TTSReplacementManager.shared
                .applyReplacements(to: paragraphs[index].text)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard expectedText == chunk.finalText else {
                mismatched += 1
                continue
            }
            preloadedData[index] = chunk.data
            preloadedDurations[index] = WAVEncoder.duration(of: chunk.data)
            applied += 1
        }

        guard AppLogger.shared.isLoggingEnabled, applied > 0 || mismatched > 0 else { return }
        AppLogger.shared.log("[TTSPerf] NextChapterPrefixApplied chapter=\(chapter.index) engine=\(tool) chunks=\(applied) textMismatch=\(mismatched)")
    }

    /// Pause: dừng mọi tổng hợp đầu cơ nhưng giữ lại chunk đã tổng hợp xong.
    internal func cancelNextChapterPrefixWork() {
        TTSNextChapterPrefixCache.shared.cancelPendingWork()
    }

    internal func resetNextChapterPrefixCache() {
        TTSNextChapterPrefixCache.shared.reset()
    }
}
