import Foundation

/// Gói nhiều đoạn audio thành **một** `Data` và mở lại.
///
/// Vì sao cần: `RemoteTTSSynthesisCoordinator` là chỗ giữ bất biến "một lượt tổng hợp remote tại một
/// thời điểm", và job của nó chuyển đúng kiểu `Data`. Một request Google gộp nhiều đoạn trả về **nhiều**
/// blob mp3, nên phải đóng chúng lại thành một `Data` để đi qua coordinator thay vì đổi actor đó thành
/// generic — sửa nó là chạm vào phần dedupe/huỷ/telemetry đang chạy đúng.
///
/// Khung nhị phân, little-endian: `[magic "FBT1"][count][len₀]…[lenₙ₋₁][bytes₀]…[bytesₙ₋₁]`, mỗi số là
/// `UInt32`. Có magic để một `Data` không phải khung (ví dụ mp3 lọt vào đường gộp) bị `decode` từ chối
/// ngay thay vì trả ra rác.
enum TTSBatchAudioPayload {
    private static let headerMagic: UInt32 = 0x4642_5431  // "FBT1"

    static func encode(_ parts: [Data]) -> Data {
        var out = Data()
        out.append(uint32: headerMagic)
        out.append(uint32: UInt32(parts.count))
        for part in parts {
            out.append(uint32: UInt32(part.count))
        }
        for part in parts {
            out.append(part)
        }
        return out
    }

    /// `nil` khi khung không hợp lệ — người gọi phải coi đó là lỗi tổng hợp, không được đoán.
    static func decode(_ data: Data) -> [Data]? {
        var cursor = 0
        guard let magic = data.readUInt32(at: &cursor), magic == headerMagic else { return nil }
        guard let count = data.readUInt32(at: &cursor), count > 0, count <= 64 else { return nil }

        var lengths: [Int] = []
        lengths.reserveCapacity(Int(count))
        for _ in 0..<count {
            guard let length = data.readUInt32(at: &cursor) else { return nil }
            lengths.append(Int(length))
        }
        let total = lengths.reduce(0, +)
        guard data.count - cursor == total else { return nil }

        var parts: [Data] = []
        parts.reserveCapacity(lengths.count)
        for length in lengths {
            let start = data.startIndex + cursor
            parts.append(data.subdata(in: start..<(start + length)))
            cursor += length
        }
        return parts
    }
}

private extension Data {
    /// Ghi 4 byte little-endian **tường minh** thay vì `Swift.withUnsafeBytes(of:_:)`: trong một
    /// `extension Data`, tên `withUnsafeBytes` không qualify sẽ khớp vào *instance method* của `Data`
    /// chứ không phải hàm toàn cục — đúng lỗi biên dịch của 1.3.332. Tự lắp byte cũng bỏ luôn phần
    /// phụ thuộc endianness của máy và không cần con trỏ.
    mutating func append(uint32 value: UInt32) {
        append(contentsOf: [
            UInt8(truncatingIfNeeded: value),
            UInt8(truncatingIfNeeded: value >> 8),
            UInt8(truncatingIfNeeded: value >> 16),
            UInt8(truncatingIfNeeded: value >> 24)
        ])
    }

    func readUInt32(at cursor: inout Int) -> UInt32? {
        guard count - cursor >= 4 else { return nil }
        let start = startIndex + cursor
        let byte0 = UInt32(self[start])
        let byte1 = UInt32(self[start + 1])
        let byte2 = UInt32(self[start + 2])
        let byte3 = UInt32(self[start + 3])
        cursor += 4
        return byte0 | (byte1 << 8) | (byte2 << 16) | (byte3 << 24)
    }
}
