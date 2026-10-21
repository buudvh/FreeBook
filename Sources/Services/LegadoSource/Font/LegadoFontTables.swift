import Foundation

/// Bộ đọc bảng font TrueType/OpenType tự viết (spec §14.1 bước 1): thư mục bảng, `head.unitsPerEm`, `cmap` định dạng 4
/// (BMP) và 12 (toàn Unicode). Đường viền glyph lấy bằng CoreText ở `LegadoFont` (chạy được cả `glyf` lẫn CFF).
/// Mọi lần đọc đều kiểm biên — font hỏng ⇒ `nil`.
struct LegadoFontTables {
    let unitsPerEm: Int
    /// Mã ký tự → chỉ số glyph (bỏ glyph 0 `.notdef`).
    let characterMap: [UInt32: UInt16]

    init?(data: Data) {
        let bytes = [UInt8](data)
        guard let base = Self.fontOffset(bytes), let tables = Self.tableDirectory(bytes, at: base),
              let head = tables["head"], let cmap = tables["cmap"] else { return nil }
        guard let units = Self.u16(bytes, head + 18), units >= 16 else { return nil }
        unitsPerEm = Int(units)
        characterMap = Self.parseCmap(bytes, at: cmap)
        if characterMap.isEmpty { return nil }
    }

    // MARK: - Thư mục bảng

    /// Vị trí font đầu tiên (`ttcf` = bộ sưu tập font ⇒ lấy font đầu).
    private static func fontOffset(_ bytes: [UInt8]) -> Int? {
        guard let tag = u32(bytes, 0) else { return nil }
        if tag == 0x7474_6366 { // "ttcf"
            guard let count = u32(bytes, 8), count > 0, let first = u32(bytes, 12) else { return nil }
            return Int(first)
        }
        return 0
    }

    private static func tableDirectory(_ bytes: [UInt8], at base: Int) -> [String: Int]? {
        guard let count = u16(bytes, base + 4), count > 0, count < 512 else { return nil }
        var tables: [String: Int] = [:]
        for index in 0..<Int(count) {
            let record = base + 12 + index * 16
            guard record + 16 <= bytes.count, let offset = u32(bytes, record + 8) else { return nil }
            let tag = String(decoding: bytes[record..<(record + 4)], as: UTF8.self)
            tables[tag] = Int(offset)
        }
        return tables
    }

    // MARK: - cmap

    /// Chọn bảng con tốt nhất: định dạng 12 (Unicode đầy đủ) trước, rồi định dạng 4 (BMP) của nền tảng Unicode/Windows.
    private static func parseCmap(_ bytes: [UInt8], at cmap: Int) -> [UInt32: UInt16] {
        guard let count = u16(bytes, cmap + 2) else { return [:] }
        var format12: Int?
        var format4: Int?
        for index in 0..<Int(count) {
            let record = cmap + 4 + index * 8
            guard let platform = u16(bytes, record), let encoding = u16(bytes, record + 2),
                  let offset = u32(bytes, record + 4) else { break }
            let unicode = platform == 0 || (platform == 3 && (encoding == 1 || encoding == 10))
            guard unicode else { continue }
            let table = cmap + Int(offset)
            switch u16(bytes, table) {
            case 12?: if format12 == nil { format12 = table }
            case 4?: if format4 == nil { format4 = table }
            default: continue
            }
        }
        if let table = format12 { return parseFormat12(bytes, at: table) }
        if let table = format4 { return parseFormat4(bytes, at: table) }
        return [:]
    }

    private static func parseFormat4(_ bytes: [UInt8], at table: Int) -> [UInt32: UInt16] {
        guard let segX2 = u16(bytes, table + 6), segX2 >= 2 else { return [:] }
        let segments = Int(segX2) / 2
        let ends = table + 14
        let starts = ends + segments * 2 + 2
        let deltas = starts + segments * 2
        let rangeOffsets = deltas + segments * 2
        var output: [UInt32: UInt16] = [:]
        for segment in 0..<segments {
            guard let end = u16(bytes, ends + segment * 2), let start = u16(bytes, starts + segment * 2),
                  let delta = u16(bytes, deltas + segment * 2),
                  let rangeOffset = u16(bytes, rangeOffsets + segment * 2), start <= end, start != 0xFFFF else { continue }
            for code in Int(start)...Int(end) {
                var glyph: UInt16 = 0
                if rangeOffset == 0 {
                    glyph = UInt16(truncatingIfNeeded: code + Int(delta))
                } else {
                    let address = rangeOffsets + segment * 2 + Int(rangeOffset) + (code - Int(start)) * 2
                    guard let raw = u16(bytes, address) else { continue }
                    glyph = raw == 0 ? 0 : UInt16(truncatingIfNeeded: Int(raw) + Int(delta))
                }
                if glyph != 0 { output[UInt32(code)] = glyph }
            }
        }
        return output
    }

    private static func parseFormat12(_ bytes: [UInt8], at table: Int) -> [UInt32: UInt16] {
        guard let groups = u32(bytes, table + 12), groups < 200_000 else { return [:] }
        var output: [UInt32: UInt16] = [:]
        for index in 0..<Int(groups) {
            let record = table + 16 + index * 12
            guard let start = u32(bytes, record), let end = u32(bytes, record + 4), let firstGlyph = u32(bytes, record + 8),
                  start <= end, end - start < 0x11_0000 else { continue }
            for code in start...end {
                let glyph = firstGlyph &+ (code - start)
                if glyph != 0, glyph <= UInt32(UInt16.max) { output[code] = UInt16(glyph) }
            }
        }
        return output
    }

    // MARK: - Đọc số big-endian

    static func u16(_ bytes: [UInt8], _ offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= bytes.count else { return nil }
        return UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
    }

    static func u32(_ bytes: [UInt8], _ offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= bytes.count else { return nil }
        return UInt32(bytes[offset]) << 24 | UInt32(bytes[offset + 1]) << 16 | UInt32(bytes[offset + 2]) << 8
            | UInt32(bytes[offset + 3])
    }
}
