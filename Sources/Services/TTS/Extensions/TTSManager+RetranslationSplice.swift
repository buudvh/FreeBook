import Foundation

/// Nối bản dịch mới vào chương TTS đang đọc trong **một** nhịp main (xem `TTSManager+Retranslation`).
///
/// - Mốc `L` = dòng của chunk **xa nhất đã cam kết tiếng**: chunk đang đọc / đang chuẩn bị (`currentParagraphIndex`, có thể
///   đã sang dòng sau trong lúc `currentParentParagraphIndex` còn ở dòng cũ) và, với NghiTTS / VieNeu, chunk hàng đợi đang
///   phát + chunk đã xếp sẵn (`nextItem` được hẹn giờ phát trên phần cứng — bàn giao có thể nghe thấy trước khi main kịp
///   nhảy chỉ số, huỷ nó là cắt tiếng). Mọi chunk của dòng ≤ `L` giữ nguyên ⇒ `currentParagraphIndex` không đổi.
/// - Chunk mới = `playbackParagraphs(from:)` (cùng `NghiUtteranceSegmenter.expand` như lúc dựng chương) lọc dòng > `L`.
/// - Tiếng đã nạp / đang nạp chỉ bỏ ở **chỉ số có chữ đổi** (so chữ + kiểu ranh giới tại cùng chỉ số): đổi một tên ở cuối
///   chương thì cửa sổ nạp trước phía trước vẫn giữ.
/// - `chapterContent` / `normalizedChapterText` thành bản **trộn** (dòng ≤ `L` chữ đang đọc, dòng sau chữ mới) — đúng chữ TTS
///   đọc, để `resumeAfterSettings` (dựng lại từ `normalizedChapterText`) không đưa bản cũ quay lại phần sau và không đổi chữ
///   dòng ≤ `L`.
/// - Reader luôn hiện bản mới (2026-11-20) và tô **cả đoạn** khi chữ dòng TTS đang đọc khác chữ đang hiện. Dòng ≤ `L` có
///   chữ TTS khác bản mới ghi vào `TTSRetranslationCoordinator.recordStaleLines` kèm bản mới đầy đủ ⇒ lùi / tua về đó thì
///   thay cả chương (`+RetranslationRewind`).
extension TTSManager {
    func applyRetranslatedChapter(_ processed: ProcessedChapterDTO, startUptime: TimeInterval, reason: String) {
        let old = paragraphs
        let fresh = playbackParagraphs(from: processed.paragraphs)
        let boundary = retranslationBoundaryLineId(in: old)
        let spliceIndex = old.firstIndex { $0.paragraphIndex > boundary } ?? old.count
        let freshTail = fresh.filter { $0.paragraphIndex > boundary }
        let spliced = Array(old[..<spliceIndex]) + freshTail

        // Chỉ số có tiếng không còn dùng được: ngoài mảng mới, hoặc chữ / kiểu ranh giới khác tại cùng chỉ số.
        var changed = Set<Int>()
        for index in spliceIndex..<max(old.count, spliced.count) {
            let sameAudio = index < old.count && index < spliced.count
                && old[index].text == spliced[index].text
                && old[index].boundaryKind == spliced[index].boundaryKind
            if !sameAudio { changed.insert(index) }
        }

        // Chữ từng dòng: dòng ≤ mốc giữ chữ đang đọc, dòng sau dùng chữ mới. `stale` = dòng ≤ mốc có chunk chữ khác bản mới.
        let oldLines = normalizedChapterText.lines
        let freshLines = ChapterTextNormalizer.normalizeProcessedContent(processed.normalizedContent).lines
        var freshTextById: [Int: String] = [:]
        for line in freshLines { freshTextById[line.id] = line.text }
        var stale: [Int: String] = [:]
        for line in oldLines where line.id <= boundary && freshTextById[line.id] != line.text {
            stale[line.id] = line.text
        }
        // Tiêu đề (-1) luôn ≤ mốc ⇒ chunk tiêu đề giữ nguyên; tên chương TTS (`chapterTitle`) cũng giữ cho khớp chunk đó.
        if old.contains(where: { $0.paragraphIndex == -1 }) {
            let oldTitle = chapterTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if oldTitle != processed.chapterTitle.trimmingCharacters(in: .whitespacesAndNewlines) {
                stale[-1] = oldTitle
            }
        }
        let mergedEntries = oldLines.filter { $0.id <= boundary }.map { (id: $0.id, text: $0.text) }
            + freshLines.filter { $0.id > boundary }.map { (id: $0.id, text: $0.text) }
        let mergedContent = ChapterTextNormalizer.reconstructContentPreservingLineIDs(from: mergedEntries)

        // ---- Một nhịp: đổi chữ + bỏ tiếng của chỉ số đổi + công bố dòng chữ cũ. ----
        paragraphs = spliced
        chapterContent = mergedContent
        normalizedChapterText = ChapterTextNormalizer.normalizeProcessedContent(mergedContent)
        if !changed.isEmpty {
            invalidateRetranslatedChunks(changed)
        }
        // Sau `chapterContent = …` (didSet đã xoá tập cũ).
        TTSRetranslationCoordinator.shared.recordStaleLines(
            Set(stale.keys),
            full: TTSRetranslationCoordinator.FullRetranslation(
                token: processed.translationToken,
                inputs: currentRetranslationInputs(),
                baseParagraphs: processed.paragraphs,
                content: processed.normalizedContent,
                title: processed.chapterTitle
            )
        )
        let elapsedMs = Int((ProcessInfo.processInfo.systemUptime - startUptime) * 1000)
        let firstChanged = changed.min().map { "\($0)" } ?? "—"
        AppLogger.shared.log(
            "🔁 [TTSRetranslate] chương=\(playingChapterIndex + 1) lý do=\(reason) L=\(boundary) splice=\(spliceIndex) "
                + "chunk cũ=\(old.count) mới=\(spliced.count) đổi=\(changed.count) từ=\(firstChanged) "
                + "dòng chữ cũ=\(stale.count) engine=\(tool) đang phát=\(isPlaying ? "có" : "không") ms=\(elapsedMs)"
        )
        if !changed.isEmpty {
            updatePrefetchWindow() // đang tạm dừng ⇒ no-op; `resume` / `speakCurrent` tự nạp lại.
        }
    }

    /// Id dòng cuối cùng giữ chữ cũ (xem doc của extension).
    private func retranslationBoundaryLineId(in chunks: [TTSParagraph]) -> Int {
        var committed = currentParagraphIndex
        if TTSManager.isLocalEngine(tool) {
            committed = max(
                committed,
                nghiAudioPlayerQueue.currentItem?.paragraphIndex ?? -1,
                nghiAudioPlayerQueue.nextItem?.paragraphIndex ?? -1
            )
        }
        committed = min(committed, chunks.count - 1)
        guard committed >= 0 else { return currentParentParagraphIndex }
        return max(currentParentParagraphIndex, chunks[committed].paragraphIndex)
    }

    /// Bỏ tiếng đã nạp + lượt đang nạp của các chỉ số đổi chữ. Chỗ ghi tiếng còn tự so chữ trước khi ghi (`startPrefetchTask`,
    /// nạp gộp Google, lượt thử online, refill NghiTTS) — huỷ ở đây để giải phóng hàng đợi tổng hợp, không phải hàng rào duy nhất.
    private func invalidateRetranslatedChunks(_ changed: Set<Int>) {
        for index in Array(preloadedData.keys) where changed.contains(index) {
            preloadedData.removeValue(forKey: index)
        }
        for index in Array(preloadedDurations.keys) where changed.contains(index) {
            preloadedDurations.removeValue(forKey: index)
        }

        // Remote: một task gộp Google phủ nhiều chỉ số ⇒ huỷ cả task nếu nó phủ chỉ số đổi; gỡ mọi chỉ số của nó (phần dọn
        // của task so generation nên không xoá nhầm task mới cùng chỉ số), `updatePrefetchWindow` nạp lại phần còn thiếu.
        let staleTasks = Set(prefetchTasks.filter { changed.contains($0.key) }.map(\.value))
        if !staleTasks.isEmpty {
            for (index, task) in Array(prefetchTasks) where staleTasks.contains(task) {
                task.cancel()
                prefetchTasks.removeValue(forKey: index)
                prefetchTaskGenerations.removeValue(forKey: index)
            }
        }
        onlineFallback.forgetChunks(changed, session: sessionID, chapterIndex: playingChapterIndex)

        if TTSManager.isLocalEngine(tool) {
            // Gỡ tay từng refill là sai: `defer` của task đã huỷ (generation chưa đổi) sẽ xoá nhầm task mới cùng chỉ số ⇒ huỷ
            // cả lượt (bump generation). Không có refill nào dính chỉ số đổi ⇒ chỉ quên đoạn rỗng / lỗi (theo chữ cũ).
            if nghiRefillInFlightIndices.contains(where: { changed.contains($0) }) {
                cancelNghiRefill()
            } else {
                clearNghiRefillFailureStates()
            }
        }
    }
}
