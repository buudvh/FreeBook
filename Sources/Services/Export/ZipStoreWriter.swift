import Foundation

/// Bộ ghi ZIP **stored** (không nén, method 0) dùng riêng cho EPUB.
///
/// Không dùng `BackupZipArchive`/ZIPFoundation vì hai lý do: EPUB bắt buộc entry `mimetype` phải là entry
/// **đầu tiên** và không nén, còn `BackupZipArchive` chỉ có API nén cả thư mục; và repo cố ý giới hạn
/// ZIPFoundation trong đúng một file (`BackupZipArchive.swift`) do `Archive.init` đổi chữ ký giữa các bản.
/// Archive toàn entry stored vẫn là ZIP hợp chuẩn, chỉ là không nén.
///
/// Ghi tuần tự: local file header + dữ liệu cho từng entry, central directory + EOCD lúc `finish()`. Không
/// hỗ trợ ZIP64 ⇒ vượt 4 GB thì `throw ExportRenderError.archiveTooLarge` thay vì tạo file hỏng.
final class ZipStoreWriter {
    /// Một entry đã ghi xong phần dữ liệu — chỉ còn chờ vào central directory.
    private struct Entry {
        let name: String
        let crc32: UInt32
        let size: UInt32
        let localHeaderOffset: UInt32
    }

    /// Giới hạn của ZIP không có ZIP64.
    private static let maxSize: Int = Int(UInt32.max)
    /// Mốc thời gian cố định 1980-01-01 00:00 — bản xuất cùng nội dung cho ra cùng byte.
    private static let dosTime: UInt16 = 0
    private static let dosDate: UInt16 = 0x0021

    private let staging: ExportStagingFile
    private var entries: [Entry] = []

    init(staging: ExportStagingFile) {
        self.staging = staging
    }

    var entryCount: Int { entries.count }

    func addEntry(name: String, text: String) throws {
        try addEntry(name: name, data: Data(text.utf8))
    }

    func addEntry(name: String, data: Data) throws {
        guard staging.bytesWritten + data.count + name.utf8.count + 30 <= Self.maxSize else {
            throw ExportRenderError.archiveTooLarge
        }
        let offset = UInt32(staging.bytesWritten)
        let crc = Self.crc32(of: data)
        let size = UInt32(data.count)

        var header = Data()
        Self.appendUInt32(0x04034B50, to: &header)   // local file header signature
        Self.appendUInt16(20, to: &header)           // version needed
        Self.appendUInt16(0, to: &header)            // flags
        Self.appendUInt16(0, to: &header)            // method: stored
        Self.appendUInt16(Self.dosTime, to: &header)
        Self.appendUInt16(Self.dosDate, to: &header)
        Self.appendUInt32(crc, to: &header)
        Self.appendUInt32(size, to: &header)         // compressed size == uncompressed
        Self.appendUInt32(size, to: &header)
        let nameBytes = Data(name.utf8)
        Self.appendUInt16(UInt16(nameBytes.count), to: &header)
        Self.appendUInt16(0, to: &header)            // extra field length
        header.append(nameBytes)

        try staging.write(header)
        try staging.write(data)
        entries.append(Entry(name: name, crc32: crc, size: size, localHeaderOffset: offset))
    }

    /// Ghi central directory + EOCD rồi đổi tên file tạm thành file đích.
    func finish() throws -> URL {
        let directoryOffset = staging.bytesWritten
        var directory = Data()
        for entry in entries {
            Self.appendUInt32(0x02014B50, to: &directory)  // central directory signature
            Self.appendUInt16(20, to: &directory)          // version made by
            Self.appendUInt16(20, to: &directory)          // version needed
            Self.appendUInt16(0, to: &directory)           // flags
            Self.appendUInt16(0, to: &directory)           // method: stored
            Self.appendUInt16(Self.dosTime, to: &directory)
            Self.appendUInt16(Self.dosDate, to: &directory)
            Self.appendUInt32(entry.crc32, to: &directory)
            Self.appendUInt32(entry.size, to: &directory)
            Self.appendUInt32(entry.size, to: &directory)
            let nameBytes = Data(entry.name.utf8)
            Self.appendUInt16(UInt16(nameBytes.count), to: &directory)
            Self.appendUInt16(0, to: &directory)           // extra field length
            Self.appendUInt16(0, to: &directory)           // comment length
            Self.appendUInt16(0, to: &directory)           // disk number start
            Self.appendUInt16(0, to: &directory)           // internal attributes
            Self.appendUInt32(0, to: &directory)           // external attributes
            Self.appendUInt32(entry.localHeaderOffset, to: &directory)
            directory.append(nameBytes)
        }

        // Chốt kích thước central directory **trước** khi nối EOCD vào cùng buffer.
        let directorySize = directory.count
        guard directoryOffset + directorySize + 22 <= Self.maxSize else {
            throw ExportRenderError.archiveTooLarge
        }

        Self.appendUInt32(0x06054B50, to: &directory)      // EOCD signature
        Self.appendUInt16(0, to: &directory)               // this disk
        Self.appendUInt16(0, to: &directory)               // disk with central directory
        Self.appendUInt16(UInt16(entries.count), to: &directory)
        Self.appendUInt16(UInt16(entries.count), to: &directory)
        Self.appendUInt32(UInt32(directorySize), to: &directory)
        Self.appendUInt32(UInt32(directoryOffset), to: &directory)
        Self.appendUInt16(0, to: &directory)               // comment length

        try staging.write(directory)
        return try staging.commit()
    }

    func discard() {
        staging.discard()
    }

    // MARK: - Số nguyên little-endian

    private static func appendUInt16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 24) & 0xFF))
    }

    // MARK: - CRC-32 (đa thức phản chiếu 0xEDB88320, đúng chuẩn ZIP)

    private static let crcTable: [UInt32] = {
        var table = [UInt32](repeating: 0, count: 256)
        for index in 0..<256 {
            var value = UInt32(index)
            for _ in 0..<8 {
                value = (value & 1 == 1) ? (0xEDB88320 ^ (value >> 1)) : (value >> 1)
            }
            table[index] = value
        }
        return table
    }()

    private static func crc32(of data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        data.withUnsafeBytes { raw in
            for byte in raw.bindMemory(to: UInt8.self) {
                crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
            }
        }
        return crc ^ 0xFFFFFFFF
    }
}
