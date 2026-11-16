import Foundation

/// Lượt **nạp trước** lỗi ⇒ bật giọng dự phòng ngay, không chờ tới lúc đoạn đang đọc cần tiếng.
///
/// Vì sao: lỗi nạp trước trước đây chỉ được log (`TTSManager.startPrefetchTask`) ⇒ app cứ phát nốt tiếng đã
/// cache tới hết cửa sổ nạp trước (~10–30 s) mới tổng hợp đoạn mới rồi mới chuyển sang giọng dự phòng.
///
/// Hai loại lỗi kích hoạt — cả hai đều bỏ các lượt nạp trước online đang chờ rồi nạp trước lại cả cửa sổ bằng giọng dự
/// phòng **ngay**, trong lúc tiếng online đã nạp còn phát (tiếng đã nạp giữ nguyên, lượt đang đọc không bị huỷ):
/// - **Hết giờ sau khi đã thử lại** (1.3.953; từ 1.3.960 lượt nạp trước có 1 lần thử lại khi có giọng dự phòng, timeout
///   theo cài đặt) — hai lượt liền hụt là triệu chứng server chết chung. 1.3.953 bật ngay lần hụt 3 s đầu tiên và để các
///   lượt khác chạy nốt; log thật cho thấy lượt > 3 s phần lớn vẫn thành công nên chuyển phiên khi đó là quá sớm, còn
///   đoạn vừa hụt thì không ai nạp lại tới lúc nó thành đoạn đang đọc (im thêm một lượt tổng hợp).
/// - **Mất mạng** (1.3.957) — lượt nạp trước lỗi lúc `TTSNetworkReachability` báo máy không có mạng. Log build 1285: mạng
///   mất 11 s trước khi tiếng online phát hết, vậy mà đoạn dự phòng đầu tiên vẫn trễ 1,9 s vì tới lúc đó mới tổng hợp.
///
/// Lỗi nội dung (voice sai, base64 hỏng) lúc máy vẫn có mạng thì im như trước, chờ đoạn đang đọc quyết định.
extension TTSManager {
    func handleOnlinePrefetchFailure(_ error: Error) {
        let isTimeout = error is TTSSynthesisTimeoutError
        let isOffline = !isTimeout && !TTSNetworkReachability.shared.isSatisfied
        guard isTimeout || isOffline else { return }
        guard let engine = TTSOnlineFallbackSettings.engine, TTSOnlineFallbackSettings.isOnlineTool(tool) else { return }
        // Chỉ khi đang đọc: tạm dừng thì chưa cần tiếng, lúc đọc lại đoạn đang đọc tự quyết (`playWithOnlineFallbackIfNeeded`).
        guard isPlaying, !onlineFallback.isActive(session: sessionID) else { return }
        if isOffline {
            AppLogger.shared.log(
                "[TTSFallback] Mất mạng, lượt nạp trước lỗi (\(error.localizedDescription)) ⇒ nạp trước bằng giọng dự phòng \(engine.title)"
            )
            activateOnlineFallback(engine: engine, offline: true)
        } else {
            AppLogger.shared.log(
                "❌ [TTSFallback] Lượt nạp trước hết lượt thử (\(error.localizedDescription)) ⇒ đọc tiếp bằng giọng dự phòng \(engine.title)"
            )
            activateOnlineFallback(
                engine: engine,
                offline: false,
                message: "\(onlineFallbackOnlineName) không phản hồi — đọc tiếp bằng giọng dự phòng \(Self.onlineFallbackVoiceTitle(for: engine))"
            )
        }
        // `activateOnlineFallback` vừa bỏ các lượt nạp trước online (kể cả lượt vừa hụt) ⇒ dựng lại cửa sổ: đoạn còn thiếu
        // đi nhánh dự phòng của `startPrefetchTask`.
        updatePrefetchWindow()
    }
}
