import Foundation

/// `Snapshot.text_count(s)` của bản thử Python = `joined.count(s)`: số lần `s` xuất hiện **không chồng lấn** (quét từ
/// trái, khớp xong nhảy qua cả cụm) trong chuỗi nối các đoạn Hán đã đọc.
///
/// Quét cả 1,8 triệu chữ cho mỗi câu hỏi thì quá chậm, nên đi theo chỉ mục vị trí của chữ đầu
/// (`LocalNameFilterAccumulator.positionsByUnit`, tăng dần) rồi so phần còn lại; giữ `nextAllowed` (cuối lần khớp trước)
/// cho đúng nghĩa không chồng lấn. Kết quả nhớ trong **một** lần chụp (chữ đã đọc còn tăng giữa các lần chụp).
/// Cụm chỉ gồm chữ Hán nên không bao giờ khớp qua dấu `\n` nối đoạn — và vì thế đếm trên chuỗi các đoạn Hán bằng đúng
/// đếm trên cả dòng chữ (`joined` của `lacpipe.py`) cho mọi cụm toàn chữ Hán của dải bộ luật.
final class LocalNameFilterTextCounter {
    private let accumulator: LocalNameFilterAccumulator
    private var memo: [LocalNameFilterTermKey: Int] = [:]
    /// Cụm dài > 5 chữ của phía LAC (日月皇家魂导师学院).
    private var longMemo: [[UInt16]: Int] = [:]

    init(accumulator: LocalNameFilterAccumulator) {
        self.accumulator = accumulator
    }

    func count(_ term: LocalNameFilterTermKey) -> Int {
        if let cached = memo[term] { return cached }
        let found = scan(term.units)
        memo[term] = found
        return found
    }

    /// Cụm toàn chữ Hán của dải bộ luật, dài bất kỳ (phía LAC).
    func count(units: [UInt16]) -> Int {
        guard !units.isEmpty else { return 0 }
        if units.count <= LocalNameFilterTermKey.maxLength { return count(LocalNameFilterTermKey(units: units)) }
        if let cached = longMemo[units] { return cached }
        let found = scan(units)
        longMemo[units] = found
        return found
    }

    private func scan(_ units: [UInt16]) -> Int {
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
        return found
    }

    // MARK: - Ngữ cảnh trái / phải (đợt 4, 2026-11-28)

    /// `neighbors(w)` của `lacpipe.py`: số lần khớp không chồng lấn + chữ Hán đứng **ngay trước** / **ngay sau** mỗi lần
    /// khớp ⇒ số lần. Đầu / cuối đoạn Hán (dấu câu, chữ khác trong chữ truyện) là ranh giới, không tính.
    struct Neighbors {
        let count: Int
        let left: [UInt16: Int]
        let right: [UInt16: Int]
    }

    private var neighborMemo: [[UInt16]: Neighbors] = [:]

    func neighbors(units: [UInt16]) -> Neighbors {
        if let cached = neighborMemo[units] { return cached }
        var found = 0
        var left: [UInt16: Int] = [:]
        var right: [UInt16: Int] = [:]
        let length = units.count
        if length > 0 {
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
                    guard matches else { continue }
                    found += 1
                    nextAllowed = position + length
                    if position > 0, LocalNameFilterRules.isHan(text[position - 1]) {
                        left[text[position - 1], default: 0] += 1
                    }
                    if position + length < text.count, LocalNameFilterRules.isHan(text[position + length]) {
                        right[text[position + length], default: 0] += 1
                    }
                }
            }
        }
        let result = Neighbors(count: found, left: left, right: right)
        neighborMemo[units] = result
        return result
    }
}
