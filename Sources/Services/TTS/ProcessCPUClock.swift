import Foundation

/// CPU-time của **cả tiến trình** (cộng dồn mọi luồng, kể cả pool luồng của ONNX Runtime), đơn vị ms.
///
/// Có mặt vì mọi số đo trước 1.3.488 (`rtf`, `busyPct`, `duty`) đều là **thời gian tường**, trong khi năng
/// lượng/nhiệt tỉ lệ với **CPU-time**. Hai thứ tách nhau đúng ở chỗ đáng soi: số luồng ORT và việc luồng
/// pool **spin** (chờ bận) — đổi wall rất ít nhưng đổi CPU-time nhiều (báo cáo
/// `Docs/Reports/2026-10-09-vieneu-huong-toi-uu-moi.md` §1, §3.2). Lấy delta giữa hai lần gọi.
enum ProcessCPUClock {
    static func nowMs() -> Double {
        var ts = timespec()
        guard clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &ts) == 0 else { return 0 }
        return Double(ts.tv_sec) * 1_000 + Double(ts.tv_nsec) / 1_000_000
    }
}
