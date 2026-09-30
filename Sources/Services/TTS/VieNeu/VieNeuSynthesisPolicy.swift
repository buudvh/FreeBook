import Foundation

/// Chính sách chất lượng ↔ tốc độ của engine **VieNeu-TTS v3 Nano**.
///
/// Quyết định của chủ dự án cho engine này là **ưu tiên liền mạch**: giữ RTF < 1 bằng mọi giá, thà hạ
/// chất lượng còn hơn để Reader giật và máy nóng. Vì vậy policy có **hai chế độ** và một luật đổi chế
/// độ có trễ (hysteresis) — không đổi qua lại mỗi đoạn.
///
/// Đây là type **thuần**: không giữ trạng thái, không đọc `UserDefaults`. Bộ đếm thích nghi nằm ở
/// `VieNeuTTSEngine` (nơi có khoá bảo vệ ONNX), policy chỉ trả lời "đổi mode nào" và "tham số của mode
/// đó là gì".
enum VieNeuSynthesisPolicy {
    /// Chế độ chất lượng. `rawValue` được ghi vào log để đọc lại được lịch sử đổi mode.
    enum Mode: String, CaseIterable, Sendable {
        /// 16 Euler step, `sway = 0` — mặc định của model.
        case high
        /// 8 Euler step, `sway = -1` — bản tham chiếu ghi rõ cặp này nhanh gấp đôi và **phải đi cùng
        /// nhau**: hạ step mà giữ `sway = 0` làm chất lượng tụt nhiều hơn cần thiết.
        case fast
        // KHÔNG có chế độ tắt CFG (`cfg = 0`). Đã thử và **bỏ**: bỏ CFG halve compute thật, nhưng model
        // card cảnh báo "hurts intelligibility" và người dùng xác nhận nghe **đứt quãng, không rõ tiếng**.
        // Giữ lại một chế độ mà tai người dùng từ chối chỉ tạo thêm lựa chọn tồi.
        //
        // Lưu ý tương thích: `UserDefaults` có thể còn giá trị `"turbo"` từ bản trước;
        // `Mode(rawValue:)` trả `nil` nên nó tự rơi về "tự động" — không cần migrate.
    }

    /// Bộ tham số đưa thẳng vào vòng Euler.
    struct Tuning: Sendable {
        let steps: Int
        let sway: Double
        let cfg: Float
    }

    static func tuning(for mode: Mode) -> Tuning {
        switch mode {
        case .high: return Tuning(steps: 16, sway: 0.0, cfg: 3.0)
        case .fast: return Tuning(steps: 8, sway: -1.0, cfg: 3.0)
        }
    }

    /// Số luồng ORT.
    ///
    /// **Không** dùng 1 như `ONNXPiperEngine` (Piper là model nhỏ, 1 luồng đủ và ưu tiên nhiệt), cũng
    /// không dùng 6 như bản tham chiếu desktop (đó là CPU máy tính). Ban đầu đặt 2; người dùng báo
    /// tổng hợp 10,15 s cho 28,13 s audio (RTF thật 0,37, trước là 0,26–0,30) nên nâng lên 4 — sau khi
    /// đã ở 8 bước + CFG thì **số luồng là đòn bẩy còn lại duy nhất**, đổi lại là máy nóng hơn.
    ///
    /// **Đã đo và giữ 4**: `Output.timing` cho `vector 7,60 s | khác 0,14 s` trên 28,01 s audio, và
    /// `RTF thật` giảm 0,37 → **0,29** so với lúc còn 2 luồng. Vòng Euler chiếm **98%** thời gian nên đây
    /// đúng là nút thắt, và chi phí cố định theo chunk (0,14 s) nhỏ tới mức **giảm số chunk không giúp gì**.
    static let defaultThreadCount: Int32 = 4

    // MARK: - Cài đặt "Tiết kiệm pin" & số luồng (1.3.441)

    /// Khoá `UserDefaults` cho chế độ "Tiết kiệm pin" và số luồng ORT.
    static let powerSavingKey = "vieneuPowerSaving"
    static let threadCountKey = "vieneuThreadCount"

    /// Số luồng ORT đã chọn (2...4), mặc định 4. **Hàm thuần** — nhận `defaults` từ caller (type này
    /// không tự đọc `UserDefaults`). Áp dụng khi **nạp lại engine** (session ORT dựng với số luồng này).
    static func threadCount(from defaults: UserDefaults) -> Int32 {
        Int32(max(2, min(4, defaults.object(forKey: threadCountKey) as? Int ?? Int(defaultThreadCount))))
    }

    /// "Tiết kiệm pin" (opt-in): ép `fast` + 2 luồng. **Hàm thuần** — nhận `defaults` từ caller.
    static func isPowerSaving(_ defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: powerSavingKey)
    }

    // MARK: - Luật đổi chế độ

    /// RTF ≥ ngưỡng này coi là "đuối". Đo bằng `synthSeconds / audioSeconds`, cùng định nghĩa với
    /// `TTSManager.recordNghiSynthesis` (`TTSManager+NghiEnergy.swift:19`).
    static let downshiftRTF: Double = 0.85
    /// RTF ≤ ngưỡng này coi là "thoải mái" ⇒ có thể quay lại `.high`.
    ///
    /// **1.3.441 — ưu tiên `fast`**: hạ 0.45 → 0.30 để khó quay lại `.high` hơn (giảm ~2× tính toán ⇒
    /// mát máy/tốn ít pin hơn, đổi lại chất lượng thấp hơn). Máy rất khoẻ mới lên lại `.high`.
    static let upshiftRTF: Double = 0.30
    /// Số mẫu liên tiếp phải vượt ngưỡng trước khi đổi. Đoạn đầu tiên luôn chậm hơn (session vừa nạp,
    /// cache còn nguội) nên đổi ngay sau một mẫu là tự hạ chất lượng vô cớ.
    static let samplesBeforeSwitch = 3

    /// Quyết định chế độ kế tiếp. `consecutiveSlow` / `consecutiveFast` là số đoạn liên tiếp đã vượt
    /// ngưỡng tương ứng; trả về `nil` nghĩa là **giữ nguyên** chế độ hiện tại.
    static func nextMode(
        current: Mode,
        lastRTF: Double,
        consecutiveSlow: Int,
        consecutiveFast: Int
    ) -> Mode? {
        switch current {
        case .high:
            guard consecutiveSlow >= samplesBeforeSwitch, lastRTF >= downshiftRTF else { return nil }
            return .fast
        case .fast:
            // Đòi hỏi ở chiều ngược lại cao hơn (`upshiftRTF` thấp hơn hẳn `downshiftRTF`) để không rơi
            // vào vòng lật qua lật lại giữa hai chế độ trên một máy ở đúng ranh giới.
            guard consecutiveFast >= samplesBeforeSwitch, lastRTF <= upshiftRTF else { return nil }
            return .high
        }
    }

    // MARK: - Đệm và tải trước

    /// Số giây audio tối thiểu nên có sẵn trước khi phát. Sâu hơn Piper (mặc định 8 s —
    /// `NghiSynthesisPolicy.defaultSafeCachedTimeThreshold`) vì mỗi lần tổng hợp ở đây đắt hơn nhiều.
    static let bufferedSecondsTarget: Double = 12.0

    /// Trần số payload audio giữ đồng thời. Giữ nguyên 5 như Piper: nới trần này không làm engine nhanh
    /// hơn, chỉ làm bộ nhớ phình — bài học đã ghi ở `NghiSynthesisPolicy`.
    static let maxTotalAudioPayloads: Int = 5
}
