import Foundation

/// Giải mã CRF của LAC (Viterbi) trên điểm phát xạ `[bước, nhãn]`.
///
/// `crfw` `[L + 2, L]`: hàng 0 điểm bắt đầu, hàng 1 điểm kết thúc, hàng `2 + i` điểm chuyển từ nhãn `i` sang từng nhãn.
/// Chép `viterbi` của `Tools/lac-export/export_lac.py`: `Float`, điểm bằng nhau giữ nhãn **nhỏ hơn** (`argmax` numpy lấy
/// vị trí đầu tiên) — so `>` chặt.
enum LACViterbi {
    static func decode(emissions: UnsafePointer<Float>, steps: Int, labels: Int, crf: [Float]) -> [Int] {
        guard steps > 0, labels > 0, crf.count >= (labels + 2) * labels else { return [] }
        var back = [Int32](repeating: 0, count: steps * labels)
        let last: Int = crf.withUnsafeBufferPointer { table in
            let start = table.baseAddress!
            let end = start + labels
            let transitions = start + 2 * labels
            var score = [Float](repeating: 0, count: labels)
            var next = [Float](repeating: 0, count: labels)
            for label in 0..<labels {
                score[label] = start[label] + emissions[label]
            }
            for step in 1..<steps {
                let emission = emissions + step * labels
                for target in 0..<labels {
                    var best = score[0] + transitions[target]
                    var origin = 0
                    for source in 1..<labels {
                        let value = score[source] + transitions[source * labels + target]
                        if value > best {
                            best = value
                            origin = source
                        }
                    }
                    next[target] = best + emission[target]
                    back[step * labels + target] = Int32(origin)
                }
                swap(&score, &next)
            }
            var best = score[0] + end[0]
            var bestLabel = 0
            for label in 1..<labels {
                let value = score[label] + end[label]
                if value > best {
                    best = value
                    bestLabel = label
                }
            }
            return bestLabel
        }
        var path = [Int](repeating: 0, count: steps)
        path[steps - 1] = last
        for step in stride(from: steps - 1, to: 0, by: -1) {
            path[step - 1] = Int(back[step * labels + path[step]])
        }
        return path
    }
}
