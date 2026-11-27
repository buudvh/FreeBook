import Foundation

/// Một từ ở **phía LAC** của bộ lọc name local: khoá theo **code point** như `str` của Python (`lacpipe.py`), dài tuỳ ý
/// và chứa được chữ ngoài dải Hán của bộ luật — thực thể LAC có thể dài 9 chữ (日月皇家魂导师学院), có dấu `·`
/// (奥斯汀·格里芬) hay chữ khối mở rộng (玄𫄸). Phía bộ luật vẫn dùng `LocalNameFilterTermKey` (≤ 5 chữ BMP, nhanh hơn).
///
/// So / băm theo từng code point — không qua `String` (canonical equivalence làm chữ tương thích `U+F900–FAFF` bằng chữ
/// thống nhất, Python thì không). Thứ tự `<` là thứ tự từ điển theo code point, cụm ngắn là tiền tố đứng trước — đúng
/// `str <` của Python.
struct LocalNameFilterWord: Hashable, Comparable, Sendable {
    let scalars: [UInt32]

    init(scalars: [UInt32]) {
        self.scalars = scalars
    }

    init<S: Sequence>(_ scalars: S) where S.Element == Unicode.Scalar {
        self.scalars = scalars.map(\.value)
    }

    init(_ string: String) {
        self.init(string.unicodeScalars)
    }

    /// Cụm của bộ luật (chữ Hán BMP) thành từ phía LAC.
    init(_ key: LocalNameFilterTermKey) {
        scalars = key.units.map(UInt32.init)
    }

    var count: Int { scalars.count }
    var isEmpty: Bool { scalars.isEmpty }
    var last: UInt32 { scalars[scalars.count - 1] }

    subscript(position: Int) -> UInt32 { scalars[position] }

    var string: String {
        var result = String.UnicodeScalarView()
        for value in scalars {
            if let scalar = Unicode.Scalar(value) { result.append(scalar) }
        }
        return String(result)
    }

    /// UTF-16 của từ (đếm số lần trong chuỗi UTF-16 đã đọc).
    var utf16Units: [UInt16] {
        Array(string.utf16)
    }

    /// `w[lower:upper]` của Python (chặn trong biên; có thể rỗng).
    func slice(_ lower: Int, _ upper: Int) -> LocalNameFilterWord {
        let from = max(0, min(lower, count))
        let to = max(from, min(upper, count))
        return LocalNameFilterWord(scalars: Array(scalars[from..<to]))
    }

    /// `w[:-length]`.
    func dropLast(_ length: Int) -> LocalNameFilterWord { slice(0, count - length) }

    /// `w[-length:]`.
    func suffix(_ length: Int) -> LocalNameFilterWord { slice(count - length, count) }

    /// `w[:i] + w[i + length:]` — phần còn lại sau khi bỏ một đoạn giữa.
    func removing(from start: Int, length: Int) -> LocalNameFilterWord {
        LocalNameFilterWord(scalars: Array(scalars[..<start]) + Array(scalars[(start + length)...]))
    }

    /// `other in self` của Python (chuỗi con liền).
    func contains(_ other: LocalNameFilterWord) -> Bool {
        let length = other.count
        guard length > 0, length <= count else { return length == 0 }
        for start in 0...(count - length) where scalars[start] == other.scalars[0] {
            var matches = true
            for step in 1..<length where scalars[start + step] != other.scalars[step] {
                matches = false
                break
            }
            if matches { return true }
        }
        return false
    }

    /// Khoá của bộ luật khi mọi chữ thuộc dải Hán của bộ luật (BMP) và dài 1–5 chữ; khác đi ⇒ `nil` (khi đó từ không
    /// có trong Danh sách họ / hậu tố Nhân danh / bảng ứng viên của bộ luật).
    var termKey: LocalNameFilterTermKey? {
        guard (1...LocalNameFilterTermKey.maxLength).contains(count), let units = ruleHanUnits else { return nil }
        return LocalNameFilterTermKey(units: units)
    }

    /// Đơn vị UTF-16 khi mọi chữ thuộc dải Hán của bộ luật (BMP) — đếm được bằng chỉ mục vị trí của bộ luật.
    var ruleHanUnits: [UInt16]? {
        var units: [UInt16] = []
        units.reserveCapacity(count)
        for value in scalars {
            guard value <= 0xFFFF, LocalNameFilterRules.isHan(UInt16(value)) else { return nil }
            units.append(UInt16(value))
        }
        return units
    }

    static func < (lhs: LocalNameFilterWord, rhs: LocalNameFilterWord) -> Bool {
        lhs.scalars.lexicographicallyPrecedes(rhs.scalars)
    }
}
