import Foundation

/// Đọc `.npz` tham chiếu tự test — hỗ trợ `float32`, `float64`, `int64`, `int32`, `bool`
/// (NPZReader chính chỉ đọc float32/float16 và không được sửa vì `VieNeuConfig.load` đang dùng nó).
///
/// Dùng lại chiến thuật quét ZIP_STORED của `NPZReader` (không tin `uncompressedSize`, tự tính từ
/// `shape × elementSize`) và đọc từng byte để tránh lỗi căn chỉnh (Data không bảo đảm căn 4 byte).
struct GoldenNPZ {
    /// Một entry `.npy` đã bóc header — giữ vùng byte payload và `descr` để chuyển đổi theo kiểu.
    struct Tensor {
        let descr: String
        let shape: [Int]
        /// Vùng byte payload (đã bỏ qua header NPY).
        let payload: Data

        func floats() -> [Float] {
            switch descr {
            case let d where d.contains("<f4") || d.contains("|f4"):
                return readF32(payload)
            case let d where d.contains("<f8") || d.contains("|f8"):
                return readF64(payload)
            case let d where d.contains("<i8") || d.contains("|i8"):
                return readI64(payload).map(Float.init)
            case let d where d.contains("<i4") || d.contains("|i4"):
                return readI32(payload).map(Float.init)
            default:
                return readF32(payload)
            }
        }

        func int64s() -> [Int64] {
            readI64(payload)
        }

        func bools() -> [UInt8] {
            payload.map { $0 == 0 ? 0 : 1 }
        }
    }

    private let tensors: [String: Tensor]

    subscript(_ name: String) -> Tensor? { tensors[name] }

    init(url: URL) throws {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        self.tensors = try Self.parse(data)
    }

    // MARK: - Quét ZIP_STORED + NPY

    private static func parse(_ data: Data) throws -> [String: Tensor] {
        var out: [String: Tensor] = [:]
        var cursor = 0
        while cursor + 30 <= data.count {
            guard isLocalHeader(data, at: cursor) else { cursor += 1; continue }
            let compression = Int(data[cursor + 8]) | (Int(data[cursor + 9]) << 8)
            let nameLength = Int(data[cursor + 26]) | (Int(data[cursor + 27]) << 8)
            let extraLength = Int(data[cursor + 28]) | (Int(data[cursor + 29]) << 8)
            let nameStart = cursor + 30
            guard nameStart + nameLength <= data.count else { break }
            let name = String(decoding: data.subdata(in: nameStart..<(nameStart + nameLength)), as: UTF8.self)
            let entryStart = nameStart + nameLength + extraLength
            guard name.hasSuffix(".npy"), entryStart < data.count else {
                cursor = max(entryStart, cursor + 30)
                continue
            }
            guard compression == 0 else {
                throw NSError(domain: "GoldenNPZ", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(name) bị nén"])
            }
            guard let parsed = try? parseNPY(data, at: entryStart) else {
                cursor = max(entryStart, cursor + 30)
                continue
            }
            out[String(name.dropLast(4))] = parsed.tensor
            cursor = entryStart + parsed.byteCount
        }
        return out
    }

    private static func parseNPY(_ data: Data, at offset: Int) throws -> (tensor: Tensor, byteCount: Int) {
        guard offset + 12 <= data.count, isNpyMagic(data, at: offset) else {
            throw NSError(domain: "GoldenNPZ", code: 2, userInfo: [NSLocalizedDescriptionKey: "thiếu magic NPY"])
        }
        let major = Int(data[offset + 6])
        let headerLength: Int
        let headerStart: Int
        if major == 2 {
            guard offset + 16 <= data.count else { throw NSError(domain: "GoldenNPZ", code: 3, userInfo: nil) }
            headerLength = Int(readU32(data, at: offset + 8))
            headerStart = offset + 12
        } else {
            headerLength = Int(data[offset + 8]) | (Int(data[offset + 9]) << 8)
            headerStart = offset + 10
        }
        guard headerStart + headerLength <= data.count else {
            throw NSError(domain: "GoldenNPZ", code: 4, userInfo: [NSLocalizedDescriptionKey: "header vượt biên"])
        }
        let header = String(decoding: data.subdata(in: headerStart..<(headerStart + headerLength)), as: UTF8.self)
            .replacingOccurrences(of: " ", with: "")
        let shape = parseShape(header)
        let elementCount = shape.isEmpty ? 1 : shape.reduce(1, *)
        let elementSize = elementSize(of: header)

        let payloadStart = headerStart + headerLength
        let payloadBytes = elementCount * elementSize
        guard payloadStart + payloadBytes <= data.count else {
            throw NSError(domain: "GoldenNPZ", code: 5, userInfo: [NSLocalizedDescriptionKey: "thiếu dữ liệu"])
        }
        let payload = data.subdata(in: payloadStart..<(payloadStart + payloadBytes))
        let tensor = Tensor(descr: header, shape: shape, payload: payload)
        return (tensor, payloadStart + payloadBytes - offset)
    }

    private static func elementSize(of header: String) -> Int {
        if header.contains("<f4") || header.contains("|f4") { return 4 }
        if header.contains("<f8") || header.contains("|f8") { return 8 }
        if header.contains("<i8") || header.contains("|i8") { return 8 }
        if header.contains("<i4") || header.contains("|i4") { return 4 }
        if header.contains("|b1") { return 1 }
        return 4
    }

    private static func parseShape(_ header: String) -> [Int] {
        guard let open = header.firstIndex(of: "("),
              let close = header[open...].firstIndex(of: ")") else { return [] }
        let inside = header[header.index(after: open)..<close]
        return inside.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }

    // MARK: - Đọc little-endian từng byte (tránh lỗi căn chỉnh)

    private static func readF32(_ data: Data) -> [Float] {
        var out = [Float](repeating: 0, count: data.count / 4)
        for i in 0..<out.count {
            let at = i * 4
            let bits = UInt32(data[at]) | (UInt32(data[at + 1]) << 8) | (UInt32(data[at + 2]) << 16) | (UInt32(data[at + 3]) << 24)
            out[i] = Float(bitPattern: bits)
        }
        return out
    }

    private static func readF64(_ data: Data) -> [Float] {
        var out = [Float](repeating: 0, count: data.count / 8)
        for i in 0..<out.count {
            let at = i * 8
            var bits: UInt64 = 0
            for j in 0..<8 { bits |= UInt64(data[at + j]) << (8 * j) }
            out[i] = Float(Double(bitPattern: bits))
        }
        return out
    }

    private static func readI64(_ data: Data) -> [Int64] {
        var out = [Int64](repeating: 0, count: data.count / 8)
        for i in 0..<out.count {
            let at = i * 8
            var bits: UInt64 = 0
            for j in 0..<8 { bits |= UInt64(data[at + j]) << (8 * j) }
            out[i] = Int64(bitPattern: bits)
        }
        return out
    }

    private static func readI32(_ data: Data) -> [Int32] {
        var out = [Int32](repeating: 0, count: data.count / 4)
        for i in 0..<out.count {
            let at = i * 4
            var bits: UInt32 = 0
            for j in 0..<4 { bits |= UInt32(data[at + j]) << (8 * j) }
            out[i] = Int32(bitPattern: bits)
        }
        return out
    }

    private static func readU32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8) | (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24)
    }

    private static func isLocalHeader(_ data: Data, at offset: Int) -> Bool {
        data[offset] == 0x50 && data[offset + 1] == 0x4b && data[offset + 2] == 0x03 && data[offset + 3] == 0x04
    }

    private static func isNpyMagic(_ data: Data, at offset: Int) -> Bool {
        data[offset] == 0x93 && data[offset + 1] == 0x4e && data[offset + 2] == 0x55
            && data[offset + 3] == 0x4d && data[offset + 4] == 0x50 && data[offset + 5] == 0x59
    }
}
