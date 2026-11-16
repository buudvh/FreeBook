import Foundation

/// Lượt **nạp trước** hụt timeout ⇒ bật giọng dự phòng ngay (1.3.953).
///
/// Vì sao: lỗi nạp trước trước đây chỉ được log (`TTSManager.startPrefetchTask`) ⇒ app cứ phát nốt tiếng đã
/// cache tới hết cửa sổ nạp trước (~10–30 s) mới tổng hợp đoạn mới rồi mới chuyển sang giọng dự phòng.
/// Chỉ **lỗi timeout** mới kích hoạt (triệu chứng server chết chung); lỗi nội dung (voice sai, base64 hỏng)
/// thì im như trước, chờ đoạn đang đọc quyết định.
///
/// Khi bật theo đường này: **không** huỷ lượt đang đọc, **không** huỷ các lượt nạp trước khác, **không** xoá
/// tiếng đã nạp — chỉ các đoạn từ đoạn lỗi trở đi mới chuyển sang giọng dự phòng.
extension TTSManager {
    func handleOnlinePrefetchFailure(_ error: Error) {
        guard error is TTSSynthesisTimeoutError else { return }
        guard let engine = TTSOnlineFallbackSettings.engine, TTSOnlineFallbackSettings.isOnlineTool(tool) else { return }
        guard !onlineFallback.isActive(session: sessionID) else { return }
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
