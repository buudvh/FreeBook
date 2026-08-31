import Foundation

/// Lấy mẫu một code từ logits của một codebook.
///
/// Thứ tự **top-k trước, sort sau** là cố ý và là điểm khác biệt lớn nhất so với cách viết trực
/// tiếp: chọn 25 ứng viên bằng một lượt quét rồi chỉ sort/softmax trên 25 phần tử đó, thay vì cấp
/// phát mảng 1024 tuple rồi `sort` toàn bộ mỗi lần gọi. Hàm này chạy 16 lần cho mỗi frame audio
/// (200 lần cho mỗi giây), nên chi phí ở đây nhân lên rất nhanh.
enum VieNeuSampler {
    /// Số ứng viên giữ lại. Khớp `top_k = 25` của engine tham chiếu.
    static let defaultTopK = 25
    static let defaultTopP: Float = 0.95
    static let defaultTemperature: Float = 0.8
    static let defaultRepetitionPenalty: Float = 1.2

    /// - Parameters:
    ///   - logits: bị **sửa tại chỗ** khi có repetition penalty, để không phải copy 1024 float mỗi
    ///     lần gọi. Caller phải coi mảng này là dùng một lần.
    ///   - temperature: `0` ⇒ argmax (tất định, dùng để đối chiếu với bản Python).
    static func sample(
        logits: inout [Float],
        channel: Int,
        temperature: Float,
        topK: Int,
        topP: Float,
        repetitionPenalty: Float,
        history: inout VieNeuRepetitionHistory
    ) -> Int32 {
        applyRepetitionPenalty(&logits, channel: channel, penalty: repetitionPenalty, history: history)

        let code: Int32
        if temperature <= 0 {
            code = Int32(argmax(logits))
        } else {
            code = Int32(sampleTopKTopP(logits, temperature: temperature, topK: topK, topP: topP))
        }
        history.add(code: code, channel: channel)
        return code
    }

    /// Đúng ngữ nghĩa của engine tham chiếu: logit âm thì **nhân** penalty (đẩy xuống thấp hơn),
    /// logit dương thì **chia** (kéo xuống gần 0). Chia đều cho cả hai dấu sẽ làm logit âm *tăng*.
    private static func applyRepetitionPenalty(
        _ logits: inout [Float],
        channel: Int,
        penalty: Float,
        history: VieNeuRepetitionHistory
    ) {
        guard penalty != 1.0, let codes = history.penalisedCodes(channel: channel) else { return }
        let count = logits.count
        for code in codes {
            let index = Int(code)
            guard index >= 0 && index < count else { continue }
            let value = logits[index]
            logits[index] = value < 0 ? value * penalty : value / penalty
        }
    }

    private static func argmax(_ logits: [Float]) -> Int {
        var best = 0
        var bestValue = -Float.greatestFiniteMagnitude
        for index in logits.indices where logits[index] > bestValue {
            bestValue = logits[index]
            best = index
        }
        return best
    }

    /// Một lượt quét chọn `k` logit lớn nhất (chèn vào mảng `k` phần tử đã sắp giảm dần), rồi
    /// softmax + nucleus + rút thăm **chỉ trên `k` ứng viên đó**.
    private static func sampleTopKTopP(_ logits: [Float], temperature: Float, topK: Int, topP: Float) -> Int {
        let vocabSize = logits.count
        guard vocabSize > 0 else { return 0 }
        let k = min(max(1, topK), vocabSize)

        var candidateIndices = [Int](repeating: 0, count: k)
        var candidateValues = [Float](repeating: -Float.greatestFiniteMagnitude, count: k)
        var filled = 0

        for index in 0..<vocabSize {
            let value = logits[index]
            // Đủ k ứng viên và giá trị mới không hơn ứng viên bé nhất ⇒ bỏ ngay, đây là nhánh
            // chạy cho hầu hết 1024 phần tử nên nó quyết định tốc độ.
            if filled == k && value <= candidateValues[k - 1] { continue }

            var position = min(filled, k - 1)
            while position > 0 && candidateValues[position - 1] < value {
                candidateValues[position] = candidateValues[position - 1]
                candidateIndices[position] = candidateIndices[position - 1]
                position -= 1
            }
            candidateValues[position] = value
            candidateIndices[position] = index
            if filled < k { filled += 1 }
        }

        // Softmax trên k ứng viên. `candidateValues[0]` là max nên trừ nó là đủ để chống tràn.
        let maxValue = candidateValues[0] / temperature
        var probabilities = [Float](repeating: 0, count: filled)
        var sum: Float = 0
        for position in 0..<filled {
            let scaled = candidateValues[position] / temperature
            let weight = exp(scaled - maxValue)
            probabilities[position] = weight
            sum += weight
        }
        guard sum > 0 else { return candidateIndices[0] }

        // Nucleus: giữ các ứng viên đầu tiên cho tới khi tổng xác suất **trước** phần tử hiện tại
        // vượt topP — cùng biên với `(cumsum - p) < top_p` của bản tham chiếu, nên phần tử làm
        // tổng vượt ngưỡng vẫn được giữ và tập ứng viên không bao giờ rỗng.
        var kept = filled
        if topP < 1.0 {
            var running: Float = 0
            for position in 0..<filled {
                let probability = probabilities[position] / sum
                if running >= topP {
                    kept = position
                    break
                }
                running += probability
            }
            kept = max(1, kept)
        }

        var keptSum: Float = 0
        for position in 0..<kept { keptSum += probabilities[position] }
        guard keptSum > 0 else { return candidateIndices[0] }

        let dice = Float.random(in: 0..<1) * keptSum
        var accumulated: Float = 0
        for position in 0..<kept {
            accumulated += probabilities[position]
            if dice <= accumulated { return candidateIndices[position] }
        }
        return candidateIndices[kept - 1]
    }
}
