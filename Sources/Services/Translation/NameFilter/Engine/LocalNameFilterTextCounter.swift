import Foundation

/// `Snapshot.text_count(s)` của bản thử Python = `joined.count(s)`: số lần `s` xuất hiện **không chồng lấn** (quét từ
/// trái, khớp xong nhảy qua cả cụm) trong chuỗi nối các đoạn Hán đã đọc.
///
/// Quét cả 1,8 triệu chữ cho mỗi câu hỏi thì quá chậm, nên đi theo chỉ mục vị trí của chữ đầu
/// (`LocalNameFilterAccumulator.positionsByUnit`, tăng dần) rồi so phần còn lại; giữ `nextAllowed` (cuối lần khớp trước)
/// cho đúng nghĩa không chồng lấn. Kết quả nhớ trong **một** lần chụp (chữ đã đọc còn tăng giữa các lần chụp).
/// Cụm chỉ gồm chữ Hán nên không bao giờ khớp qua dấu `\n` nối đoạn.
final class LocalNameFilterTextCounter {
    private let accumulator: LocalNameFilterAccumulator
    private var memo: [LocalNameFilterTermKey: Int] = [:]

    init(accumulator: LocalNameFilterAccumulator) {
        self.accumulator = accumulator
    }

    func count(_ term: LocalNameFilterTermKey) -> Int {
        if let cached = memo[term] { return cached }
        let units = term.units
        let length = units.count
        var found = 0
        accumulator.text.withUnsafeBufferPointer { text in
            var nextAllowed = 0
            for position32 in accumulator.positionsByUnit[Int(units[0])] {
                let position = Int(position32)
                guard position >= nextAllowed, position + length <= text.count else { continue }
                var matches = true
                var step = 1
                while step < length {
                    if text[position + step] != units[step] {
                        matches = false
                        break
                    }
                    step += 1
                }
                if matches {
                    found += 1
                    nextAllowed = position + length
                }
            }
        }
        memo[term] = found
        return found
    }
}
