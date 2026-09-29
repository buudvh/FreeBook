import Foundation

/// Đo hiệu năng và thích nghi chất lượng của `VieNeuTTSEngine`.
///
/// Tách khỏi file chính vì trần **400 dòng vật lý** của repo. Hai hàm ở đây đọc/ghi trạng thái
/// `mode`/`consecutiveSlow`/`consecutiveFast`/`droppedScalarWarningShown` của engine, mà Swift giới hạn
/// `private` theo **file** ⇒ các trường đó phải để `internal`. Cùng lý do và cùng khuôn với
/// `SeaG2P`/`SeaG2P+Phonemize` và với tiền lệ đã ghi ở `Docs/CodeGraph/09_dependency_rules.md:120`.
extension VieNeuTTSEngine {
    /// Cập nhật bộ đếm RTF rồi đổi chế độ nếu đủ mẫu liên tiếp. Ngưỡng nằm ở `VieNeuSynthesisPolicy`.
    ///
    /// Chỉ được gọi từ trong vùng đã giữ `lock` của `synthesize` — hàm này không tự khoá.
    func updateMode(synthesisMs: Double, pcmDuration: Double) {
        guard pcmDuration > 0 else { return }
        let rtf = (synthesisMs / 1_000) / pcmDuration
        if rtf >= VieNeuSynthesisPolicy.downshiftRTF {
            consecutiveSlow += 1
            consecutiveFast = 0
        } else if rtf <= VieNeuSynthesisPolicy.upshiftRTF {
            consecutiveFast += 1
            consecutiveSlow = 0
        } else {
            consecutiveSlow = 0
            consecutiveFast = 0
        }
        if let next = VieNeuSynthesisPolicy.nextMode(
            current: mode,
            lastRTF: rtf,
            consecutiveSlow: consecutiveSlow,
            consecutiveFast: consecutiveFast
        ), next != mode {
            mode = next
            consecutiveSlow = 0
            consecutiveFast = 0
            AppLogger.shared.log("🎙️ [VieNeu] Đổi chế độ sang \(next.rawValue) (RTF=\(String(format: "%.2f", rtf)))")
        }
    }

    /// Phoneme lạ bị **bỏ qua** im lặng ở tầng mã hoá (đúng hành vi bản tham chiếu), nên đây là chỗ duy
    /// nhất nói ra rằng chuyện đó đã xảy ra. Chỉ log một lần cho cả vòng đời engine để không ngập log.
    func noteDroppedScalars(_ dropped: Int, total: Int) {
        guard dropped > 0, !droppedScalarWarningShown else { return }
        droppedScalarWarningShown = true
        AppLogger.shared.log("⚠️ [VieNeu] Bỏ qua \(dropped) phoneme không có trong vocab (tổng \(total) id)")
    }

    /// Thời gian tách theo **hai nhóm việc**, cộng dồn cho cả đoạn.
    ///
    /// Có mặt để trả lời "chậm ở đâu" bằng số đo thay vì phỏng đoán: nếu `vectorMs` chiếm gần hết thì
    /// đòn bẩy là số bước / CFG / số luồng ORT; nếu `otherMs` đáng kể thì đó là **chi phí cố định theo
    /// chunk** (text_encoder + duration_predictor + codec_decoder) và cách giảm là giảm số chunk.
    struct Timing {
        var vectorMs: Double = 0
        var otherMs: Double = 0
    }
}
