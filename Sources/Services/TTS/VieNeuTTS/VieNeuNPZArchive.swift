import Accelerate
import Foundation

/// Đọc mảng `float` từ một file `.npz` (ZIP chứa các `.npy`) mà không cần thư viện ngoài.
///
/// `vieneu_v3_heads.npz` giữ bảng embedding **tied** của model — vừa là bảng tra khi dựng input,
/// vừa là ma trận đầu ra khi tính logits — nên không thể tránh việc phải đọc nó bằng Swift.
///
/// Hai điểm khiến bản này khác cách viết trực tiếp:
///
/// 1. **Đi qua central directory**, không quét từng byte tìm chữ ký `PK\x03\x04`. Quét tuần tự trên
///    một `Data` 52 MB vừa chậm vừa có thể ăn phải chữ ký nằm trong dữ liệu float.
/// 2. **Chuyển fp16 → fp32 bằng `vImageConvert_Planar16FtoPlanarF`**, không phải vòng lặp từng phần
///    tử. Bảng `audio_emb` có 12.6 triệu phần tử; vòng lặp `Float(Float16(bitPattern:))` là phần
///    lớn của 3.7 giây khởi động đo được ở bản thử nghiệm.
struct VieNeuNPZArchive {
    private enum NPYDataType {
        case float16
        case float32

        var bytesPerElement: Int {
            switch self {
            case .float16: return 2
            case .float32: return 4
            }
        }
    }

    private struct Entry {
        let name: String
        /// Offset của local file header trong file.
        let localHeaderOffset: Int
        let compressedSize: Int
        let uncompressedSize: Int
        /// 0 = stored. `np.savez` dùng stored; `np.savez_compressed` dùng deflate (8).
        let compressionMethod: Int
    }

    private let data: Data
    private let entries: [String: Entry]

    init(url: URL) throws {
        // `mappedIfSafe` để 52 MB nằm ở page cache file-backed thay vì ngốn hẳn heap.
        self.data = try Data(contentsOf: url, options: .mappedIfSafe)
        self.entries = try Self.readCentralDirectory(data)
    }

    var availableNames: [String] { Array(entries.keys) }

    func contains(_ name: String) -> Bool {
        entries[name] != nil || entries["\(name).npy"] != nil
    }

    /// Đọc một mảng thành `[Float]`, chuyển đổi dtype nếu cần.
    ///
    /// - Parameter expectedCount: số phần tử bắt buộc. Truyền `nil` khi chưa biết (ví dụ vector
    ///   bias mà chiều lấy từ chính header).
    func floatArray(named name: String, expectedCount: Int? = nil) throws -> [Float] {
        guard let entry = entries[name] ?? entries["\(name).npy"] else {
            throw TTSError.internalError("Không tìm thấy '\(name)' trong npz (có: \(availableNames.joined(separator: ", ")))")
        }
        guard entry.compressionMethod == 0 else {
            throw TTSError.internalError(
                "'\(name)' bị nén (method \(entry.compressionMethod)); cần npz lưu bằng np.savez, không phải savez_compressed"
            )
        }

        let payloadStart = try Self.payloadOffset(data, entry: entry)
        let (dataType, elementCount, headerEnd) = try Self.readNPYHeader(data, offset: payloadStart)
        let count = expectedCount ?? elementCount
        guard elementCount >= count else {
            throw TTSError.internalError("'\(name)' chỉ có \(elementCount) phần tử, cần \(count)")
        }

        let byteCount = count * dataType.bytesPerElement
        guard headerEnd + byteCount <= data.count else {
            throw TTSError.internalError("'\(name)' vượt biên file npz")
        }

        switch dataType {
        case .float32:
            var output = [Float](repeating: 0, count: count)
            _ = output.withUnsafeMutableBytes { destination in
                data.copyBytes(to: destination, from: headerEnd..<(headerEnd + byteCount))
            }
            return output
        case .float16:
            var halves = [UInt16](repeating: 0, count: count)
            _ = halves.withUnsafeMutableBytes { destination in
                data.copyBytes(to: destination, from: headerEnd..<(headerEnd + byteCount))
            }
            return Self.convertHalvesToFloats(halves)
        }
    }

    /// Đọc một số vô hướng (ví dụ `xvec_ln_eps`).
    func scalar(named name: String) throws -> Float {
        try floatArray(named: name, expectedCount: 1).first ?? 0
    }

    // MARK: - fp16 → fp32

    /// Chia thành nhiều "hàng" thay vì một hàng 12.6 triệu pixel: vImage nhận `vImagePixelCount`
    /// rất lớn nhưng hình dạng 2D giữ `rowBytes` ở mức lành mạnh và không phụ thuộc vào giới hạn
    /// chiều rộng của bản cài đặt.
    private static func convertHalvesToFloats(_ halves: [UInt16]) -> [Float] {
        let count = halves.count
        var output = [Float](repeating: 0, count: count)
        guard count > 0 else { return output }

        let rowWidth = 768
        let rows = count / rowWidth
        let remainder = count % rowWidth

        halves.withUnsafeBufferPointer { sourceBuffer in
            output.withUnsafeMutableBufferPointer { destinationBuffer in
                guard let sourceBase = sourceBuffer.baseAddress,
                      let destinationBase = destinationBuffer.baseAddress else { return }

                if rows > 0 {
                    var source = vImage_Buffer(
                        data: UnsafeMutableRawPointer(mutating: sourceBase),
                        height: vImagePixelCount(rows),
                        width: vImagePixelCount(rowWidth),
                        rowBytes: rowWidth * 2
                    )
                    var destination = vImage_Buffer(
                        data: UnsafeMutableRawPointer(destinationBase),
                        height: vImagePixelCount(rows),
                        width: vImagePixelCount(rowWidth),
                        rowBytes: rowWidth * 4
                    )
                    vImageConvert_Planar16FtoPlanarF(&source, &destination, 0)
                }

                if remainder > 0 {
                    let offset = rows * rowWidth
                    var source = vImage_Buffer(
                        data: UnsafeMutableRawPointer(mutating: sourceBase + offset),
                        height: 1,
                        width: vImagePixelCount(remainder),
                        rowBytes: remainder * 2
                    )
                    var destination = vImage_Buffer(
                        data: UnsafeMutableRawPointer(destinationBase + offset),
                        height: 1,
                        width: vImagePixelCount(remainder),
                        rowBytes: remainder * 4
                    )
                    vImageConvert_Planar16FtoPlanarF(&source, &destination, 0)
                }
            }
        }
        return output
    }

    // MARK: - ZIP

    private static func uint16(_ data: Data, _ offset: Int) -> Int {
        guard offset + 2 <= data.count else { return 0 }
        return Int(data[offset]) | (Int(data[offset + 1]) << 8)
    }

    private static func uint32(_ data: Data, _ offset: Int) -> Int {
        guard offset + 4 <= data.count else { return 0 }
        return Int(data[offset])
            | (Int(data[offset + 1]) << 8)
            | (Int(data[offset + 2]) << 16)
            | (Int(data[offset + 3]) << 24)
    }

    private static func readCentralDirectory(_ data: Data) throws -> [String: Entry] {
        // EOCD nằm trong 22 byte cuối, cộng tối đa 65535 byte comment.
        let searchStart = max(0, data.count - 65_557)
        var eocd = -1
        var index = data.count - 22
        while index >= searchStart {
            if data[index] == 0x50, data[index + 1] == 0x4B, data[index + 2] == 0x05, data[index + 3] == 0x06 {
                eocd = index
                break
            }
            index -= 1
        }
        guard eocd >= 0 else { throw TTSError.internalError("npz không có End Of Central Directory") }

        let entryCount = uint16(data, eocd + 10)
        var cursor = uint32(data, eocd + 16)
        var result: [String: Entry] = [:]

        for _ in 0..<entryCount {
            guard cursor + 46 <= data.count,
                  data[cursor] == 0x50, data[cursor + 1] == 0x4B,
                  data[cursor + 2] == 0x01, data[cursor + 3] == 0x02 else { break }

            let method = uint16(data, cursor + 10)
            let compressedSize = uint32(data, cursor + 20)
            let uncompressedSize = uint32(data, cursor + 24)
            let nameLength = uint16(data, cursor + 28)
            let extraLength = uint16(data, cursor + 30)
            let commentLength = uint16(data, cursor + 32)
            let localOffset = uint32(data, cursor + 42)

            let nameStart = cursor + 46
            guard nameStart + nameLength <= data.count else { break }
            let nameData = data.subdata(in: nameStart..<(nameStart + nameLength))
            if let name = String(data: nameData, encoding: .utf8) {
                result[name] = Entry(
                    name: name,
                    localHeaderOffset: localOffset,
                    compressedSize: compressedSize,
                    uncompressedSize: uncompressedSize,
                    compressionMethod: method
                )
            }
            cursor = nameStart + nameLength + extraLength + commentLength
        }

        guard !result.isEmpty else { throw TTSError.internalError("npz không có entry nào") }
        return result
    }

    /// Nội dung entry bắt đầu sau local header: 30 byte cố định + tên + extra field.
    /// Extra field của local header **có thể khác** của central directory, nên phải đọc lại ở đây.
    private static func payloadOffset(_ data: Data, entry: Entry) throws -> Int {
        let base = entry.localHeaderOffset
        guard base + 30 <= data.count,
              data[base] == 0x50, data[base + 1] == 0x4B,
              data[base + 2] == 0x03, data[base + 3] == 0x04 else {
            throw TTSError.internalError("Local header của '\(entry.name)' không hợp lệ")
        }
        let nameLength = uint16(data, base + 26)
        let extraLength = uint16(data, base + 28)
        return base + 30 + nameLength + extraLength
    }

    // MARK: - NPY

    /// Trả về `(dtype, số phần tử, offset bắt đầu dữ liệu)`.
    private static func readNPYHeader(_ data: Data, offset: Int) throws -> (NPYDataType, Int, Int) {
        guard offset + 10 <= data.count,
              data[offset] == 0x93,
              data[offset + 1] == 0x4E, data[offset + 2] == 0x55,
              data[offset + 3] == 0x4D, data[offset + 4] == 0x50, data[offset + 5] == 0x59 else {
            throw TTSError.internalError("Thiếu magic \\x93NUMPY trong npz entry")
        }

        let major = data[offset + 6]
        let headerLength: Int
        let headerStart: Int
        switch major {
        case 1:
            headerLength = uint16(data, offset + 8)
            headerStart = offset + 10
        case 2, 3:
            headerLength = uint32(data, offset + 8)
            headerStart = offset + 12
        default:
            throw TTSError.internalError("Không hỗ trợ NPY phiên bản \(major)")
        }

        guard headerStart + headerLength <= data.count else {
            throw TTSError.internalError("Header NPY vượt biên")
        }
        let headerData = data.subdata(in: headerStart..<(headerStart + headerLength))
        guard let header = String(data: headerData, encoding: .ascii) else {
            throw TTSError.internalError("Header NPY không phải ASCII")
        }
        let compact = header.replacingOccurrences(of: " ", with: "")

        guard !compact.contains("'fortran_order':True") else {
            throw TTSError.internalError("Không hỗ trợ NPY fortran_order")
        }

        let dataType: NPYDataType
        if compact.contains("'descr':'<f2'") || compact.contains("'descr':'|f2'") {
            dataType = .float16
        } else if compact.contains("'descr':'<f4'") || compact.contains("'descr':'|f4'") {
            dataType = .float32
        } else {
            throw TTSError.internalError("dtype NPY không hỗ trợ trong header: \(compact)")
        }

        let elementCount = Self.parseShapeProduct(compact)
        guard elementCount > 0 else {
            throw TTSError.internalError("Không đọc được shape từ header NPY: \(compact)")
        }
        return (dataType, elementCount, headerStart + headerLength)
    }

    /// Nhân các chiều trong `'shape':(a,b,c,)`. Shape rỗng `()` là vô hướng ⇒ 1 phần tử.
    private static func parseShapeProduct(_ compactHeader: String) -> Int {
        guard let shapeRange = compactHeader.range(of: "'shape':(") else { return 0 }
        let afterOpen = compactHeader[shapeRange.upperBound...]
        guard let closeIndex = afterOpen.firstIndex(of: ")") else { return 0 }
        let body = afterOpen[afterOpen.startIndex..<closeIndex]
        let dimensions = body
            .split(separator: ",", omittingEmptySubsequences: true)
            .compactMap { Int($0) }
        if dimensions.isEmpty { return body.isEmpty ? 1 : 0 }
        return dimensions.reduce(1, *)
    }
}
