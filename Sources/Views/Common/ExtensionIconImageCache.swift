import UIKit

/// Cache ảnh `icon.png` của extension đọc từ đĩa (`ExtensionPackageReader`: file trong thư mục hoặc base64 trong gói).
///
/// `UIImage(contentsOfFile:)` **không** dùng cache dùng chung của UIKit (chỉ `UIImage(named:)` có),
/// nên trước 1.3.330 mỗi lần SwiftUI dựng lại một dòng là **một lần đọc đĩa + giải mã PNG** — và
/// `ExtensionIconView` nằm trong mọi dòng của Kệ sách, Khám phá, mục lục Reader.
///
/// Khoá cache gồm cả mốc sửa (`ExtensionPackageReader.modificationStamp`: mtime của `icon.png` với thư mục, mtime + cỡ
/// của file gói) nên cài lại extension là tự có ảnh mới, không cần API vô hiệu hoá.
/// Ảnh **không có** cũng được ghi nhớ (giá trị `nil`) để không stat + đọc lại mỗi lượt vẽ. Gói đã mất (mốc `nil`) thì
/// không nhớ gì.
final class ExtensionIconImageCache: @unchecked Sendable {
    static let shared = ExtensionIconImageCache()

    private static let maxEntries = 128

    private struct Key: Hashable {
        let localPath: String
        let stamp: ExtensionPackageReader.Stamp
    }

    private var entries: [Key: UIImage?] = [:]
    private let lock = NSLock()

    private init() {}

    func icon(forExtensionAt localPath: String) -> UIImage? {
        guard !localPath.isEmpty,
              let stamp = ExtensionPackageReader.modificationStamp(
                localPath: localPath,
                relativePaths: [ExtensionPackageReader.iconFileName]
              ) else { return nil }
        let key = Key(localPath: localPath, stamp: stamp)

        lock.lock()
        if let cached = entries[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let image = ExtensionPackageReader.iconData(localPath: localPath).flatMap { UIImage(data: $0) }

        lock.lock()
        if entries.count >= Self.maxEntries {
            entries.removeAll(keepingCapacity: true)
        }
        entries[key] = image
        lock.unlock()
        return image
    }
}
