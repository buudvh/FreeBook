import Foundation

/// Bộ đọc NPZ tối thiểu: lấy mảng `float32`/`float16` của các entry `.npy` **không nén**.
///
/// Không dùng `ZIPFoundation` dù app đã có dependency đó: `constants.npz` đã xác minh là ZIP_STORED
/// nên đường đọc thẳng ngắn hơn hẳn, và tránh việc một thư viện ZIP đời mới tự "sửa" hành vi nén.
///
/// ## Bẫy đã trả giá bằng một lần hỏng thật: **đừng tin `uncompressedSize` của ZIP local header**
/// `np.savez` ghi `0xFFFFFFFF` vào trường `compressed size`/`uncompressed size` của local header (sentinel
/// ZIP64) và để kích thước thật ở **extra field** / **central directory**. Bản đầu của file này đọc
/// thẳng trường đó nên ra `4.294.967.295`, rồi `throw` "vượt biên file"; và vì `VieNeuTTSEngine` khi đó
/// gán `runtime` **trước** khi nạp config, người dùng chỉ thấy một thông báo sai chỗ ("Graph runtime…")
/// trong khi nguyên nhân thật nằm ở đây.
///
/// Cách đọc bây giờ **không phụ thuộc kích thước của ZIP**: sau header local, kiểm magic `\x93NUMPY`, đọc
/// header NPY để lấy `shape` và `descr`, rồi tự tính số byte cần (`số phần tử × kích thước phần tử`).
/// Nhờ vậy con trỏ nhảy qua đúng vùng dữ liệu — cũng là điều kiện để không quét nhầm một chuỗi
/// `PK\x03\x04` tình cờ nằm trong dữ liệu float.
enum NPZReader {
    /// Cố ý **không** đặt tên là `Array`: một type lồng tên `Array` trong tầm nhìn sẽ làm mọi chỗ viết
    /// `Array(...)` trong file này phải suy luận xem đang trỏ vào `Swift.Array` hay vào type lồng.
    struct FloatArray {
        let shape: [Int]
        let values: [Float]
    }

    private static let localHeaderSignature: [UInt8] = [0x50, 0x4b, 0x03, 0x04]
    private static let npyMagic: [UInt8] = [0x93, 0x4e, 0x55, 0x4d, 0x50, 0x59] // "\x93NUMPY"

    static func read(url: URL) throws -> [String: FloatArray] {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        var arrays: [String: FloatArray] = [:]

        var cursor = 0
        while cursor + 30 <= data.count {
            guard matches(data, at: cursor, signature: localHeaderSignature) else {
                cursor += 1
                continue
            }
            let compression = Int(data[cursor + 8]) | (Int(data[cursor + 9]) << 8)
            let filenameLength = Int(data[cursor + 26]) | (Int(data[cursor + 27]) << 8)
            let extraLength = Int(data[cursor + 28]) | (Int(data[cursor + 29]) << 8)
            let nameStart = cursor + 30
            guard nameStart + filenameLength <= data.count else { break }

            let nameData = data.subdata(in: nameStart..<(nameStart + filenameLength))
            let name = String(decoding: nameData, as: UTF8.self)
            let entryStart = nameStart + filenameLength + extraLength

            guard name.hasSuffix(".npy"), entryStart < data.count else {
                // Không phải entry NPY: nhảy qua header rồi quét tiếp. `entryStart >= cursor + 30` nên
                // vòng lặp luôn tiến, không thể kẹt.
                cursor = entryStart
                continue
            }
            guard compression == 0 else {
                throw VieNeuConfig.LoadError.badNPZ("\(name) bị nén (compress_type=\(compression))")
            }

            let parsed = try parseNPY(data, at: entryStart, name: name)
            arrays[String(name.dropLast(4))] = parsed.array
            cursor = entryStart + parsed.byteCount
        }

        return arrays
    }

    /// Đọc một khối NPY nằm ở `offset` trong `data`. Trả về mảng **và** số byte đã tiêu thụ để bên gọi
    /// nhảy qua đúng vùng dữ liệu.
    private static func parseNPY(_ data: Data, at offset: Int, name: String) throws -> (array: FloatArray, byteCount: Int) {
        guard offset + 12 <= data.count, matches(data, at: offset, signature: npyMagic) else {
            throw VieNeuConfig.LoadError.badNPZ("\(name) không có magic NPY")
        }
        let major = Int(data[offset + 6])
        let headerLength: Int
        let headerStart: Int
        if major == 2 {
            guard offset + 16 <= data.count else { throw VieNeuConfig.LoadError.badNPZ("\(name) header cụt") }
            headerLength = Int(readUInt32(data, at: offset + 8))
            headerStart = offset + 12
        } else {
            headerLength = Int(data[offset + 8]) | (Int(data[offset + 9]) << 8)
            headerStart = offset + 10
        }
        guard headerStart + headerLength <= data.count else {
            throw VieNeuConfig.LoadError.badNPZ("\(name) header vượt biên")
        }

        let headerData = data.subdata(in: headerStart..<(headerStart + headerLength))
        let header = String(decoding: headerData, as: UTF8.self).replacingOccurrences(of: " ", with: "")
        let shape = parseShape(header)
        let elementCount = shape.isEmpty ? 1 : shape.reduce(1, *)

        let elementSize: Int
        if header.contains("<f4") || header.contains("|f4") {
            elementSize = 4
        } else if header.contains("<f2") || header.contains("|f2") {
            elementSize = 2
        } else {
            throw VieNeuConfig.LoadError.badNPZ("\(name) dùng descr chưa hỗ trợ")
        }

        let payloadStart = headerStart + headerLength
        let payloadBytes = elementCount * elementSize
        guard payloadStart + payloadBytes <= data.count else {
            throw VieNeuConfig.LoadError.badNPZ("\(name) thiếu dữ liệu")
        }

        // Đọc **từng byte** chứ không `withMemoryRebound`: `Data` không bảo đảm căn chỉnh 4 byte, và
        // rebind một con trỏ lệch căn chỉnh là hành vi không xác định — repo cũ đã crash thật ở đúng
        // dạng lỗi này (`c838327 Fix memory alignment load crashes`).
        var values = [Float](repeating: 0, count: elementCount)
        if elementSize == 4 {
            for index in 0..<elementCount {
                let at = payloadStart + index * 4
                let bits = UInt32(data[at])
                    | (UInt32(data[at + 1]) << 8)
                    | (UInt32(data[at + 2]) << 16)
                    | (UInt32(data[at + 3]) << 24)
                values[index] = Float(bitPattern: bits)
            }
        } else {
            for index in 0..<elementCount {
                let at = payloadStart + index * 2
                let bits = UInt16(data[at]) | (UInt16(data[at + 1]) << 8)
                values[index] = Float(Float16(bitPattern: bits))
            }
        }

        let byteCount = (payloadStart + payloadBytes) - offset
        return (FloatArray(shape: shape, values: values), byteCount)
    }

    private static func parseShape(_ header: String) -> [Int] {
        guard let open = header.firstIndex(of: "("),
              let close = header[open...].firstIndex(of: ")") else { return [] }
        let inside = header[header.index(after: open)..<close]
        return inside
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }

    private static func matches(_ data: Data, at offset: Int, signature: [UInt8]) -> Bool {
        guard offset >= 0, offset + signature.count <= data.count else { return false }
        for index in signature.indices {
            if data[offset + index] != signature[index] { return false }
        }
        return true
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else { return 0 }
        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}
