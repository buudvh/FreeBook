import Foundation

/// Bản đồ ký tự của chữ chương **đang** lọc rác — để bỏ qua quy tắc chắc chắn không khớp mà không chạy
/// `replaceOccurrences` / `replaceMatches` trên cả chương (1.3.970). Chỉ là điều kiện **cần**: probe nói "có thể khớp" thì
/// quy tắc vẫn chạy như cũ; nói "không thể" thì lượt thay vốn ra 0 chỗ ⇒ bỏ qua cho kết quả y hệt.
///
/// - `units`: mọi đơn vị UTF-16 của chữ gốc **và** của dạng NFD (`decomposedStringWithCanonicalMapping`). Quy tắc chuỗi
///   thường tìm bằng options `[]` (không `.literal`) ⇒ khớp theo tương đương chính tắc — mọi đơn vị trong NFD của mẫu
///   phải có trong NFD của chữ. Regex (ICU, khớp đúng mã) cần ký tự literal bắt buộc có trong chữ gốc.
/// - `pairs`: cặp đơn vị liền nhau trong NFD của chữ, băm vào 2^18 bit (trùng băm chỉ làm chạy thừa, không bỏ sót).
///   Hai ký tự **starter** (ccc = 0) liền nhau trong NFD của mẫu thì cũng liền nhau trong NFD của đoạn khớp: sắp xếp
///   chính tắc chỉ đổi chỗ các dấu (ccc ≠ 0) với nhau, không bao giờ chen vào giữa hai starter.
///
/// Probe phải phản ánh chữ **hiện tại**: một quy tắc thay được ≥ 1 chỗ thì gọi `rebuild` trước quy tắc kế.
struct JunkFilterTextProbe {
    private static let unitWordCount = 1 << 10 // 65 536 bit — mỗi giá trị UTF-16 một bit.
    private static let pairSlotBits = 18
    private static let pairWordCount = (1 << pairSlotBits) >> 6

    private var units = [UInt64](repeating: 0, count: unitWordCount)
    private var pairs = [UInt64](repeating: 0, count: pairWordCount)

    init(text: NSString) {
        rebuild(from: text)
    }

    /// Ô băm của cặp (a, b) — dùng chung cho chữ (ở đây) và mẫu (`JunkFilterCompiledRule`).
    static func pairSlot(_ first: UInt16, _ second: UInt16) -> Int {
        let key = UInt32(first) << 16 | UInt32(second)
        return Int((key &* 0x9E37_79B1) >> UInt32(32 - pairSlotBits))
    }

    mutating func rebuild(from text: NSString) {
        for index in units.indices { units[index] = 0 }
        for index in pairs.indices { pairs[index] = 0 }
        let raw = Self.utf16Units(of: text)
        for unit in raw { insertUnit(unit) }
        let decomposed = Self.utf16Units(of: text.decomposedStringWithCanonicalMapping as NSString)
        var previous: UInt16?
        for unit in decomposed {
            insertUnit(unit)
            if let previous { insertPair(Self.pairSlot(previous, unit)) }
            previous = unit
        }
    }

    /// `false` ⇔ quy tắc chắc chắn không khớp chữ hiện tại.
    func mayMatch(_ rule: JunkFilterCompiledRule) -> Bool {
        for unit in rule.requiredUnits where !containsUnit(unit) { return false }
        for slot in rule.requiredPairSlots where !containsPair(slot) { return false }
        return true
    }

    // MARK: - Bit

    private mutating func insertUnit(_ unit: UInt16) {
        units[Int(unit >> 6)] |= 1 << UInt64(unit & 63)
    }

    private mutating func insertPair(_ slot: Int) {
        pairs[slot >> 6] |= 1 << UInt64(slot & 63)
    }

    private func containsUnit(_ unit: UInt16) -> Bool {
        units[Int(unit >> 6)] & (1 << UInt64(unit & 63)) != 0
    }

    private func containsPair(_ slot: Int) -> Bool {
        pairs[slot >> 6] & (1 << UInt64(slot & 63)) != 0
    }

    private static func utf16Units(of string: NSString) -> [UInt16] {
        let length = string.length
        guard length > 0 else { return [] }
        return [UInt16](unsafeUninitializedCapacity: length) { buffer, count in
            string.getCharacters(buffer.baseAddress!, range: NSRange(location: 0, length: length))
            count = length
        }
    }
}
