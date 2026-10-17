import Foundation
import UIKit

/// Cache đĩa cho byte ảnh comic đọc online: `Caches/comic_images/<sha256(key)>`, giới hạn 400 MB.
///
/// Thư mục `Caches` là **chủ ý**: dữ liệu tải lại được, hệ điều hành được phép xoá khi thiếu chỗ. Ảnh tải
/// offline nằm ở chỗ khác (`ComicOfflineStore`, `applicationSupport/comics/`) và không bao giờ đi qua đây.
///
/// Thread-safe: đọc/ghi file gọi thẳng từ luồng gọi (luôn là luồng nền của `ComicImageLoader`); sổ dung
/// lượng ước lượng giữ dưới `lock`; dọn file cũ nhất chạy trên `trimQueue` (serial) khi vượt giới hạn hoặc
/// khi app vào background.
final class ComicImageDiskCache: @unchecked Sendable {
    static let byteLimit: Int64 = 400 * 1024 * 1024
    /// Dọn về 75% giới hạn để không phải dọn lại ngay sau vài ảnh kế.
    static let trimTarget: Int64 = byteLimit * 3 / 4

    private let directory: URL
    private let fileManager = FileManager.default
    private let trimQueue = DispatchQueue(label: "com.freebook.comic-image-disk-cache", qos: .utility)
    private let lock = NSLock()
    /// Tổng byte ước lượng; `nil` = chưa đo (đo lần đầu trong lượt dọn).
    private var estimatedBytes: Int64?
    private var isTrimScheduled = false

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent("comic_images", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)

        // Đăng ký trên MainActor: hằng tên notification thuộc `UIApplication` (@MainActor).
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = NotificationCenter.default.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.scheduleTrim()
            }
            self.scheduleTrim()
        }
    }

    // MARK: - Đọc / ghi

    func data(forKey key: String) -> Data? {
        let url = fileURL(forKey: key)
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        // "Cũ nhất" tính theo lần dùng gần nhất: chạm mtime khi trúng cache.
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return data
    }

    func store(_ data: Data, forKey key: String) {
        guard !data.isEmpty else { return }
        let url = fileURL(forKey: key)
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            AppLogger.shared.log("❌ [ComicImageDiskCache] Lỗi ghi cache ảnh: \(error.localizedDescription)")
            return
        }

        lock.lock()
        var needsTrim = false
        if let current = estimatedBytes {
            let updated = current + Int64(data.count)
            estimatedBytes = updated
            needsTrim = updated > Self.byteLimit
        }
        lock.unlock()
        if needsTrim {
            scheduleTrim()
        }
    }

    /// Bỏ một mục (byte đã cache nhưng không giải mã được). Sổ dung lượng ước lượng để nguyên — lượt dọn kế đo lại.
    func remove(forKey key: String) {
        let url = fileURL(forKey: key)
        guard fileManager.fileExists(atPath: url.path) else { return }
        do {
            try fileManager.removeItem(at: url)
        } catch {
            AppLogger.shared.log("❌ [ComicImageDiskCache] Lỗi xoá mục cache ảnh hỏng: \(error.localizedDescription)")
        }
    }

    func removeAll() {
        trimQueue.async { [weak self] in
            guard let self else { return }
            try? self.fileManager.removeItem(at: self.directory)
            try? self.fileManager.createDirectory(at: self.directory, withIntermediateDirectories: true, attributes: nil)
            self.lock.lock()
            self.estimatedBytes = 0
            self.lock.unlock()
        }
    }

    // MARK: - Dọn dẹp

    /// Đo lại toàn thư mục rồi dọn nếu vượt giới hạn; gộp các yêu cầu chồng nhau thành một lượt.
    private func scheduleTrim() {
        lock.lock()
        if isTrimScheduled {
            lock.unlock()
            return
        }
        isTrimScheduled = true
        lock.unlock()

        trimQueue.async { [weak self] in
            self?.trimIfNeeded()
        }
    }

    private func trimIfNeeded() {
        defer {
            lock.lock()
            isTrimScheduled = false
            lock.unlock()
        }

        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return }

        var entries: [(url: URL, size: Int64, date: Date)] = []
        entries.reserveCapacity(urls.count)
        var total: Int64 = 0
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            let size = Int64(values.fileSize ?? 0)
            total += size
            entries.append((url: url, size: size, date: values.contentModificationDate ?? .distantPast))
        }

        if total > Self.byteLimit {
            entries.sort { $0.date < $1.date }
            var removedCount = 0
            for entry in entries where total > Self.trimTarget {
                do {
                    try fileManager.removeItem(at: entry.url)
                    total -= entry.size
                    removedCount += 1
                } catch {
                    continue
                }
            }
            AppLogger.shared.log("🧹 [ComicImageDiskCache] Dọn \(removedCount) ảnh cũ, còn \(total / 1_048_576) MB")
        }

        lock.lock()
        estimatedBytes = total
        lock.unlock()
    }

    private func fileURL(forKey key: String) -> URL {
        directory.appendingPathComponent(key.sha256(), isDirectory: false)
    }
}
