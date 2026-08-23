import Foundation

/// Dựng **record 0** của file MOBI: PalmDOC header (16 byte) + MOBI header (232 byte) + EXTH + tên sách.
///
/// Bản xuất cố ý dùng `compression = 1` (**không nén**): PalmDOC LZ77 chỉ tiết kiệm dung lượng, còn file
/// không nén thì Kindle, Calibre và mọi máy đọc MOBI vẫn mở bình thường — đổi lại code writer không phải
/// mang theo một bộ nén và không có nguy cơ sinh file hỏng. `encryptionType = 0` (không DRM).
///
/// Mọi field là big-endian; offset ghi trong comment tính từ đầu **MOBI header** để đối chiếu với đặc tả.
enum MobiHeaderBuilder {
    /// Kích thước một record text — hằng của PalmDOC, cũng là bước đọc file staging.
    static let textRecordSize = 4096
    private static let mobiHeaderLength = 232

    /// Mọi con số record 0 cần biết trước khi ghi (đều tính được trước khi mở file đích).
    struct Layout {
        let textLength: Int
        let textRecordCount: Int
        let fullName: String
        let author: String
        let desc: String
        /// Record đầu tiên không phải nội dung sách (ở đây: record ảnh bìa, hoặc record EOF).
        let firstNonBookIndex: Int
        let firstImageIndex: Int
        /// Vị trí record bìa **tương đối** với `firstImageIndex`; `nil` khi truyện không có bìa.
        let coverImageOffset: UInt32?
        let lastContentRecord: Int
        let uniqueId: UInt32
    }

    static func record0(_ layout: Layout) -> Data {
        let exth = exthBlock(layout)
        let fullNameBytes = Data(layout.fullName.utf8)
        let fullNameOffset = 16 + mobiHeaderLength + exth.count

        var data = Data()

        // MARK: PalmDOC header (16 byte)
        BigEndianBytes.appendUInt16(1, to: &data)                                    // compression: không nén
        BigEndianBytes.appendUInt16(0, to: &data)                                    // unused
        BigEndianBytes.appendUInt32(UInt32(layout.textLength), to: &data)
        BigEndianBytes.appendUInt16(UInt16(layout.textRecordCount), to: &data)
        BigEndianBytes.appendUInt16(UInt16(textRecordSize), to: &data)
        BigEndianBytes.appendUInt16(0, to: &data)                                    // encryption: không DRM
        BigEndianBytes.appendUInt16(0, to: &data)                                    // unused

        // MARK: MOBI header (232 byte)
        BigEndianBytes.appendSignature("MOBI", to: &data)                            // 0
        BigEndianBytes.appendUInt32(UInt32(mobiHeaderLength), to: &data)             // 4
        BigEndianBytes.appendUInt32(2, to: &data)                                    // 8   mobi type: book
        BigEndianBytes.appendUInt32(65001, to: &data)                                // 12  text encoding: UTF-8
        BigEndianBytes.appendUInt32(layout.uniqueId, to: &data)                      // 16
        BigEndianBytes.appendUInt32(6, to: &data)                                    // 20  file version
        for _ in 0..<10 {
            BigEndianBytes.appendUInt32(0xFFFFFFFF, to: &data)                       // 24  các index không dùng
        }
        BigEndianBytes.appendUInt32(UInt32(layout.firstNonBookIndex), to: &data)     // 64
        BigEndianBytes.appendUInt32(UInt32(fullNameOffset), to: &data)               // 68
        BigEndianBytes.appendUInt32(UInt32(fullNameBytes.count), to: &data)          // 72
        BigEndianBytes.appendUInt32(9, to: &data)                                    // 76  locale
        BigEndianBytes.appendUInt32(0, to: &data)                                    // 80  input language
        BigEndianBytes.appendUInt32(0, to: &data)                                    // 84  output language
        BigEndianBytes.appendUInt32(6, to: &data)                                    // 88  min version
        BigEndianBytes.appendUInt32(UInt32(layout.firstImageIndex), to: &data)       // 92
        BigEndianBytes.appendUInt32(0, to: &data)                                    // 96  huffman record offset
        BigEndianBytes.appendUInt32(0, to: &data)                                    // 100 huffman record count
        BigEndianBytes.appendUInt32(0, to: &data)                                    // 104 huffman table offset
        BigEndianBytes.appendUInt32(0, to: &data)                                    // 108 huffman table length
        BigEndianBytes.appendUInt32(0x40, to: &data)                                 // 112 EXTH flags: có EXTH
        BigEndianBytes.appendZeros(32, to: &data)                                    // 116 unknown
        BigEndianBytes.appendUInt32(0xFFFFFFFF, to: &data)                           // 148 unknown
        BigEndianBytes.appendUInt32(0xFFFFFFFF, to: &data)                           // 152 DRM offset: không có
        BigEndianBytes.appendUInt32(0, to: &data)                                    // 156 DRM count
        BigEndianBytes.appendUInt32(0, to: &data)                                    // 160 DRM size
        BigEndianBytes.appendUInt32(0, to: &data)                                    // 164 DRM flags
        BigEndianBytes.appendZeros(8, to: &data)                                     // 168 unknown
        BigEndianBytes.appendUInt16(1, to: &data)                                    // 176 first content record
        BigEndianBytes.appendUInt16(UInt16(layout.lastContentRecord), to: &data)     // 178 last content record
        BigEndianBytes.appendUInt32(1, to: &data)                                    // 180 unknown
        BigEndianBytes.appendUInt32(0xFFFFFFFF, to: &data)                           // 184 FCIS record: không ghi
        BigEndianBytes.appendUInt32(0, to: &data)                                    // 188 FCIS count
        BigEndianBytes.appendUInt32(0xFFFFFFFF, to: &data)                           // 192 FLIS record: không ghi
        BigEndianBytes.appendUInt32(0, to: &data)                                    // 196 FLIS count
        BigEndianBytes.appendZeros(8, to: &data)                                     // 200 unknown
        BigEndianBytes.appendUInt32(0xFFFFFFFF, to: &data)                           // 208 unknown
        BigEndianBytes.appendUInt32(0, to: &data)                                    // 212 compilation data count
        BigEndianBytes.appendUInt32(0xFFFFFFFF, to: &data)                           // 216 compilation sections
        BigEndianBytes.appendUInt32(0xFFFFFFFF, to: &data)                           // 220 unknown
        BigEndianBytes.appendUInt32(0, to: &data)                                    // 224 extra record data flags: không có
        BigEndianBytes.appendUInt32(0xFFFFFFFF, to: &data)                           // 228 INDX record offset

        // MARK: EXTH + tên sách
        data.append(exth)
        data.append(fullNameBytes)
        data.append(Data([0, 0]))
        while data.count % 4 != 0 {
            data.append(0)
        }
        return data
    }

    /// EXTH: metadata dạng `{ type, length, data }`. Đây là chỗ Kindle đọc tác giả, mô tả và ảnh bìa.
    private static func exthBlock(_ layout: Layout) -> Data {
        var records: [(type: UInt32, payload: Data)] = []
        if !layout.author.isEmpty {
            records.append((100, Data(layout.author.utf8)))
        }
        if !layout.desc.isEmpty {
            records.append((103, Data(layout.desc.utf8)))
        }
        records.append((503, Data(layout.fullName.utf8)))
        if let coverOffset = layout.coverImageOffset {
            var payload = Data()
            BigEndianBytes.appendUInt32(coverOffset, to: &payload)
            records.append((201, payload))
        }

        var body = Data()
        for record in records {
            BigEndianBytes.appendUInt32(record.type, to: &body)
            BigEndianBytes.appendUInt32(UInt32(record.payload.count + 8), to: &body)
            body.append(record.payload)
        }

        var padding = 0
        while (12 + body.count + padding) % 4 != 0 {
            padding += 1
        }

        var exth = Data()
        BigEndianBytes.appendSignature("EXTH", to: &exth)
        BigEndianBytes.appendUInt32(UInt32(12 + body.count + padding), to: &exth)
        BigEndianBytes.appendUInt32(UInt32(records.count), to: &exth)
        exth.append(body)
        BigEndianBytes.appendZeros(padding, to: &exth)
        return exth
    }
}
