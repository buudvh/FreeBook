import Foundation

/// v3 `Snapshot.surname_boundness(s)` của bản thử Python: tỉ lệ số lần chữ họ `s` dính với chữ bên cạnh thành **từ
/// thường** trong VP (经 → 已经, 金 → 金色…). Họ hay dính (≥ `weakSurname`) thì ứng viên tên người cần bằng chứng.
///
/// Đi theo chỉ mục vị trí của chữ đầu (`LocalNameFilterAccumulator.positionsByUnit`), xét **mọi** lần xuất hiện (chồng
/// lấn được, như `text.find(s, i + 1)`). Cửa sổ trái `text[i-1 : i+n]` / phải `text[i : i+n+1]`; cửa sổ chứa `\n` nối
/// đoạn không bao giờ có trong VP (Python tra ra `None`) nên bỏ qua luôn. Nhớ kết quả trong **một** lần chụp.
final class LocalNameFilterSurnameBoundness {
    private let accumulator: LocalNameFilterAccumulator
    private let dictionaries: LocalNameFilterDictionaries
    private var memo: [LocalNameFilterTermKey: Double] = [:]
    private static let newline: UInt16 = 0x0A

    init(accumulator: LocalNameFilterAccumulator, dictionaries: LocalNameFilterDictionaries) {
        self.accumulator = accumulator
        self.dictionaries = dictionaries
    }

    func ratio(_ surname: LocalNameFilterTermKey) -> Double {
        if let cached = memo[surname] { return cached }
        let length = surname.count
        let units = surname.units
        var total = 0
        var bound = 0
        accumulator.text.withUnsafeBufferPointer { text in
            for position32 in accumulator.positionsByUnit[Int(units[0])] {
                let position = Int(position32)
                guard position + length <= text.count else { continue }
                var matches = true
                for step in 1..<length where text[position + step] != units[step] {
                    matches = false
                    break
                }
                guard matches else { continue }
                total += 1
                if position > 0, isCommon(text, start: position - 1, count: length + 1) {
                    bound += 1
                } else if position + length + 1 <= text.count, isCommon(text, start: position, count: length + 1) {
                    bound += 1
                }
            }
        }
        let result = total > 0 ? Double(bound) / Double(total) : 0
        memo[surname] = result
        return result
    }

    /// `d.status(text[start : start + count]) == "common"`; cửa sổ có `\n` ⇒ không.
    private func isCommon(_ text: UnsafeBufferPointer<UInt16>, start: Int, count: Int) -> Bool {
        for offset in 0..<count where text[start + offset] == Self.newline { return false }
        return dictionaries.status(LocalNameFilterTermKey(text, start: start, count: count)) == .common
    }
}
