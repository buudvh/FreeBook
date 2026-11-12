import Foundation

/// Cắt im lặng hai đầu mẫu giọng — chép `librosa.effects.trim(wav, top_db=30)` mà VieNeu Turbo upstream gọi trong
/// `_preclean_reference_audio` (`src/vieneu/v3turbo.py`). `librosa>=0.11` nằm trong `dependencies` lõi của
/// `pyproject.toml` upstream, nên người dùng upstream chạy **nhánh librosa**, không phải nhánh dự phòng `|x| > 1e-5`.
///
/// Thuật toán librosa 0.11 (mặc định `frame_length` 2048, `hop_length` 512, `ref=np.max`):
/// ```text
/// rms   = feature.rms(y, frame_length, hop_length)        # center=True, đệm 0 (pad_mode="constant") 1024 mỗi đầu
///                                                          # ⇒ 1 + len // 512 khung, khung i phủ mẫu [i·512 − 1024, i·512 + 1024)
/// db_i  = 10·log10(max(1e-10, rms_i²)) − 10·log10(max(1e-10, max_j rms_j²))   # amplitude_to_db(amin=1e-5)
/// giữ   = db_i > −top_db
/// start = đầu khung giữ đầu tiên · 512;  end = min(len, (khung giữ cuối + 1) · 512)
/// không khung nào ⇒ (0, 0)
/// ```
/// Năng lượng khung tính bằng tổng tiền tố `Double` (librosa tính `float32`) — chỉ khác ở khung sát ngưỡng.
enum VieNeuSilenceTrimmer {
    static let topDecibels = 30.0
    static let frameLength = 2048
    static let hopLength = 512
    /// `amin = 1e-5` của `amplitude_to_db` ⇒ sàn công suất 1e-10.
    private static let powerFloor = 1e-10

    /// Đoạn `[start, end)` giữ lại. Rỗng khi cả mẫu im lặng (hoặc mảng rỗng).
    static func nonSilentRange(
        of samples: [Float],
        topDecibels: Double = VieNeuSilenceTrimmer.topDecibels,
        frameLength: Int = VieNeuSilenceTrimmer.frameLength,
        hopLength: Int = VieNeuSilenceTrimmer.hopLength
    ) -> Range<Int> {
        let count = samples.count
        guard count > 0, frameLength > 0, hopLength > 0 else { return 0..<0 }

        // Tổng tiền tố bình phương: năng lượng mọi khung trong O(n); ngoài biên là 0 (đệm hằng 0).
        var prefix = [Double](repeating: 0, count: count + 1)
        for index in 0..<count {
            let value = Double(samples[index])
            prefix[index + 1] = prefix[index] + value * value
        }
        let half = frameLength / 2
        let frameCount = 1 + count / hopLength
        var power = [Double](repeating: 0, count: frameCount)
        var peak = 0.0
        for frame in 0..<frameCount {
            let lower = min(count, max(0, frame * hopLength - half))
            let upper = min(count, max(0, frame * hopLength - half + frameLength))
            let value = max(0, prefix[upper] - prefix[lower]) / Double(frameLength)
            power[frame] = value
            peak = max(peak, value)
        }

        let reference = 10 * log10(max(powerFloor, peak))
        var first: Int?
        var last: Int?
        for frame in 0..<frameCount where 10 * log10(max(powerFloor, power[frame])) - reference > -topDecibels {
            if first == nil { first = frame }
            last = frame
        }
        guard let first, let last else { return 0..<0 }
        let start = min(count, first * hopLength)
        let end = min(count, (last + 1) * hopLength)
        return start..<max(start, end)
    }
}
