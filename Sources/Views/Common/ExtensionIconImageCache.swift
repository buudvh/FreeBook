import UIKit

/// Cache ảnh `icon.png` của extension đọc từ đĩa.
///
/// `UIImage(contentsOfFile:)` **không** dùng cache dùng chung của UIKit (chỉ `UIImage(named:)` có),
/// nên trước 1.3.330 mỗi lần SwiftUI dựng lại một dòng là **một lần đọc đĩa + giải mã PNG** — và
/// `ExtensionIconView` nằm trong mọi dòng của Kệ sách, Khám phá, mục lục Reader.
///
/// Khoá cache gồm cả mốc sửa file nên cài lại extension là tự có ảnh mới, không cần API vô hiệu hoá.
/// Ảnh **không có** cũng được ghi nhớ (giá trị `nil`) để không stat + đọc lại mỗi lượt vẽ.
final class ExtensionIconImageCache: @unchecked Sendable {
    static let shared = ExtensionIconImageCache()

    private static let maxEntries = 128

    private var entries: [String: UIImage?] = [:]
    private let lock = NSLock()

    private init() {}

    func icon(forExtensionAt localPath: String) -> UIImage? {
        guard !localPath.isEmpty else { return nil }
        let iconPath = URL(fileURLWithPath: localPath).appendingPathComponent("icon.png").path
        let attributes = try? FileManager.default.attributesOfItem(atPath: iconPath)
        let modifiedAt = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let key = "\(iconPath)|\(modifiedAt)"

        lock.lock()
        if let cached = entries[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let image = modifiedAt > 0 ? UIImage(contentsOfFile: iconPath) : nil

        lock.lock()
        if entries.count >= Self.maxEntries {
            entries.removeAll(keepingCapacity: true)
        }
        entries[key] = image
        lock.unlock()
        return image
    }
}
