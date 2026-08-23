import Foundation

/// Đọc file MOBI / AZW / AZW3 (PalmDB) ra thân HTML + metadata.
///
/// **Thử nghiệm, chỉ file không DRM.** Không cài SKEL/FDST của KF8 và không đọc index nhị phân
/// (INDX/NCX) — ranh giới chương để `HtmlBookParser` suy ra từ chính HTML.
///
/// Mọi số trong PalmDB/MOBI là **big-endian**, và mọi offset đều kiểm biên trước khi đọc: file hỏng
/// phải ra lỗi hoặc text ngắn hơn, không bao giờ đọc rác hay crash.
///
/// Offset dưới đây tính từ **đầu record 0** (tức đã gồm 16 byte PalmDOC header), theo đúng cách
/// KindleUnpack đọc: magic `"MOBI"` ở `0x10`, `headerLength` ở `0x14`, `extraDataFlags` ở `0xF2`.
enum MobiArchiveReader {
    struct Package: Sendable {
        /// Thân sách đã giải nén, **chưa** decode thành `String` (bảng mã do caller quyết).
        let textData: Data
        /// Tên bảng mã suy từ `codepage` của MOBI header (`"65001"` / `"1252"`), `nil` nếu không rõ.
        let charsetName: String?
        let title: String?
        let author: String?
        let desc: String?
        let coverData: Data?
    }

    private typealias Failure = BookImportService.ImportError

    static func read(data: Data) throws -> Package {
        let records = try recordRanges(in: data)
        let record0 = slice(data, records[0])

        guard let compression = uint16(record0, 0x00),
              let textRecordCount = uint16(record0, 0x08),
              let encryption = uint16(record0, 0x0C)
        else { throw Failure.malformed("PalmDOC header quá ngắn") }

        // Chặn cứng file có DRM, không thử phá.
        guard encryption == 0 else { throw Failure.drmProtected }
        guard compression != 17480 else { throw Failure.unsupportedCompression }
        guard compression == 1 || compression == 2 else {
            throw Failure.malformed("kiểu nén \(compression) chưa hỗ trợ")
        }

        var codepage: UInt32 = 0
        var extraFlags: UInt16 = 0
        var firstImageIndex = 0
        var exth: [UInt32: Data] = [:]
        var fullName: String?

        if ascii(record0, 0x10, 4) == "MOBI", let headerLength = uint32(record0, 0x14) {
            codepage = uint32(record0, 0x1C) ?? 0
            let version = uint32(record0, 0x24) ?? 0
            // `extraDataFlags` chỉ tồn tại ở MOBI header đủ dài và version ≥ 5.
            if headerLength >= 0xE4, version >= 5 {
                extraFlags = uint16(record0, 0xF2) ?? 0
            }
            if let raw = uint32(record0, 0x6C), raw != 0xFFFF_FFFF {
                firstImageIndex = Int(raw)
            }
            if (uint32(record0, 0x80) ?? 0) & 0x40 != 0 {
                exth = exthRecords(record0: record0, offset: 16 + Int(headerLength))
            }
            fullName = fullNameText(record0: record0, codepage: codepage)
        }

        let text = textData(
            data: data,
            records: records,
            count: Int(textRecordCount),
            compression: compression,
            extraFlags: extraFlags
        )
        guard !text.isEmpty else { throw Failure.emptyContent }

        let charset = charsetName(for: codepage)
        return Package(
            textData: text,
            charsetName: charset,
            title: exthText(exth, 503, charset, multiline: false) ?? fullName,
            author: exthText(exth, 100, charset, multiline: false),
            desc: exthText(exth, 103, charset, multiline: true),
            coverData: coverData(
                data: data,
                records: records,
                firstImageIndex: firstImageIndex,
                textRecordCount: Int(textRecordCount),
                coverOffset: exth[201]
            )
        )
    }

    // MARK: - PalmDB

    /// Bảng record của PalmDB: `numberOfRecords` @76, rồi `numberOfRecords × 8` byte
    /// `{ offset UInt32, attributes 1B, uniqueID 3B }`. Độ dài record `i` = `offset[i+1] - offset[i]`.
    /// Record có offset vô lý được giữ **chỗ** dưới dạng range rỗng để số hiệu record không lệch.
    private static func recordRanges(in data: Data) throws -> [Range<Int>] {
        guard data.count >= 78, let count = uint16(data, 76), count > 0 else {
            throw Failure.malformed("PalmDB header quá ngắn")
        }
        guard data.count >= 78 + Int(count) * 8 else {
            throw Failure.malformed("bảng record của PalmDB bị cắt")
        }

        var offsets: [Int] = []
        for index in 0..<Int(count) {
            guard let offset = uint32(data, 78 + index * 8) else { break }
            offsets.append(Int(offset))
        }
        guard !offsets.isEmpty else { throw Failure.malformed("PalmDB không có record nào") }

        var ranges: [Range<Int>] = []
        for (index, start) in offsets.enumerated() {
            let end = index + 1 < offsets.count ? offsets[index + 1] : data.count
            if start >= 0, start < end, end <= data.count {
                ranges.append(start..<end)
            } else {
                ranges.append(0..<0)
            }
        }
        guard !ranges[0].isEmpty else { throw Failure.malformed("record 0 của PalmDB rỗng") }
        return ranges
    }

    /// Ghép record `1 ..< 1 + count`: cắt trailing entry rồi giải nén (compression 2) hoặc dùng thẳng
    /// (compression 1).
    private static func textData(
        data: Data,
        records: [Range<Int>],
        count: Int,
        compression: UInt16,
        extraFlags: UInt16
    ) -> Data {
        let last = min(count, records.count - 1)
        guard last >= 1 else { return Data() }

        var output = Data()
        for index in 1...last {
            let raw = slice(data, records[index])
            guard !raw.isEmpty else { continue }
            let trimmed = PalmDocDecompressor.stripTrailingEntries(record: raw, flags: extraFlags)
            guard !trimmed.isEmpty else { continue }
            output.append(compression == 2 ? PalmDocDecompressor.decompress(trimmed) : trimmed)
        }
        return output
    }

    // MARK: - EXTH

    /// `"EXTH"`, `headerLength`, `recordCount`, rồi từng record `{ type UInt32, length UInt32, data }`
    /// với `length` **gồm cả** 8 byte header. Giữ giá trị đầu tiên của mỗi `type`.
    private static func exthRecords(record0: Data, offset: Int) -> [UInt32: Data] {
        guard ascii(record0, offset, 4) == "EXTH", let count = uint32(record0, offset + 8) else {
            return [:]
        }

        var result: [UInt32: Data] = [:]
        var cursor = offset + 12
        for _ in 0..<min(Int(count), 512) {
            guard let type = uint32(record0, cursor),
                  let length = uint32(record0, cursor + 4),
                  length >= 8
            else { break }
            let end = cursor + Int(length)
            guard end <= record0.count else { break }
            if result[type] == nil {
                result[type] = subrange(record0, cursor + 8, end)
            }
            cursor = end
        }
        return result
    }

    private static func exthText(
        _ records: [UInt32: Data],
        _ type: UInt32,
        _ charsetName: String?,
        multiline: Bool
    ) -> String? {
        guard let raw = records[type], !raw.isEmpty,
              let decoded = decodeString(Data(raw), charsetName: charsetName)
        else { return nil }
        // Mô tả trong EXTH thường là HTML; tên sách/tác giả đôi khi cũng có entity.
        let text = multiline
            ? XhtmlTextExtractor.plainText(html: decoded)
            : XhtmlTextExtractor.inlineText(html: decoded)
        return text.isEmpty ? nil : text
    }

    /// Tên sách trong MOBI header (`fullNameOffset` @0x54, `fullNameLength` @0x58) — dùng khi EXTH 503
    /// không có.
    private static func fullNameText(record0: Data, codepage: UInt32) -> String? {
        guard let offset = uint32(record0, 0x54),
              let length = uint32(record0, 0x58),
              length > 0, length < 1024
        else { return nil }
        let end = Int(offset) + Int(length)
        guard end <= record0.count else { return nil }
        let raw = subrange(record0, Int(offset), end)
        guard let decoded = decodeString(Data(raw), charsetName: charsetName(for: codepage)) else {
            return nil
        }
        let text = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    // MARK: - Ảnh bìa

    /// EXTH 201 là **thứ tự record ảnh** tính từ `firstImageIndex`. Record đó không phải ảnh (hoặc
    /// thiếu EXTH 201) thì lấy record ảnh **lớn nhất** — bìa gần như luôn là ảnh nặng nhất.
    private static func coverData(
        data: Data,
        records: [Range<Int>],
        firstImageIndex: Int,
        textRecordCount: Int,
        coverOffset: Data?
    ) -> Data? {
        if firstImageIndex > 0, let coverOffset,
           let raw = uint32(Data(coverOffset), 0), raw != 0xFFFF_FFFF {
            let target = firstImageIndex + Int(raw)
            if target > 0, target < records.count {
                let record = slice(data, records[target])
                if isImage(record) { return Data(record) }
            }
        }

        let start = firstImageIndex > 0 ? firstImageIndex : textRecordCount + 1
        guard start < records.count else { return nil }
        var best: Data?
        for index in start..<records.count {
            let record = slice(data, records[index])
            guard isImage(record) else { continue }
            if best == nil || record.count > (best?.count ?? 0) {
                best = Data(record)
            }
        }
        return best
    }

    private static func isImage(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        let base = data.startIndex
        let head = [data[base], data[base + 1], data[base + 2], data[base + 3]]
        if head[0] == 0xFF, head[1] == 0xD8, head[2] == 0xFF { return true }
        if head == [0x89, 0x50, 0x4E, 0x47] { return true }
        if head == [0x47, 0x49, 0x46, 0x38] { return true }
        return false
    }

    // MARK: - Bảng mã

    /// `codepage` của MOBI chỉ thực tế có hai giá trị; tên trả về khớp `TextEncodingDecoder`.
    private static func charsetName(for codepage: UInt32) -> String? {
        switch codepage {
        case 65001: return "65001"
        case 1252: return "1252"
        default: return nil
        }
    }

    private static func decodeString(_ data: Data, charsetName: String?) -> String? {
        if let charsetName,
           let text = TextEncodingDecoder.decodeDeclared(data, charsetName: charsetName),
           !text.isEmpty {
            return text
        }
        if let text = String(data: data, encoding: .utf8), !text.isEmpty { return text }
        let fallback = TextEncodingDecoder.decode(data)
        return fallback.isEmpty ? nil : fallback
    }

    // MARK: - Đọc byte có kiểm biên

    private static func slice(_ data: Data, _ range: Range<Int>) -> Data {
        return subrange(data, range.lowerBound, range.upperBound)
    }

    /// Cắt theo offset **tương đối với đầu `data`** — `Data` sau khi slice có `startIndex != 0` nên
    /// mọi phép đọc đều phải cộng `startIndex`.
    private static func subrange(_ data: Data, _ lower: Int, _ upper: Int) -> Data {
        guard lower >= 0, lower <= upper, upper <= data.count else { return Data() }
        let base = data.startIndex
        return data[(base + lower)..<(base + upper)]
    }

    private static func uint16(_ data: Data, _ offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= data.count else { return nil }
        let base = data.startIndex + offset
        return (UInt16(data[base]) << 8) | UInt16(data[base + 1])
    }

    private static func uint32(_ data: Data, _ offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= data.count else { return nil }
        let base = data.startIndex + offset
        return (UInt32(data[base]) << 24)
            | (UInt32(data[base + 1]) << 16)
            | (UInt32(data[base + 2]) << 8)
            | UInt32(data[base + 3])
    }

    private static func ascii(_ data: Data, _ offset: Int, _ length: Int) -> String? {
        let raw = subrange(data, offset, offset + length)
        guard raw.count == length else { return nil }
        return String(data: Data(raw), encoding: .isoLatin1)
    }
}
