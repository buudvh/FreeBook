import Foundation

/// Phần DSP và tách văn bản của `VieNeuTTSEngine`.
///
/// Tách khỏi file chính vì trần **400 dòng vật lý** của repo, và vì đây là nhóm hàm **thuần** — không
/// chạm `ORTSession`, không chạm trạng thái thích nghi, nên đứng riêng thì đọc và kiểm được độc lập.
extension VieNeuTTSEngine {
    /// Lưới thời gian đã warp, port nguyên `u = linspace(0,1,n+1)` rồi
    /// `tg = u + sway × (cos(π/2·u) − 1 + u)`.
    ///
    /// `sway = 0` cho lưới đều. `sway = −1` dồn mẫu về hai đầu — bản tham chiếu khuyến nghị đúng cặp
    /// "8 steps + sway = −1", nên hai tham số này **không** được tách rời nhau.
    static func timeGrid(steps: Int, sway: Double) -> [Double] {
        guard steps > 0 else { return [0.0, 1.0] }
        return (0...steps).map { index in
            let u = Double(index) / Double(steps)
            return u + sway * (cos(Double.pi / 2 * u) - 1 + u)
        }
    }

    /// Nhiễu khởi tạo `x` — **chuẩn tắc**, không phải đều.
    ///
    /// Flow matching huấn luyện với prior Gaussian; đổi sang nhiễu đều vẫn chạy, vẫn ra tiếng, nhưng
    /// chất lượng tụt mà không có lỗi nào báo. Box–Muller sinh từng cặp để không phí một lần `log`.
    static func fillStandardNormal(_ values: inout [Float]) {
        var index = 0
        while index < values.count {
            let uniform = Double.random(in: Double.leastNormalMagnitude...1.0)
            let angle = 2 * Double.pi * Double.random(in: 0...1)
            let radius = (-2 * log(uniform)).squareRoot()
            values[index] = Float(radius * cos(angle))
            index += 1
            if index < values.count {
                values[index] = Float(radius * sin(angle))
                index += 1
            }
        }
    }

    /// Ghép các chunk thành một mảng mẫu, **có khớp âm lượng giữa các chunk** và chèn khoảng nghỉ theo
    /// loại ranh giới.
    ///
    /// ## Vì sao khớp âm lượng — đây là **mở rộng**, không phải port
    /// Bản tham chiếu (`join_audio_chunks`) **không** chuẩn hoá gì: nó giữ nguyên audio từng chunk rồi chỉ
    /// chèn zeros cho đủ khoảng nghỉ, và `grep` trong `core_utils.py` không có hàm `normalize`/`peak`/`rms`
    /// nào. Nghĩa là mức to nhỏ chênh giữa các chunk là hành vi **cố hữu** của bản tham chiếu.
    ///
    /// Nhưng người dùng nghe thành lỗi: *"chỗ đến năm giảm âm lượng đột ngột"* — đúng ngay ranh giới chunk
    /// trong một câu dài toàn số. Vì model sinh mỗi chunk độc lập, chunk toàn số đọc đều đều nên **nhỏ hơn**
    /// chunk kể chuyện, và tai người nghe ra một cú tụt âm lượng.
    ///
    /// Cách xử lý cố ý **dè dặt**: lấy **trung vị** RMS của các chunk làm mốc rồi kéo mỗi chunk về mốc đó,
    /// nhưng kẹp hệ số trong **[0,6 … 1,6]** (±4 dB). Kẹp là để không "sửa" những khác biệt **có ý nghĩa**
    /// (câu thì thầm, câu nhấn mạnh) — chỉ san bằng chênh lệch do model sinh rời rạc.
    static func joinChunks(
        _ waveforms: [[Float]],
        gaps: [Chunk.Gap],
        sampleRate: Int
    ) -> (samples: [Float], pauseSeconds: Double) {
        guard !waveforms.isEmpty else { return ([], 0) }

        let gains = loudnessGains(for: waveforms)
        var samples: [Float] = []
        // Cố ý KHÔNG đặt tên `pauseSeconds`: trùng tên sẽ **che** hàm `pauseSeconds(for:)` cùng type và
        // lỗi biên dịch là "cannot call value of non-function type 'Double'".
        var totalPauseSeconds = 0.0

        for (index, waveform) in waveforms.enumerated() {
            if index > 0 {
                // Khoảng nghỉ theo **loại ranh giới** của khe, không phải một hằng số cho mọi khe.
                let pause = Self.pauseSeconds(for: gaps[index - 1])
                totalPauseSeconds += pause
                samples.append(contentsOf: [Float](repeating: 0, count: Int(pause * Double(sampleRate))))
            }
            let gain = gains[index]
            if gain == 1 {
                samples.append(contentsOf: waveform)
            } else {
                samples.append(contentsOf: waveform.map { $0 * gain })
            }
        }
        return (samples, totalPauseSeconds)
    }

    /// Hệ số kéo mỗi chunk về **trung vị** RMS, kẹp trong [0,6 … 1,6] (±4 dB).
    private static func loudnessGains(for waveforms: [[Float]]) -> [Float] {
        let levels = waveforms.map { rootMeanSquare($0) }.filter { $0 > 1e-5 }
        guard levels.count >= 2 else { return [Float](repeating: 1, count: waveforms.count) }

        let sorted = levels.sorted()
        let median = sorted[sorted.count / 2]
        return waveforms.map { waveform in
            let level = rootMeanSquare(waveform)
            guard level > 1e-5 else { return 1 }
            return Float(min(1.6, max(0.6, Double(median / level))))
        }
    }

    private static func rootMeanSquare(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Double = 0
        for value in samples { sum += Double(value) * Double(value) }
        return Float((sum / Double(samples.count)).squareRoot())
    }

    /// `(lead, tail)` — số mẫu im lặng ở đầu và cuối, đo bằng envelope `mean|x|` trên cửa sổ 10 ms.
    /// Port nguyên `edge_silence` với `EDGE_THRESH_DB = −45`.
    static func edgeSilence(_ samples: [Float], sampleRate: Int) -> (lead: Int, tail: Int) {
        let window = max(1, Int(0.01 * Double(sampleRate)))
        let windowCount = samples.count / window
        guard windowCount > 0 else { return (samples.count, 0) }

        let threshold = Float(pow(10.0, -45.0 / 20.0))
        var firstAbove = -1
        var lastAbove = -1
        for windowIndex in 0..<windowCount {
            let base = windowIndex * window
            var total: Float = 0
            for offset in 0..<window { total += abs(samples[base + offset]) }
            guard total / Float(window) > threshold else { continue }
            if firstAbove < 0 { firstAbove = windowIndex }
            lastAbove = windowIndex
        }
        guard firstAbove >= 0 else { return (samples.count, 0) }
        return (firstAbove * window, samples.count - (lastAbove + 1) * window)
    }

    /// Ký hiệu dẫn thêm vào **đầu chuỗi phiên âm** của mỗi chunk (1.3.949): phẩy + cách.
    ///
    /// Vì sao: Nano hay bắt đầu tiếng ngay mẫu 0, không chừa khoảng lặng nào ⇒ phụ âm tắc đầu đoạn ("c", "t") không có
    /// chỗ cho khoảng ngậm trước tiếng bật, nghe như **mất chữ đầu** ("Ca du tô" thành "a du tô"). Đo trên PC ở tốc độ
    /// tổng hợp 1,15× (8 câu × 2 seed): không dẫn 4/16 lượt có ≥ 20 ms lặng đầu; dấu cách 7/16; **phẩy + cách 13/16**
    /// (1,0×: 16/16). Lặng thừa bị `trimAndFade` cắt còn 40 ms.
    ///
    /// **Không được tốn thêm phép tính** (anh Bửu: Nano là trình đọc chính vì ít tốn pin). Ký hiệu dẫn làm
    /// `duration_predictor` cộng ~1,8 khung mỗi chunk (đo 115 đoạn truyện thật: +3,3% khung); `runChunk` trả lại
    /// `leadInFrameCredit` khung nên tổng khung không tăng (đo 12 câu × 2 seed: 810 so với 818 khi không dẫn), mà khoảng
    /// dẫn vẫn có ở 23/24 lượt. Đánh đổi: lời đọc trong chunk nhanh hơn ~3% (khoảng dẫn lấy chỗ trong cùng số khung).
    static let leadInPhonemes = ", "
    /// Số khung trả lại khi chunk có ký hiệu dẫn; chunk ngắn hơn 32 khung chỉ trả 1, dưới 16 khung không trả.
    static let leadInFrameCredit = 2

    /// Chuỗi phiên âm đưa vào `encode`: thêm `leadInPhonemes` khi chunk có lời đọc và chưa mở đầu bằng dấu câu / dấu cách.
    static func withLeadIn(_ phonemes: String) -> String {
        guard let first = phonemes.unicodeScalars.first else { return phonemes }
        if first == " " || CharacterSet.punctuationCharacters.contains(first) { return phonemes }
        return leadInPhonemes + phonemes
    }

    /// Cắt im lặng model tự sinh ở hai đầu (giữ 0,04 s mỗi đầu) rồi fade cosine 0,015 s ở hai mép.
    /// Port `trim_and_fade` với `EDGE_KEEP_S = 0.04`, `EDGE_FADE_S = 0.015`.
    ///
    /// **Lệch có chủ ý so với bản tham chiếu (1.3.949):** đoạn mà model **không** chừa lặng đầu thì 15 ms đầu chính là
    /// phụ âm đầu — fade 15 ms sẽ ăn mất nó. Khi đó chỉ fade 2 ms (đủ để không "tách" tiếng). `hadLeadIn` cho bên gọi đếm
    /// số chunk như vậy vào log.
    static func trimAndFade(_ samples: [Float], sampleRate: Int) -> (samples: [Float], hadLeadIn: Bool) {
        guard !samples.isEmpty else { return (samples, true) }
        let (lead, tail) = edgeSilence(samples, sampleRate: sampleRate)
        let keep = Int(0.04 * Double(sampleRate))
        let start = max(0, lead - keep)
        let end = samples.count - max(0, tail - keep)
        guard start < end else { return (samples, lead > 0) }

        var output = Array(samples[start..<end])
        let fade = min(Int(0.015 * Double(sampleRate)), output.count / 2)
        guard fade > 1 else { return (output, lead > 0) }
        let headFade = lead >= fade ? fade : min(fade, max(2, Int(0.002 * Double(sampleRate))))
        // `linspace(0, π, fade)` của numpy ⇒ mẫu số là `fade − 1`, không phải `fade`.
        for index in 0..<headFade {
            output[index] *= Float(0.5 - 0.5 * cos(Double.pi * Double(index) / Double(headFade - 1)))
        }
        for index in 0..<fade {
            output[output.count - 1 - index] *= Float(0.5 - 0.5 * cos(Double.pi * Double(index) / Double(fade - 1)))
        }
        return (output, lead > 0)
    }

}
