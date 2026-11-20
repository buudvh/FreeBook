import Foundation

/// Làm nhỏ dần **đuôi bị cụt** của tiếng vtts (1.3.1036, anh Bửu: "chỗ ngắt đoạn … hay có tiếng xoẹt xoẹt").
///
/// vtts tự cắt câu > 40 âm tiết ở dấu phẩy (`MAX_SYL` của `vtts_text.c`) rồi nối các mảnh bằng 150 ms **im lặng tuyệt
/// đối** (`VTTS_CHUNK_GAP_MS`, bridge `memset` số 0). Mảnh kết thúc ở dấu phẩy hay bị model cắt khi âm còn đang kêu — đo WAV
/// CI câu "…phiên bản, đem mệnh danh…": 5 ms cuối mảnh 1 còn −36 dBFS rồi rơi thẳng về 0 (cả hai giọng ở 1×) ⇒ tiếng click,
/// trình phát kéo nhanh thì thành tiếng "vụt".
///
/// Cách sửa: trước mỗi khe im lặng tuyệt đối ≥ 100 ms và ở cuối tiếng, nhân 20 ms cuối với nửa chu kỳ cosin (về 0); sau
/// khe to dần 5 ms. Chỉ dò khe **số 0 tuyệt đối** — khoảng lặng tự nhiên của model luôn còn nhiễu nền nên không bị đụng.
/// Chạy trên mẫu thô của `VttsRuntime` (trước `VttsLoudness`, trước khi nối khoảng lặng đuôi).
enum VttsEdgeFade {
    static let fadeOutSeconds = 0.02
    static let fadeInSeconds = 0.005
    static let minimumGapSeconds = 0.1
    /// Mẫu cuối trước khe lớn hơn mức này (−60 dBFS) ⇒ tính là một chỗ cụt (chỉ để ghi log `cut=`).
    static let abruptFloorDb = -60.0

    /// Sửa `samples` tại chỗ; trả số chỗ cụt đã làm nhỏ dần.
    @discardableResult
    static func apply(_ samples: inout [Float], sampleRate: Int) -> Int {
        let count = samples.count
        guard count > 0, sampleRate > 0 else { return 0 }
        let fadeOutLength = max(1, Int(Double(sampleRate) * fadeOutSeconds))
        let fadeInLength = max(1, Int(Double(sampleRate) * fadeInSeconds))
        let minimumGap = max(1, Int(Double(sampleRate) * minimumGapSeconds))
        let abruptFloor = Float(pow(10, abruptFloorDb / 20))
        var abrupt = 0

        var index = 0
        while index < count {
            guard samples[index] == 0 else {
                index += 1
                continue
            }
            var end = index
            while end < count, samples[end] == 0 { end += 1 }
            if end - index >= minimumGap, index > 0 {
                if abs(samples[index - 1]) > abruptFloor { abrupt += 1 }
                fadeOut(&samples, endingAt: index, length: fadeOutLength)
                if end < count { fadeIn(&samples, startingAt: end, length: fadeInLength) }
            }
            index = end
        }

        var last = count
        while last > 0, samples[last - 1] == 0 { last -= 1 }
        if last > 0 {
            if abs(samples[last - 1]) > abruptFloor { abrupt += 1 }
            fadeOut(&samples, endingAt: last, length: fadeOutLength)
        }
        return abrupt
    }

    /// Mẫu `[end − length, end)` nhân `½(1 + cos πt)`, t đi từ 1/length tới 1 ⇒ mẫu cuối về đúng 0.
    private static func fadeOut(_ samples: inout [Float], endingAt end: Int, length: Int) {
        let start = max(0, end - length)
        let span = end - start
        guard span > 0 else { return }
        for position in start..<end {
            let progress = Double(position - start + 1) / Double(span)
            samples[position] *= Float(0.5 * (1 + cos(Double.pi * progress)))
        }
    }

    /// Mẫu `[start, start + length)` nhân `½(1 − cos πt)`, t đi từ 0 ⇒ mẫu đầu bằng 0.
    private static func fadeIn(_ samples: inout [Float], startingAt start: Int, length: Int) {
        let end = min(samples.count, start + length)
        let span = end - start
        guard span > 0 else { return }
        for position in start..<end {
            let progress = Double(position - start) / Double(span)
            samples[position] *= Float(0.5 * (1 - cos(Double.pi * progress)))
        }
    }
}
