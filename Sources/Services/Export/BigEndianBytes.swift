import Foundation

/// Nối số nguyên **big-endian** vào `Data` — định dạng PalmDB/MOBI dùng big-endian ở mọi field
/// (ngược với ZIP, nơi mọi field là little-endian và được `ZipStoreWriter` tự lo).
enum BigEndianBytes {
    static func appendUInt16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8(value & 0xFF))
    }

    static func appendUInt32(_ value: UInt32, to data: inout Data) {
        data.append(UInt8((value >> 24) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8(value & 0xFF))
    }

    /// Chuỗi ASCII 4 ký tự làm chữ ký (`"BOOK"`, `"MOBI"`, `"EXTH"`).
    static func appendSignature(_ signature: String, to data: inout Data) {
        data.append(Data(signature.utf8.prefix(4)))
    }

    /// `count` byte 0 — dùng cho các vùng "unknown" bắt buộc phải có trong MOBI header.
    static func appendZeros(_ count: Int, to data: inout Data) {
        data.append(Data(repeating: 0, count: count))
    }
}
