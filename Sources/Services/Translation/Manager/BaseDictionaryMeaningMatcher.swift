import Foundation

/// So "nghĩa chứa chuỗi tìm, không phân biệt hoa thường" **trên byte UTF-8 của pool** — thay cho
/// `String(bytes:encoding:)` + `range(of:options: .caseInsensitive)` cho từng nghĩa (cỡ triệu nghĩa, phần tốn nhất
/// của lượt tìm cũ). Dùng ở `BaseDictionaryIndexSearch`.
///
/// Giải mã bằng `Unicode.UTF8.ForwardParser` (cùng parser `FrozenTrieDictionary.poolValueIsDecodable`), hạ thường từng
/// scalar theo `lowercaseMapping` (chỉ khi ra đúng một scalar — đủ cho Latin / Latin mở rộng tiếng Việt, Hy Lạp, Kirin;
/// dưới U+2000, ngoài đó giữ nguyên), **không** bỏ dấu (`a` không khớp `á`, như `.caseInsensitive`). Chuỗi tìm chuẩn
/// NFC. Nghĩa có dấu kết hợp rời (NFD, U+0300…) ⇒ trả `.needsFoundation`, nơi gọi so bằng Foundation như cũ; chuỗi tìm
/// có dấu rời ⇒ mọi nghĩa đi đường Foundation. Nghĩa UTF-8 hỏng ⇒ không khớp (bản cũ bỏ qua nghĩa không giải mã được).
struct BaseDictionaryMeaningMatcher: Sendable {
    enum Outcome {
        case match
        case noMatch
        case needsFoundation
    }

    /// Chuỗi tìm nguyên văn (đã cắt khoảng trắng) — đường Foundation dùng đúng chuỗi này như bản cũ.
    let needle: String
    private let foldedNeedle: [UInt32]
    private let needleNeedsFoundation: Bool

    init(needle: String) {
        self.needle = needle
        let scalars = needle.precomposedStringWithCanonicalMapping.unicodeScalars
        foldedNeedle = scalars.map { Self.fold($0.value) }
        needleNeedsFoundation = scalars.contains { Self.isCombiningMark($0.value) }
    }

    /// `bytes` = nội dung UTF-8 của một nghĩa (không gồm 2 byte độ dài). `scratch` là bộ đệm dùng lại của luồng gọi.
    func match(_ bytes: UnsafeRawBufferPointer, scratch: inout [UInt32]) -> Outcome {
        if needleNeedsFoundation { return .needsFoundation }
        guard !foldedNeedle.isEmpty else { return .match }
        scratch.removeAll(keepingCapacity: true)
        var iterator = bytes.makeIterator()
        var parser = Unicode.UTF8.ForwardParser()
        decoding: while true {
            switch parser.parseScalar(from: &iterator) {
            case .valid(let encoded):
                let value = Unicode.UTF8.decode(encoded).value
                if Self.isCombiningMark(value) { return .needsFoundation }
                scratch.append(Self.fold(value))
            case .emptyInput:
                break decoding
            case .error:
                return .noMatch
            }
        }
        return Self.contains(scratch, foldedNeedle) ? .match : .noMatch
    }

    /// Đường cũ: Foundation, phân biệt dấu, không phân biệt hoa thường.
    func foundationMatches(_ value: String) -> Bool {
        value.range(of: needle, options: .caseInsensitive) != nil
    }

    // MARK: - Nội bộ

    private static func contains(_ haystack: [UInt32], _ needle: [UInt32]) -> Bool {
        let last = haystack.count - needle.count
        guard last >= 0 else { return false }
        let first = needle[0]
        var start = 0
        while start <= last {
            if haystack[start] == first {
                var offset = 1
                while offset < needle.count, haystack[start + offset] == needle[offset] { offset += 1 }
                if offset == needle.count { return true }
            }
            start += 1
        }
        return false
    }

    private static let foldLimit: UInt32 = 0x2000

    /// Bảng hạ thường cho scalar < U+2000 (dựng một lần, lười).
    private static let foldTable: [UInt32] = (0..<foldLimit).map { value in
        guard let scalar = Unicode.Scalar(value) else { return value }
        let lowered = scalar.properties.lowercaseMapping.unicodeScalars
        guard lowered.count == 1, let only = lowered.first else { return value }
        return only.value
    }

    private static func fold(_ value: UInt32) -> UInt32 {
        value < foldLimit ? foldTable[Int(value)] : value
    }

    private static func isCombiningMark(_ value: UInt32) -> Bool {
        switch value {
        case 0x0300...0x036F, 0x1AB0...0x1AFF, 0x1DC0...0x1DFF, 0x20D0...0x20FF, 0xFE20...0xFE2F:
            return true
        default:
            return false
        }
    }
}
