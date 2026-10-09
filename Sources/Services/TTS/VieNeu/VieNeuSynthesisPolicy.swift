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
        // KHÔNG có chế độ 4 bước. Đã thử và **bỏ**: giảm còn 4 bước (8 lượt `vector_estimator`/chunk,
        // một nửa `.fast`) làm sai số tích phân vòng Euler quá lớn — người dùng nghe và báo "âm thanh
        // quá kém, không rõ tiếng". Giữ CFG **không bù được** sai số tích phân (CFG là neo để bám
        // điều kiện, không phải độ chính xác của phép lấy tích phân). Sàn thực nghiệm của `steps` là
        // **8**. Đừng thử 5/6/7.
        //
        // KHÔNG có chế độ tắt CFG (`cfg = 0`). Đã thử và **bỏ**: bỏ CFG halve compute thật, nhưng model
        // card cảnh báo "hurts intelligibility" và người dùng xác nhận nghe **đứt quãng, không rõ tiếng**.
        // Giữ lại một chế độ mà tai người dùng từ chối chỉ tạo thêm lựa chọn tồi.
        //
        // Lưu ý tương thích: `UserDefaults` có thể còn giá trị `"turbo"` hoặc `"low"` từ bản trước;
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

    /// Chế độ **thật sự** dùng cho một lượt tổng hợp: **luôn** theo cài đặt TTS.
    ///
    /// ## Vì sao **không** phụ thuộc loại giọng (sửa ở 1.3.461)
    /// Từ 1.3.456 hàm này nhận thêm `isClonedVoice` và **ép `.high` cho mọi lượt tổng hợp bằng giọng nhân
    /// bản**. Đó là **hiểu sai phạm vi** của yêu cầu gốc: "chất lượng cao" là chuyện của **bước clone giọng**
    /// (chọn audio gốc + bấm Lưu) — mà bước đó chạy 3 graph clone (`speaker_encoder`/`codec_encoder`/
    /// `reference_encoder`) chứ **không** chạy vòng Euler, nên **không có `steps`** để đặt.
    /// Hệ quả của việc ép sai chỗ rất thật: bật **"Tiết kiệm pin"** mà bấm **nghe truyện** bằng giọng clone
    /// vẫn chạy 16 bước ⇒ gấp đôi tính toán ⇒ `rtf` ~0,86, `busyPct` ~97 %, **`underrun`** ⇒ audio giật,
    /// máy nóng — trong khi màn Cài đặt hiện "Cân bằng" và **không** có gì tiết lộ sự lệch đó.
    ///
    /// Người dùng chốt 2026-10-01: *"khi tôi bấm nghe truyện (dù tôi chọn giọng clone trong giọng đọc) thì
    /// phải theo cài đặt tts"*. Muốn 16 bước khi đọc thì **tắt "Tiết kiệm pin" + đặt "Chất lượng cao"** —
    /// hai công tắc đã có sẵn.
    ///
    /// Ghi chú kỹ thuật vẫn đúng: vòng Euler là nơi áp **toàn bộ** điều kiện hoá (x-vector + `style`), nên
    /// ở 8 bước âm sắc **bám mẫu kém hơn** 16 bước. Đó là **đánh đổi của cài đặt**, không phải lý do để
    /// ghi đè cài đặt của người dùng.
    static func effectiveMode(requested: Mode?, current: Mode) -> Mode {
        requested ?? current
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
    static let defaultThreadCount: Int32 = 2

    // MARK: - Cài đặt "Tiết kiệm pin" & số luồng (1.3.441)

    /// Khoá `UserDefaults` cho chế độ "Tiết kiệm pin" và số luồng ORT.
    static let powerSavingKey = "vieneuPowerSaving"
    static let threadCountKey = "vieneuThreadCount"
    /// Khoá công tắc spin của pool luồng ORT (1.3.488). Mặc định **tắt** — xem `allowSpinning(from:)`.
    static let allowSpinningKey = "vieneuOrtAllowSpinning"

    /// Khoá `UserDefaults` của chế độ chất lượng. Nằm ở đây — **cùng chỗ** với hai khoá trên — thay vì
    /// giấu trong `VieNeuTTSService`: màn Cài đặt phải đọc được nó ngay cả khi `VieNeuTTSService.shared`
    /// **chưa** được tạo, nếu không `@State` rơi về mặc định và không bao giờ được làm mới (lỗi
    /// 1.3.456: mở màn Cài đặt TTS luôn hiện "Tiết kiệm pin: bật" dù người dùng đã tắt).
    static let preferredModeKey = "vieneuPreferredMode"

    /// Đọc chế độ đã lưu **thẳng từ `UserDefaults`** — không cần `VieNeuTTSService` đã dựng.
    static func preferredMode(from defaults: UserDefaults) -> Mode? {
        guard let raw = defaults.string(forKey: preferredModeKey) else { return nil }
        return Mode(rawValue: raw)
    }

    /// Số luồng ORT đã chọn (1...4; mức 1 thêm ở 1.3.488 để đo CPU-time — NghiTTS vốn chạy 1 luồng).
    /// **Hàm thuần** — nhận `defaults` từ caller (type này không tự đọc `UserDefaults`). Áp dụng khi
    /// **nạp lại engine** (session ORT dựng với số luồng này).
    static func threadCount(from defaults: UserDefaults) -> Int32 {
        Int32(max(1, min(4, defaults.object(forKey: threadCountKey) as? Int ?? Int(defaultThreadCount))))
    }

    /// Cho luồng pool ORT **spin** (chờ bận) hay không. Mặc định **tắt** (1.3.488): spin đốt CPU-time giữa các
    /// op mà gần như không đổi tốc độ. Bật chỉ để so A/B. Áp dụng khi **nạp lại engine**. **Hàm thuần**.
    static func allowSpinning(from defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: allowSpinningKey)
    }

    /// "Tiết kiệm pin": ép `fast` + 2 luồng. **Mặc định BẬT** khi chưa có khoá (user chốt 2026-09-30).
    /// **Hàm thuần** — nhận `defaults` từ caller.
    static func isPowerSaving(_ defaults: UserDefaults) -> Bool {
        defaults.object(forKey: powerSavingKey) == nil ? true : defaults.bool(forKey: powerSavingKey)
    }

    /// Số luồng ORT **hiệu dụng**: "Tiết kiệm pin" ghim 2 luồng, ngược lại dùng giá trị đã chọn.
    static func effectiveThreadCount(from defaults: UserDefaults) -> Int32 {
        isPowerSaving(defaults) ? 2 : threadCount(from: defaults)
    }

    // MARK: - Tốc độ tổng hợp (1.3.465)

    /// Khoá `UserDefaults` của **tốc độ tổng hợp** — tốc độ đưa thẳng vào model, **khác** tốc độ phát
    /// (`ttsRate` / `vieneuRate` vẫn điều khiển `AVAudioPlayer.rate`).
    static let synthesisSpeedKey = "vieneuSynthesisSpeed"

    /// Dải cho phép. Dưới 1,0 không có lý do để dùng (chậm hơn mặc định làm bằng tốc độ phát được rồi);
    /// trên 2,0 model Nano bắt đầu nói không rõ.
    static let synthesisSpeedRange: ClosedRange<Double> = 1.0...2.0

    /// Tốc độ tổng hợp đã lưu. **Hàm thuần** — nhận `defaults` từ caller (type này không tự đọc
    /// `UserDefaults`). Mặc định **1,0** = đúng hành vi trước 1.3.465: tổng hợp ở tốc độ gốc của model
    /// rồi tăng tốc bằng phát.
    ///
    /// ## Vì sao có cài đặt này
    /// Vòng Euler chạy trên `frames = round(secs × fps)` với `secs = exp(log_s) / speed`
    /// (`VieNeuTTSEngine.swift:336-337`) ⇒ **lượng tính toán tỷ lệ thuận với thời lượng audio sinh ra**.
    /// Tổng hợp ở 1,8× rồi phát ở 1,0× cho cùng một tốc độ nghe như tổng hợp 1,0× rồi phát 1,8×, nhưng
    /// tốn **ít hơn ~45 %** tính toán. Đây là cách duy nhất giảm nhiệt mà **không** làm chậm tổng hợp
    /// (hạ số luồng / hạ QoS đều là làm chậm ⇒ sinh đứt đoạn).
    static func synthesisSpeed(from defaults: UserDefaults) -> Double {
        let raw = defaults.double(forKey: synthesisSpeedKey)
        guard raw > 0 else { return 1.0 }
        return max(synthesisSpeedRange.lowerBound, min(synthesisSpeedRange.upperBound, raw))
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
    static let bufferedSecondsTarget: Double = 10.0

    /// Trần số payload audio giữ đồng thời. Giữ nguyên 5 như Piper: nới trần này không làm engine nhanh
    /// hơn, chỉ làm bộ nhớ phình — bài học đã ghi ở `NghiSynthesisPolicy`.
    static let maxTotalAudioPayloads: Int = 5
}
