import Foundation

/// Lượt **nạp trước** lỗi ⇒ bật giọng dự phòng ngay, không chờ tới lúc đoạn đang đọc cần tiếng.
///
/// Vì sao: lỗi nạp trước trước đây chỉ được log (`TTSManager.startPrefetchTask`) ⇒ app cứ phát nốt tiếng đã
/// cache tới hết cửa sổ nạp trước (~10–30 s) mới tổng hợp đoạn mới rồi mới chuyển sang giọng dự phòng.
///
/// Hai loại lỗi kích hoạt:
/// - **Hết giờ** (1.3.953) — triệu chứng server chết chung. **Không** huỷ lượt đang đọc, **không** huỷ các lượt nạp
///   trước khác, **không** xoá tiếng đã nạp: lượt nào còn chạy thì tự xong; chỉ các đoạn từ đoạn lỗi trở đi mới
///   chuyển sang giọng dự phòng.
/// - **Mất mạng** (1.3.957) — lượt nạp trước lỗi lúc `TTSNetworkReachability` báo máy không có mạng. Các lượt nạp
///   trước online đang chờ chắc chắn cũng lỗi nên bỏ luôn, rồi nạp trước lại cả cửa sổ bằng giọng dự phòng **ngay**
///   trong lúc tiếng online đã nạp còn phát. Log build 1285: mạng mất 11 s trước khi tiếng online phát hết, vậy mà
///   đoạn dự phòng đầu tiên vẫn trễ 1,9 s vì tới lúc đó mới bắt đầu tổng hợp. Tiếng online đã nạp giữ nguyên.
///
/// Lỗi nội dung (voice sai, base64 hỏng) lúc máy vẫn có mạng thì im như trước, chờ đoạn đang đọc quyết định.
extension TTSManager {
    func handleOnlinePrefetchFailure(_ error: Error) {
        let isTimeout = error is TTSSynthesisTimeoutError
        let isOffline = !isTimeout && !TTSNetworkReachability.shared.isSatisfied
        guard isTimeout || isOffline else { return }
        guard let engine = TTSOnlineFallbackSettings.engine, TTSOnlineFallbackSettings.isOnlineTool(tool) else { return }
        guard !onlineFallback.isActive(session: sessionID) else { return }
        if isOffline {
            // Chỉ khi đang đọc: tạm dừng thì chưa cần tiếng, lúc đọc lại đoạn đang đọc tự quyết (`playWithOnlineFallbackIfNeeded`).
            guard isPlaying else { return }
            AppLogger.shared.log(
                "[TTSFallback] Mất mạng, lượt nạp trước lỗi (\(error.localizedDescription)) ⇒ nạp trước bằng giọng dự phòng \(engine.title)"
            )
            activateOnlineFallback(engine: engine, offline: true)
            // `activateOnlineFallback` vừa bỏ các lượt nạp trước online ⇒ dựng lại cửa sổ: đoạn còn thiếu đi nhánh dự phòng.
            updatePrefetchWindow()
            return
        }
        AppLogger.shared.log(
            "❌ [TTSFallback] Lượt nạp trước hụt (\(error.localizedDescription)) ⇒ đọc tiếp bằng giọng dự phòng \(engine.title)"
        )
        activateOnlineFallback(
            engine: engine,
            offline: false,
            cancelPendingPrefetch: false,
            message: "\(onlineFallbackOnlineName) không phản hồi — đọc tiếp bằng giọng dự phòng \(Self.onlineFallbackVoiceTitle(for: engine))"
        )
    }
}
