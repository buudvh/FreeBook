import Foundation

/// **Đọc song song** đoạn đang đọc bằng giọng dự phòng khi TTS online chậm (1.3.960, anh Bửu chọn "7 s + thử lại 1 +
/// song song").
///
/// Vì sao: log thật (364 phút đọc Google / tiện ích) — lượt online thường mất 0,2–0,8 s, 5% số phút có lượt > 3 s mà phần
/// lớn vẫn **thành công** (chậm nhất 6,8 s). Timeout cứng 3 s của 1.3.953 cắt nhầm lượt sắp xong rồi chuyển cả phiên sang
/// dự phòng. Nay tách "chậm" khỏi "chết":
/// - Lượt online của đoạn đang đọc chạy với timeout theo cài đặt + 1 lần thử lại (`RemoteTTSAttemptPolicy`).
/// - Quá `TTSOnlineSynthesisSettings.fallbackHedgeDelaySeconds` chưa có tiếng ⇒ tổng hợp **song song** bằng giọng dự phòng
///   (`startOnlineFallbackHedge`); bên nào xong trước thì phát (`TTSOnlineFallbackState.claimDelivery`), bên về sau bỏ.
///   Online về trước ⇒ huỷ lượt dự phòng. Dự phòng phát rồi mà online vẫn thành công ⇒ đoạn sau vẫn đọc online.
/// - Online **hết lượt thử** ⇒ chuyển cả phiên sang dự phòng như cũ (`switchToOnlineFallback`), hoặc — nếu dự phòng đã
///   phát đoạn này — chỉ chuyển phiên, không đọc lại đoạn (`handleOnlineFailureAfterHedge`).
extension TTSManager {
    /// `playGoogleTTS` / `playExtensionTTS`, ngay trước lượt online của đoạn đang đọc (chưa bật dự phòng). Không có giọng
    /// dự phòng ⇒ không làm gì.
    func startOnlineFallbackHedge(text: String, index: Int, playbackId: String, context: TTSPlaybackContext) {
        onlineFallback.cancelHedge()
        guard TTSOnlineFallbackSettings.engine != nil, TTSOnlineFallbackSettings.isOnlineTool(tool) else { return }
        let session = sessionID
        let delay = TTSOnlineSynthesisSettings.fallbackHedgeDelaySeconds
        onlineFallback.hedgeKey = onlineFallbackChunkKey(index)
        onlineFallback.hedgeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !Task.isCancelled, self.sessionID == session, self.currentPlaybackId == playbackId,
                  !self.onlineFallback.isDelivered(playbackId) else { return }
            AppLogger.shared.log(
                "[TTSFallback] \(self.onlineFallbackOnlineName) chưa có tiếng sau \(Int(delay)) s ⇒ tổng hợp song song đoạn \(index) bằng giọng dự phòng"
            )
            do {
                let data = try await self.onlineFallbackAudio(index: index, text: text, priority: .demand)
                guard !Task.isCancelled, self.isContextValid(context), self.currentPlaybackId == playbackId,
                      self.onlineFallback.claimDelivery(playbackId) else { return }
                AppLogger.shared.log("[TTSFallback] Đoạn \(index) đọc bằng giọng dự phòng (online chưa xong)")
                self.playAudioData(data, context: context)
                self.updatePrefetchWindow()
            } catch is CancellationError {
                return
            } catch {
                // Để lượt online quyết: được ⇒ phát online; hết lượt thử ⇒ `switchToOnlineFallback` đọc lại bằng giọng dự
                // phòng, vẫn lỗi thì dừng như cũ.
                AppLogger.shared.log("❌ [TTSFallback] Giọng dự phòng (đọc song song) lỗi: \(error.localizedDescription)")
            }
        }
    }

    /// Đầu `playGoogleTTS` / `playExtensionTTS`: sang đoạn khác (bỏ qua đoạn, hết đoạn) ⇒ huỷ lượt song song của đoạn cũ.
    /// Cùng đoạn (đọc lại đoạn này bằng dự phòng sau khi online hỏng) thì giữ — lượt mới dùng chung tiếng đang tổng hợp.
    func cancelOnlineFallbackHedge(unlessIndex index: Int? = nil) {
        if let index, onlineFallback.hedgeKey == onlineFallbackChunkKey(index) { return }
        onlineFallback.cancelHedge()
    }

    /// Lượt online của đoạn đang đọc vừa có tiếng ⇒ `true` nếu được phát (dự phòng chưa phát đoạn này); huỷ lượt song song.
    func claimOnlineDelivery(_ playbackId: String) -> Bool {
        guard onlineFallback.claimDelivery(playbackId) else { return false }
        onlineFallback.cancelHedge()
        return true
    }

    /// `catch` của lượt online đoạn đang đọc. Dự phòng đã phát đoạn này ⇒ online hết lượt thử chỉ còn là tín hiệu server
    /// hỏng: chuyển cả phiên sang dự phòng, **không** đọc lại đoạn; trả `true` (bên gọi thôi).
    func handleOnlineFailureAfterHedge(_ error: Error, playbackId: String, session: UUID) -> Bool {
        guard onlineFallback.isDelivered(playbackId) else { return false }
        guard session == sessionID, isPlaying, let engine = TTSOnlineFallbackSettings.engine,
              !onlineFallback.isActive(session: sessionID) else { return true }
        AppLogger.shared.log(
            "❌ [TTSFallback] \(onlineFallbackOnlineName) hết lượt thử (\(error.localizedDescription)) ⇒ đọc tiếp bằng giọng dự phòng \(engine.title)"
        )
        activateOnlineFallback(engine: engine, offline: !TTSNetworkReachability.shared.isSatisfied)
        updatePrefetchWindow()
        return true
    }
}
