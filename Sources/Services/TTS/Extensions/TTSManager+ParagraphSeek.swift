import Foundation

/// Tua theo **đoạn** (dòng cha `TTSParagraph.paragraphIndex`) từ vạch tiến độ của sheet nghe mini (2026-11-19, anh Bửu:
/// "không tua thời gian mà tua theo đoạn"). Màn khoá (`TTSManager+NowPlaying`) giữ nguyên, không tua.
extension TTSManager {
    /// Số chunk quanh đích được giữ tiếng đã nạp của NghiTTS / VieNeu (đoạn kế bắt buộc + tối đa 4 dự trữ của VieNeu + dư).
    private static let seekKeptPrefetchSpan = 6

    /// Nhảy tới **chunk đầu** của dòng `lineId`. Khuôn `skipForward` nhưng chạy được cả khi đang tạm dừng (khác `skipBackward`
    /// có `guard isPlaying`): đang phát ⇒ đọc từ đầu dòng đó; đang dừng ⇒ chỉ dời chỗ + cập nhật trạng thái (Reader / sheet /
    /// Now Playing), bấm phát mới đọc.
    public func seekToParagraph(lineId: Int) {
        guard let target = paragraphs.firstIndex(where: { $0.paragraphIndex == lineId }) else { return }
        // Vừa đọc hết chunk cuối, chương kế đang tải / tổng hợp: không huỷ thì lượt chuyển chương (kiểm phiên / generation /
        // chương vẫn khớp) nhảy sang chương sau giữa đoạn người dùng vừa tua tới. Như `pause()`.
        cancelChapterAdvanceTask()
        finishTTSAutoAdvancePerf(outcome: "cancelled", endpoint: "seek")
        let from = currentParagraphIndex
        stopCurrentPlayback() // tắt tiếng + bỏ chunk đã xếp sẵn của hàng đợi Nghi
        // Lượt tổng hợp / phát của chỗ cũ: đang dừng mà còn task phát Nghi thì `resume()` rẽ nhánh `nghiPlaybackTask != nil`
        // và chờ một task đã chết ⇒ im tiếng.
        cancelNghiPlaybackTask()
        remotePlaybackTask?.cancel()
        remotePlaybackTask = nil
        remotePlaybackTaskGeneration &+= 1
        onlineFallback.cancelHedge()
        dropLocalPrefetchOutsideSeekWindow(target)

        currentParagraphIndex = target
        currentParentParagraphIndex = paragraphs[target].paragraphIndex
        highlightRange = nil
        checkpointProgress()
        AppLogger.shared.log("⏩ [TTSSeek] Tua tới dòng \(lineId) (chunk \(from) → \(target)/\(paragraphs.count), đang phát=\(isPlaying ? "có" : "không"))")
        if isPlaying {
            speakCurrent()
        } else {
            publishLifecycleState(isPlaying: false)
            updateNowPlayingInfo()
        }
    }

    /// NghiTTS / VieNeu: refill ngoài cửa sổ mới chiếm hết luồng nạp trước (`fillNghiRefillUpToCapacity`) ⇒ huỷ cả lượt
    /// (bump generation, không gỡ tay từng task); tiếng đã nạp ngoài cửa sổ bị tính vào trần dự trữ ⇒ bỏ. Remote tự dọn cửa sổ
    /// ở `updatePrefetchWindow` khi chunk mới bắt đầu phát.
    private func dropLocalPrefetchOutsideSeekWindow(_ target: Int) {
        guard TTSManager.isLocalEngine(tool) else { return }
        let window = target...(target + Self.seekKeptPrefetchSpan)
        if nghiRefillInFlightIndices.contains(where: { !window.contains($0) }) {
            cancelNghiRefill()
        }
        for index in Array(preloadedData.keys) where !window.contains(index) {
            preloadedData.removeValue(forKey: index)
            preloadedDurations.removeValue(forKey: index)
        }
    }
}
