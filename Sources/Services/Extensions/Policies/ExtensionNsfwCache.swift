import Foundation

/// Bộ nhớ đệm kết quả `ExtensionNsfwClassifier.isNsfw` theo `packageId`.
///
/// Classifier chuẩn hoá chuỗi (bỏ dấu, tách từ) trên tên + mô tả + tác giả nên tốn cỡ 0,1 ms/tiện ích, trong
/// khi Kho (~700 mục catalog) và Tìm kiếm mọi nguồn gọi lại ở **mỗi lượt vẽ**. Một mục đệm chỉ được dùng khi
/// bản `Extension` y hệt bản lúc tính (so `==`), nên sửa metadata/cờ `isNsfw` là tự tính lại — không cần xoá tay.
///
/// Có lock: gọi được từ thread bất kỳ.
final class ExtensionNsfwCache: @unchecked Sendable {
    static let shared = ExtensionNsfwCache()

    private struct Entry {
        let ext: Extension
        let isNsfw: Bool
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    private init() {}

    func isNsfw(_ ext: Extension) -> Bool {
        lock.lock()
        let cached = entries[ext.packageId]
        lock.unlock()
        if let cached, cached.ext == ext { return cached.isNsfw }

        let value = ExtensionNsfwClassifier.isNsfw(ext)
        lock.lock()
        entries[ext.packageId] = Entry(ext: ext, isNsfw: value)
        lock.unlock()
        return value
    }
}
