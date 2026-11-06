import Foundation

/// Gói JS (`ExtensionPackageBundle`) đã parse, giữ trong RAM cho `ExtensionPackageReader`.
///
/// - Khoá theo đường dẫn chuẩn hoá; mục chỉ dùng được khi (mtime, cỡ) của file **khớp đúng** lần `stat` vừa làm. Sửa
///   một file trong gói là ghi lại cả file ⇒ mốc đổi ⇒ parse lại.
/// - Lock chỉ bọc thao tác trên từ điển, không bao giờ giữ trong lúc đọc đĩa hay parse.
/// - Giới hạn theo số mục **và** tổng cỡ file (≈ RAM của chuỗi đã parse); vượt thì bỏ mục dùng lâu nhất. Đủ rộng để
///   "tìm mọi nguồn" qua vài chục tiện ích không phải parse lại mỗi lượt. Gói lớn hơn cả trần vẫn trả cho caller, chỉ
///   không được nhớ.
final class ExtensionPackageBundleCache: @unchecked Sendable {
    static let shared = ExtensionPackageBundleCache()

    static let maxEntries = 96
    static let maxTotalBytes: Int64 = 24 * 1024 * 1024

    private struct Entry {
        let modifiedAt: Double
        let size: Int64
        let bundle: ExtensionPackageBundle
        var lastUsed: UInt64
    }

    private var entries: [String: Entry] = [:]
    private var totalBytes: Int64 = 0
    private var tick: UInt64 = 0
    private let lock = NSLock()

    private init() {}

    /// Gói ở `url` ứng với mốc (mtime, cỡ) vừa `stat`. Đọc / parse lỗi ⇒ `nil` và bỏ mục cũ của đường dẫn này.
    func bundle(at url: URL, modifiedAt: Double, size: Int64) -> ExtensionPackageBundle? {
        let key = url.standardizedFileURL.path
        lock.lock()
        if var entry = entries[key], entry.modifiedAt == modifiedAt, entry.size == size {
            tick &+= 1
            entry.lastUsed = tick
            entries[key] = entry
            lock.unlock()
            return entry.bundle
        }
        lock.unlock()

        guard let data = try? Data(contentsOf: url),
              let bundle = try? ExtensionPackageBundle.decode(from: data) else {
            remove(path: key)
            return nil
        }
        store(bundle, key: key, modifiedAt: modifiedAt, size: size)
        return bundle
    }

    /// Bỏ mục của một đường dẫn (file gói đã mất / `stat` lỗi).
    func remove(path: String) {
        lock.lock()
        if let old = entries.removeValue(forKey: path) { totalBytes -= old.size }
        lock.unlock()
    }

    private func store(_ bundle: ExtensionPackageBundle, key: String, modifiedAt: Double, size: Int64) {
        lock.lock()
        defer { lock.unlock() }
        if let old = entries.removeValue(forKey: key) { totalBytes -= old.size }
        guard size <= Self.maxTotalBytes else { return }
        tick &+= 1
        entries[key] = Entry(modifiedAt: modifiedAt, size: size, bundle: bundle, lastUsed: tick)
        totalBytes += size
        while entries.count > Self.maxEntries || totalBytes > Self.maxTotalBytes,
              let oldest = entries.min(by: { $0.value.lastUsed < $1.value.lastUsed }) {
            entries.removeValue(forKey: oldest.key)
            totalBytes -= oldest.value.size
        }
    }
}
