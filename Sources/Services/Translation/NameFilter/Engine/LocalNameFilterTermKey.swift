import Foundation

/// Khoá của một cụm 1–5 chữ Hán, thay `String` ở vòng nóng của bộ lọc name local.
///
/// - Nhanh: hai từ máy, băm rẻ, không cấp phát.
/// - So **đúng từng code point** như Python: `String` của Swift coi chữ Hán tương thích `U+F900–FAFF` bằng chữ thống nhất
///   tương đương chính tắc, Python thì không.
/// - Thứ tự (`<`) là thứ tự từ điển theo đơn vị UTF-16, cụm ngắn là tiền tố đứng trước — đúng `str <` của Python với chữ
///   trong BMP (chữ Hán không bao giờ là 0 nên ô trống = 0 luôn nhỏ hơn).
///
/// Cụm dài nhất bộ lọc cần: đuôi 2 chữ + 3 chữ đứng trước (luật `glue_sfx` cũng xét tối đa 5 chữ).
struct LocalNameFilterTermKey: Hashable, Comparable, Sendable {
    static let maxLength = 5

    /// Đơn vị 0–3, đơn vị 0 ở 16 bit cao nhất; ô trống = 0.
    let head: UInt64
    /// Đơn vị 4 (0 nếu cụm ≤ 4 chữ).
    let tail: UInt16
    let count: Int

    /// Cụm `units[start ..< start + count]` (`count` 1…5, caller bảo đảm trong biên).
    @inline(__always)
    init(_ units: UnsafeBufferPointer<UInt16>, start: Int, count: Int) {
        var packed: UInt64 = 0
        var position = 0
        while position < count && position < 4 {
            packed |= UInt64(units[start + position]) << UInt64(48 - 16 * position)
            position += 1
        }
        head = packed
        tail = count > 4 ? units[start + 4] : 0
        self.count = count
    }

    init(units: [UInt16]) {
        var packed: UInt64 = 0
        for (position, unit) in units.prefix(4).enumerated() {
            packed |= UInt64(unit) << UInt64(48 - 16 * position)
        }
        head = packed
        tail = units.count > 4 ? units[4] : 0
        count = units.count
    }

    init(unit: UInt16) {
        self.init(units: [unit])
    }

    /// Chuỗi toàn chữ Hán (ba dải của bộ lọc), 1…5 chữ; khác đi ⇒ `nil` (không bao giờ khớp được chữ trong truyện).
    init?(string: String) {
        let units = Array(string.utf16)
        guard (1...Self.maxLength).contains(units.count), units.allSatisfy(LocalNameFilterRules.isHan) else { return nil }
        self.init(units: units)
    }

    @inline(__always)
    subscript(position: Int) -> UInt16 {
        position < 4 ? UInt16(truncatingIfNeeded: head >> UInt64(48 - 16 * position)) : tail
    }

    var first: UInt16 { self[0] }
    var last: UInt16 { self[count - 1] }

    var units: [UInt16] {
        (0..<count).map { self[$0] }
    }

    var string: String {
        String(decoding: units, as: UTF16.self)
    }

    /// `t[lower:upper]` của Python (đã chặn trong biên; rỗng ⇒ `nil`).
    func slice(_ lower: Int, _ upper: Int) -> LocalNameFilterTermKey? {
        let from = max(0, lower)
        let to = min(count, upper)
        guard from < to else { return nil }
        return LocalNameFilterTermKey(units: Array(units[from..<to]))
    }

    /// `t[from:]`.
    func dropFirst(_ length: Int) -> LocalNameFilterTermKey? {
        slice(length, count)
    }

    /// `t[:-length]`.
    func dropLast(_ length: Int) -> LocalNameFilterTermKey? {
        slice(0, count - length)
    }

    /// `t[-length:]`.
    func suffix(_ length: Int) -> LocalNameFilterTermKey? {
        slice(count - length, count)
    }

    static func < (lhs: LocalNameFilterTermKey, rhs: LocalNameFilterTermKey) -> Bool {
        if lhs.head != rhs.head { return lhs.head < rhs.head }
        return lhs.tail < rhs.tail
    }
}
