import Foundation

/// Chừa thread cho TTS khi "Tìm trên tất cả nguồn" đang chạy lúc nghe (1.3.671).
///
/// Script tiện ích JS chạy **đồng bộ** trên cooperative pool (≈ số lõi) và chặn thread suốt lúc `fetch`/`sleep`
/// (`JSExecutionTelemetry`). Tìm hàng chục nguồn cùng lúc làm cạn pool ⇒ TTS từ xa (actor worker/coordinator,
/// `URLSession` async của Google) không còn thread để tổng hợp đoạn kế ⇒ giọng đọc đơ khi hết đoạn nạp trước.
///
/// - TTS không phát: không giới hạn — hành vi cũ, mọi nguồn JS chạy ngay.
/// - TTS đang phát (mọi engine): tối đa `số lõi − 1 − (lời gọi JS khác đang chạy)` nguồn JS cùng lúc, **tối thiểu 1**.
///   "Khác" là tải truyện, nạp chương, Ext TTS… — ước lượng bằng `inFlight − số nguồn tìm đang chạy`. Khi các việc
///   đó đã chiếm gần hết pool thì tìm chỉ còn 1 nguồn một lúc và TTS vẫn có thể chậm: giới hạn này không chạm chúng.
///
/// Nguồn Legado không tính: engine chạy trên `Thread` riêng (`LegadoEngineSession.run`), không chiếm pool.
enum SearchTTSThreadReservePolicy {
    /// Số nguồn JS được chạy cùng lúc. `Int.max` khi TTS không phát.
    static func jsSearchLimit(
        ttsPlaying: Bool,
        runningSearches: Int,
        jsInFlight: Int = JSExecutionTelemetry.inFlightCount,
        cores: Int = ProcessInfo.processInfo.activeProcessorCount
    ) -> Int {
        guard ttsPlaying else { return Int.max }
        let others = max(0, jsInFlight - runningSearches)
        return max(1, cores - 1 - others)
    }

    /// TTS có đang phát không — đọc `TTSManager` trên main (main không thuộc pool nên không bị cạn theo).
    static func isTTSPlaying() async -> Bool {
        await MainActor.run { TTSManager.shared.isPlaying }
    }
}
