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

    /// Ký tự kết câu dùng làm chỗ cắt ưu tiên.
    private static let chunkBoundaryCharacters = Set("。！？!?.;\n…；：")
    /// Không cắt ở ranh giới câu nếu mẩu đang gom còn ngắn hơn ngưỡng này — nếu không thì một đoạn văn
    /// nhiều dấu phẩy sẽ vỡ thành hàng chục chunk vài chữ, mỗi chunk phải chạy trọn một vòng Euler.
    private static let softChunkMinimum = 40

    /// Tách văn bản thành các mẩu ≤ `limit` ký tự, ưu tiên cắt sau dấu kết câu.
    ///
    /// Đây là phần **thay thế có chủ ý** cho `normalize_to_chunks_v3_with_gaps` của bản tham chiếu: hàm
    /// đó vừa chuẩn hoá văn bản (đọc số, viết tắt) vừa tách chunk, mà quyết định của chủ dự án là
    /// **không** chạy lớp tiền xử lý nào cho engine này (xem plan §2). Phần tách chunk thì vẫn phải có:
    /// Nano chỉ được huấn luyện với clip ≤ 15 giây và bản tham chiếu cắt ở 140 ký tự.
    static func splitIntoChunks(_ text: String, limit: Int) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard limit > 0 else { return [trimmed] }

        var chunks: [String] = []
        var current = ""

        // Cắt theo **từ**, tuyệt đối không theo ký tự.
        //
        // Bản đầu cắt cứng ở đúng `limit` ký tự, nên một từ nằm vắt qua ranh giới bị chẻ đôi: "trở" thành
        // "t" + "rở", "Potter" thành "Po" + "tter". Hai mảnh đó không có trong từ điển nên rơi vào đường
        // **đánh vần từng ký tự** (`charFallback`) và bị đọc thành **tên chữ cái** — đúng cái người dùng
        // nghe thấy: "trở" → "thê giở", "Potter" → "pô ti tờ". Lỗi chỉ hiện ở đúng những từ nằm ngay
        // ranh giới chunk, nên rất khó đoán nếu không đếm vị trí.
        for piece in trimmed.split(separator: " ", omittingEmptySubsequences: true) {
            let word = String(piece)
            if current.isEmpty {
                current = word
            } else if current.count + 1 + word.count <= limit {
                current += " " + word
            } else {
                chunks.append(current)
                current = word
            }

            // Từ đơn dài hơn `limit` thì buộc phải cắt cứng — không còn ranh giới nào tốt hơn.
            while current.count > limit {
                chunks.append(String(current.prefix(limit)))
                current = String(current.dropFirst(limit))
            }

            // Ưu tiên chốt chunk ở ranh giới câu để các chunk sau bám theo câu, không bám theo số ký tự.
            if let last = current.last,
               chunkBoundaryCharacters.contains(last),
               current.count >= softChunkMinimum {
                chunks.append(current)
                current = ""
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks.isEmpty ? [trimmed] : chunks
    }

    /// Khoảng lặng chèn giữa hai chunk **nội bộ** của cùng một đoạn văn.
    ///
    /// Ngắn hơn hẳn các khoảng ngắt ở `NghiTTSSettingsView` (0,1–0,5 s) vì đây là vết nối kỹ thuật, không
    /// phải ngắt câu do người dùng đặt: `trim_and_fade` đã fade hai mép để không click, còn khoảng nghỉ
    /// theo dấu câu là việc của tầng trên.
    static func interChunkSilenceSamples(_ sampleRate: Int) -> Int {
        max(0, Int(0.12 * Double(sampleRate)))
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

    /// Cắt im lặng model tự sinh ở hai đầu (giữ 0,04 s mỗi đầu) rồi fade cosine 0,015 s ở hai mép.
    /// Port nguyên `trim_and_fade` với `EDGE_KEEP_S = 0.04`, `EDGE_FADE_S = 0.015`.
    static func trimAndFade(_ samples: [Float], sampleRate: Int) -> [Float] {
        guard !samples.isEmpty else { return samples }
        let (lead, tail) = edgeSilence(samples, sampleRate: sampleRate)
        let keep = Int(0.04 * Double(sampleRate))
        let start = max(0, lead - keep)
        let end = samples.count - max(0, tail - keep)
        guard start < end else { return samples }

        var output = Array(samples[start..<end])
        let fade = min(Int(0.015 * Double(sampleRate)), output.count / 2)
        guard fade > 1 else { return output }
        // `linspace(0, π, fade)` của numpy ⇒ mẫu số là `fade − 1`, không phải `fade`.
        for index in 0..<fade {
            let ramp = Float(0.5 - 0.5 * cos(Double.pi * Double(index) / Double(fade - 1)))
            output[index] *= ramp
            output[output.count - 1 - index] *= ramp
        }
        return output
    }
}
