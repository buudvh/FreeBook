import Foundation

/// Nạp trước đồng thời (concurrent prefetch) cho đường đọc local (NghiTTS / VieNeu).
///
/// Tách file vì `TTSManager.swift` vượt trần ratchet-down (4028 dòng so với baseline 3470 trong
/// `architecture_allowlist.json`) — mọi code MỚI phải nằm ở extension. Phần khai báo `nghiRefill*`
/// vẫn ở file legacy (extension không thêm được stored property), còn logic nạp trước đồng thời
/// gom về đây.
extension TTSManager {
    /// Số lượt tổng hợp nạp trước được phép chạy **cùng lúc**.
    ///
    /// - NghiTTS (Piper): tổng hợp gần tức thì (tens of ms), 1 luồng đã đủ và ưu tiên nhiệt, giữ
    ///   nguyên behaviour cũ.
    /// - VieNeu: mỗi lần tổng hợp đắt (RTF ~0,3 + chi phí cố định theo chunk; `VieNeuSynthesisPolicy`
    ///   ghi rõ `bufferedSecondsTarget = 10` vì "mỗi lần tổng hợp đắt hơn nhiều"). Nếu chỉ nạp tuần
    ///   tự 1 đoạn, những đoạn ngắn (thời lượng audio ≤ 1 lần tổng hợp) sẽ không kịp tổng hợp trước
    ///   khi đoạn đang phát kết thúc ⇒ phải chờ — đúng lỗi người dùng báo. Cho phép 3 luồng chạy song
    ///   song để đường nạp trước đi trước kịp một đoạn đệm sâu, hấp thụ được cả tổng hợp lạnh
    ///   (cold start) lẫn đoạn cực ngắn.
    ///
    /// **Lưu ý hiệu năng**: `VieNeuTTSEngine` khoá ONNX bằng `NSLock` nên các lượt tổng hợp thực tế
    /// vẫn chạy nối tiếp ở phần ONNX — concurrency ở tầng này chủ yếu xoá khoảng trống điều phối
    /// (không đợi `defer` → `updateNghiPrefetchWindow` → `schedule` tiếp) và chồng được phần tiền
    /// xử lý (normalize / G2P) nằm ngoài khoá. Nếu đoạn thực tế vẫn đứt, tăng lên 4–5 sau khi đo
    /// RTF thực tế trên thiết bị.
    internal var maxConcurrentNghiRefills: Int {
        tool == "vieneu" ? 3 : 1
    }

    /// Lập lịch nạp trước cho đến khi đạt giới hạn luồng hoặc không còn ứng viên.
    ///
    /// Thay vì chỉ nạp 1 đoạn rồi `return`, vòng lặp này nạp liền kề `N+1, N+2, …` (mỗi lượt
    /// `scheduleNghiRefill()` tự bước qua các đoạn đang bay / rỗng) cho tới khi `nghiRefillTasks`
    /// đầy hoặc `nghiRefillCandidate` trả `nil`. Mỗi lượt tổng hợp xong sẽ `defer` gọi lại
    /// `updateNghiPrefetchWindow` nên pipeline tự duy trì mà không cần đệ quy hở.
    internal func fillNghiRefillUpToCapacity() {
        var safety = 0
        while safety < 32 {
            safety &+= 1
            // `scheduleNghiRefill()` tự guard `nghiRefillRetryTask == nil` và giới hạn luồng, nên ở
            // đây chỉ cần kiểm tra số lượt đang bay. Nếu đầy hoặc đang retry, nó trả `false` ⇒ dừng.
            guard nghiRefillTasks.count < maxConcurrentNghiRefills else { break }
            guard scheduleNghiRefill() else { break }
        }
    }

    /// Đệm nóng đầu phát / biên chương: tổng hợp trước các đoạn kế (`N+1..N+3`) NGAY khi bắt đầu phát.
    ///
    /// Gọi từ `continueStartSpeaking` — điểm vào chung của cả **fresh start** (`startSpeaking`) lẫn
    /// **sang chương mới** (`applyNextChapter`). Đoạn đầu của một phiên/chương thường lạnh; nếu chỉ nạp
    /// tuần tự sau khi nó phát xong thì đoạn 1→2→3 sẽ hụt (đúng lỗi người dùng báo "nghe xong đoạn 1
    /// còn đợi mới nghe đoạn 2"). Chạy nạp trước song song với việc tổng hợp+phát đoạn hiện tại để lấp
    /// khoảng trống đó. Hàm tự bỏ qua đoạn đã có/đang bay nên gọi lại là vô hại.
    internal func warmNghiRefillForPlaybackStart() {
        guard TTSManager.isLocalEngine(tool) else { return }
        fillNghiRefillUpToCapacity()
    }
}
