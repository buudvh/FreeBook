import Foundation

/// Đo dung lượng cho màn Dung lượng. Hàm thuần, chạy trên luồng nền (`Task.detached`), không đụng SwiftData.
///
/// Đo **dung lượng thật trên đĩa** (`totalFileAllocatedSize`, thiếu thì `fileAllocatedSize`, rồi `fileSize`) và đếm cả
/// file ẩn — khác `BackupPaths.directorySize` (chỉ cỡ logic, bỏ file ẩn, đúng cho ước tính Sao lưu nên giữ nguyên).
/// Không theo symlink (enumerator mặc định không đi vào thư mục symlink) ⇒ không đếm trùng.
///
/// Cùng lượt: dòng con của loại TTS (`StorageUsageTTSBreakdown`, tổng của loại lấy từ đó) và của "Khác"
/// (`StorageUsageHomeBreakdown`, chung lượt duyệt cả thư mục nhà), cộng tổng rác từ lượt `JunkScanner` truyền vào.
public enum StorageUsageScanner {
    static func scan(junk: JunkScanResult) -> StorageUsageSnapshot {
        var entries: [StorageUsageSnapshot.Entry] = []
        var details: [StorageUsageDetail] = []
        var listedBytes: Int64 = 0
        for category in StorageUsageCategory.allCases where category != .other {
            let bytes: Int64
            if category == .tts, let first = category.locations.first, case .directory(let root) = first {
                let tts = StorageUsageTTSBreakdown.measure(root: root, junk: junk)
                bytes = tts.totalBytes
                details += tts.details
            } else {
                bytes = category.locations.reduce(Int64(0)) { $0 + size(of: $1) }
            }
            listedBytes += bytes
            if bytes > 0 {
                entries.append(StorageUsageSnapshot.Entry(category: category, bytes: bytes))
            }
        }

        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let homeWalk = StorageUsageHomeBreakdown.measure(home: home)
        let appBytes = max(homeWalk.homeBytes, listedBytes)
        let otherBytes = appBytes - listedBytes
        if otherBytes > 0 {
            entries.append(StorageUsageSnapshot.Entry(category: .other, bytes: otherBytes))
            details += homeWalk.details(otherBytes: otherBytes)
        }
        homeWalk.logUnknown()
        entries.sort { $0.bytes > $1.bytes }

        let volume = try? home.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeTotalCapacityKey
        ])
        return StorageUsageSnapshot(
            appBytes: appBytes,
            entries: entries,
            deviceAvailableBytes: volume?.volumeAvailableCapacityForImportantUsage,
            deviceTotalBytes: volume?.volumeTotalCapacity.map { Int64($0) },
            measuredAt: Date(),
            details: details,
            junkBytes: junk.totalBytes
        )
    }

    // MARK: - Đo

    static let sizeKeys: Set<URLResourceKey> = [
        .isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey
    ]

    static func size(of location: StorageUsageCategory.Location) -> Int64 {
        switch location {
        case .directory(let url):
            return directorySize(url)
        case .filesWithPrefix(let directory, let prefix):
            let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
            return names
                .filter { $0.hasPrefix(prefix) }
                .reduce(Int64(0)) { total, name in total + fileSize(directory.appendingPathComponent(name)) }
        }
    }

    static func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(sizeKeys),
            options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }
        var total: Int64 = 0
        for case let item as URL in enumerator {
            total += fileSize(item)
        }
        return total
    }

    /// Dung lượng thật của một file thường (thư mục / symlink ⇒ 0).
    static func fileSize(_ url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: sizeKeys), values.isRegularFile == true else { return 0 }
        let bytes = values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0
        return Int64(bytes)
    }
}
