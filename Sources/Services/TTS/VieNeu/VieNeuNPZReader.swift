import Foundation

/// Bộ đọc NPZ tối thiểu: chỉ lấy mảng `float32`/`float16` của các entry `.npy` **không nén**.
///
/// Không dùng `ZIPFoundation` dù app đã có dependency đó: `constants.npz` đã xác minh là ZIP_STORED
/// nên đường đọc thẳng ngắn hơn hẳn, và tránh việc một thư viện ZIP đời mới tự "sửa" hành vi nén.
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
            let uncompressedSize = readUInt32(data, at: cursor + 22)
            let filenameLength = Int(data[cursor + 26]) | (Int(data[cursor + 27]) << 8)
            let extraLength = Int(data[cursor + 28]) | (Int(data[cursor + 29]) << 8)
            let nameStart = cursor + 30
            guard nameStart + filenameLength <= data.count else { break }

            let nameData = data.subdata(in: nameStart..<(nameStart + filenameLength))
            let name = String(decoding: nameData, as: UTF8.self)
            let entryStart = nameStart + filenameLength + extraLength
            let entryEnd = entryStart + Int(uncompressedSize)

            defer { cursor = max(entryStart, cursor + 1) }

            guard name.hasSuffix(".npy"), entryStart < data.count else { continue }
            guard compression == 0 else {
                throw VieNeuConfig.LoadError.badNPZ("\(name) bị nén (compress_type=\(compression))")
            }
            guard entryEnd <= data.count else {
                throw VieNeuConfig.LoadError.badNPZ("\(name) vượt biên file")
            }

            let payload = data.subdata(in: entryStart..<entryEnd)
            arrays[String(name.dropLast(4))] = try parseNPY(payload, name: name)
        }

        return arrays
    }

    private static func parseNPY(_ payload: Data, name: String) throws -> FloatArray {
        guard payload.count > 12, matches(payload, at: 0, signature: npyMagic) else {
            throw VieNeuConfig.LoadError.badNPZ("\(name) không có magic NPY")
        }
        let major = Int(payload[6])
        let headerLength: Int
        let headerStart: Int
        if major == 2 {
            guard payload.count > 16 else { throw VieNeuConfig.LoadError.badNPZ("\(name) header cụt") }
            headerLength = Int(readUInt32(payload, at: 8))
            headerStart = 12
        } else {
            headerLength = Int(payload[8]) | (Int(payload[9]) << 8)
            headerStart = 10
        }
        guard headerStart + headerLength <= payload.count else {
            throw VieNeuConfig.LoadError.badNPZ("\(name) header vượt biên")
        }

        let headerData = payload.subdata(in: headerStart..<(headerStart + headerLength))
        let header = String(decoding: headerData, as: UTF8.self).replacingOccurrences(of: " ", with: "")
        let shape = parseShape(header)
        let dataStart = headerStart + headerLength

        let elementCount = shape.isEmpty ? 1 : shape.reduce(1, *)
        // Đọc **từng byte** chứ không `withMemoryRebound`: `Data` không bảo đảm căn chỉnh 4 byte, và
        // rebind một con trỏ lệch căn chỉnh là hành vi không xác định — repo cũ đã crash thật ở đúng
        // dạng lỗi này (`c838327 Fix memory alignment load crashes`). Chi phí không đáng kể: hai mảng
        // của `constants.npz` chỉ có 192 và 12.800 phần tử.
        if header.contains("<f4") || header.contains("|f4") {
            guard dataStart + elementCount * 4 <= payload.count else {
                throw VieNeuConfig.LoadError.badNPZ("\(name) thiếu dữ liệu float32")
            }
            var values = [Float](repeating: 0, count: elementCount)
            for index in 0..<elementCount {
                let offset = dataStart + index * 4
                let bits = UInt32(payload[offset])
                    | (UInt32(payload[offset + 1]) << 8)
                    | (UInt32(payload[offset + 2]) << 16)
                    | (UInt32(payload[offset + 3]) << 24)
                values[index] = Float(bitPattern: bits)
            }
            return FloatArray(shape: shape, values: values)
        }
        if header.contains("<f2") || header.contains("|f2") {
            guard dataStart + elementCount * 2 <= payload.count else {
                throw VieNeuConfig.LoadError.badNPZ("\(name) thiếu dữ liệu float16")
            }
            var values = [Float](repeating: 0, count: elementCount)
            for index in 0..<elementCount {
                let offset = dataStart + index * 2
                let bits = UInt16(payload[offset]) | (UInt16(payload[offset + 1]) << 8)
                values[index] = Float(Float16(bitPattern: bits))
            }
            return FloatArray(shape: shape, values: values)
        }
        throw VieNeuConfig.LoadError.badNPZ("\(name) dùng descr chưa hỗ trợ")
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
