import Foundation

/// Giải nén thân text của MOBI/PalmDOC.
///
/// Hai việc, tách khỏi `MobiArchiveReader` vì đây là thuật toán thuần trên byte:
/// 1. `stripTrailingEntries` — cắt phần metadata bám đuôi mỗi record text (nếu không cắt thì mỗi
///    biên 4096 byte lẫn vài ký tự rác);
/// 2. `decompress` — LZ77 biến thể PalmDOC.
///
/// Mọi vòng lặp đều kiểm biên: file MOBI hỏng không được làm crash, chỉ được ra text ngắn hơn.
enum PalmDocDecompressor {
    /// Cắt "trailing data entries" theo `extraDataFlags` của MOBI header.
    ///
    /// Mỗi bit 1…15 bật ⇒ cuối record có một entry, độ dài ghi bằng **số nguyên biến độ dài đọc
    /// ngược** (byte cuối là byte thấp nhất, bit 7 bật đánh dấu bắt đầu entry) và **đã bao gồm chính
    /// mấy byte độ dài đó**. Bit 0 (multibyte overlap) cắt thêm `1 + (byte cuối & 0x03)` byte.
    static func stripTrailingEntries(record: Data, flags: UInt16) -> Data {
        guard flags != 0 else { return record }
        var bytes = [UInt8](record)

        var trailers = 0
        var probe = flags >> 1
        while probe != 0 {
            trailers += Int(probe & 1)
            probe >>= 1
        }

        for _ in 0..<trailers {
            let size = trailingEntrySize(bytes)
            guard size > 0, size <= bytes.count else { return Data(bytes) }
            bytes.removeLast(size)
        }

        if flags & 0x01 != 0, let last = bytes.last {
            let extra = Int(last & 0x03) + 1
            guard extra <= bytes.count else { return Data() }
            bytes.removeLast(extra)
        }
        return Data(bytes)
    }

    private static func trailingEntrySize(_ bytes: [UInt8]) -> Int {
        guard !bytes.isEmpty else { return 0 }
        var size = 0
        for byte in bytes.suffix(4) {
            if byte & 0x80 != 0 { size = 0 }
            size = (size << 7) | Int(byte & 0x7F)
        }
        return size
    }

    /// LZ77 của PalmDOC:
    /// * `0x00` và `0x09…0x7F` — ký tự nguyên bản;
    /// * `0x01…0x08` — copy đúng `b` byte literal tiếp theo;
    /// * `0x80…0xBF` — cặp 2 byte: lùi `distance` byte trong output, copy `length` byte;
    /// * `0xC0…0xFF` — dấu cách + `b ^ 0x80`.
    static func decompress(_ input: Data) -> Data {
        let bytes = [UInt8](input)
        var output: [UInt8] = []
        output.reserveCapacity(bytes.count * 3)

        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            index += 1

            switch byte {
            case 0x00, 0x09...0x7F:
                output.append(byte)

            case 0x01...0x08:
                let end = min(index + Int(byte), bytes.count)
                output.append(contentsOf: bytes[index..<end])
                index = end

            case 0x80...0xBF:
                guard index < bytes.count else { break }
                let pair = (UInt16(byte) << 8) | UInt16(bytes[index])
                index += 1
                let distance = Int((pair >> 3) & 0x07FF)
                let length = Int(pair & 0x07) + 3
                guard distance > 0, distance <= output.count else { break }
                var source = output.count - distance
                for _ in 0..<length {
                    guard source < output.count else { break }
                    output.append(output[source])
                    source += 1
                }

            default:
                output.append(0x20)
                output.append(byte ^ 0x80)
            }
        }
        return Data(output)
    }
}
