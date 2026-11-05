import Foundation

/// Kết quả một lần đo của màn Dung lượng (`StorageUsageScanner.scan()`): bất biến, đi qua ranh giới luồng.
public struct StorageUsageSnapshot: Sendable {
    public struct Entry: Sendable, Identifiable {
        public let category: StorageUsageCategory
        public let bytes: Int64
        public var id: String { category.rawValue }
    }

    /// Tổng dung lượng app đang chiếm (cả thư mục nhà của app).
    public let appBytes: Int64
    /// Các loại có dữ liệu (> 0 byte), xếp lớn → nhỏ.
    public let entries: [Entry]
    /// Dung lượng trống / tổng của máy; `nil` khi iOS không trả.
    public let deviceAvailableBytes: Int64?
    public let deviceTotalBytes: Int64?

    public func bytes(of category: StorageUsageCategory) -> Int64 {
        entries.first { $0.category == category }?.bytes ?? 0
    }

    public static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .file)
    }
}
