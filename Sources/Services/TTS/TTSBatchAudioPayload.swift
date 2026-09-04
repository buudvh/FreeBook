import Foundation

/// Gói nhiều đoạn audio thành **một** `Data` và mở lại.
///
/// Vì sao cần: `RemoteTTSSynthesisCoordinator` là chỗ giữ bất biến "một lượt tổng hợp remote tại một
/// thời điểm", và job của nó chuyển đúng kiểu `Data`. Một request Google gộp nhiều đoạn trả về **nhiều**
/// blob mp3, nên phải đóng chúng lại thành một `Data` để đi qua coordinator thay vì đổi actor đó thành
/// generic — sửa nó là chạm vào phần dedupe/huỷ/telemetry đang chạy đúng.
///
/// Khung nhị phân, little-endian: `[count: UInt32][len₀: UInt32]…[lenₙ₋₁: UInt32][bytes₀]…[bytesₙ₋₁]`.
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
    mutating func append(uint32 value: UInt32) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }

    func readUInt32(at cursor: inout Int) -> UInt32? {
        guard count - cursor >= 4 else { return nil }
        let start = startIndex + cursor
        let slice = self[start..<(start + 4)]
        cursor += 4
        return slice.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian }
    }
}
