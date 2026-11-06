import Foundation

/// Dọn thư mục `covers/` (1.3.762): tìm bìa mồ côi (không `Book` nào giữ), xoá chúng, và thu nhỏ bìa còn dùng mà quá cỡ.
///
/// Nằm ở owner vì mọi thao tác file phải qua `validatePathSafety` của chính `covers/`. Tầng trên
/// (`CoverCleanupCoordinator`) chỉ đưa vào danh sách `bookId` của thư viện. Mọi hàm có I/O: chỉ gọi ở luồng nền.
///
/// Một file **có chủ** khi tên trùng `sha256(bookId).jpg` hoặc tên kiểu cũ (`getLegacyFileName`, chỉ chuyển tên lười lúc
/// truyện được mở) của một `bookId` trong thư viện. File ghi / đổi tên chưa quá `minimumAge` thì bỏ qua: trang Chi tiết
/// vừa lưu truyện, bản khôi phục đang chép bìa trước khi ghi `Book`.
extension ImageCacheManager {
    /// Đếm trước: file mồ côi + (tuỳ chọn) bìa có chủ quá `CoverImageEncoder.maxPixelSize`.
    func scanCoverFolder(ownedBookIds: Set<String>, minimumAge: TimeInterval, includeOversized: Bool, now: Date = Date()) -> CoverFolderScan {
        let owners = ownerMap(for: ownedBookIds)
        var orphanNames: [String] = []
        var orphanBytes: Int64 = 0
        var oversized: [CoverFolderScan.OversizedCover] = []
        var oversizedBytes: Int64 = 0

        for name in coverFileNames() {
            let url = coversDirectory.appendingPathComponent(name)
            guard let info = fileInfo(url), info.isRegularFile else { continue }
            if let bookId = owners[name] {
                guard includeOversized, name.hasSuffix(".jpg"),
                      let side = CoverImageEncoder.longestPixelSide(of: url), side > CoverImageEncoder.maxPixelSize else { continue }
                oversized.append(CoverFolderScan.OversizedCover(fileName: name, bookId: bookId))
                oversizedBytes += info.bytes
            } else if now.timeIntervalSince(info.lastTouched) >= minimumAge {
                orphanNames.append(name)
                orphanBytes += info.bytes
            }
        }
        return CoverFolderScan(orphanFileNames: orphanNames, orphanBytes: orphanBytes, oversized: oversized, oversizedBytes: oversizedBytes)
    }

    /// Xoá các file mồ côi của `scan`, **kiểm lại** từng file theo `ownedBookIds` mới nhất và tuổi tối thiểu (giữa lúc đếm
    /// và lúc bấm Dọn có thể đã lưu truyện mới). Trả số file + số byte đã xoá.
    func removeOrphanCovers(in scan: CoverFolderScan, ownedBookIds: Set<String>, minimumAge: TimeInterval, now: Date = Date()) -> (count: Int, bytes: Int64) {
        let owners = ownerMap(for: ownedBookIds)
        var count = 0
        var bytes: Int64 = 0
        var failures = 0
        for name in scan.orphanFileNames where owners[name] == nil {
            let url = coversDirectory.appendingPathComponent(name)
            guard let info = fileInfo(url), info.isRegularFile,
                  now.timeIntervalSince(info.lastTouched) >= minimumAge else { continue }
            do {
                try validatePathSafety(for: url)
                try fileManager.removeItem(at: url)
                count += 1
                bytes += info.bytes
            } catch {
                failures += 1
            }
        }
        if failures > 0 {
            AppLogger.shared.log("❌ [CoverCleanup] Không xoá được \(failures) bìa mồ côi")
        }
        return (count, bytes)
    }

    /// Ghi lại bản thu nhỏ (`CoverImageEncoder`) cho các bìa quá cỡ của `scan`; chỉ ghi khi bản mới nhỏ hơn. Trả số file
    /// đã ghi lại + số byte tiết kiệm.
    func shrinkOversizedCovers(in scan: CoverFolderScan) -> (count: Int, savedBytes: Int64) {
        var count = 0
        var saved: Int64 = 0
        var failures = 0
        for cover in scan.oversized {
            let url = coversDirectory.appendingPathComponent(cover.fileName)
            guard let info = fileInfo(url), info.isRegularFile,
                  let encoded = CoverImageEncoder.encode(contentsOf: url) else { continue }
            let newBytes = Int64(encoded.jpeg.count)
            guard newBytes < info.bytes else { continue }
            do {
                try validatePathSafety(for: url)
                try encoded.jpeg.write(to: url, options: .atomic)
                invalidateCover(for: cover.bookId)
                count += 1
                saved += info.bytes - newBytes
            } catch {
                failures += 1
            }
        }
        if failures > 0 {
            AppLogger.shared.log("❌ [CoverCleanup] Không thu nhỏ được \(failures) bìa quá cỡ")
        }
        return (count, saved)
    }

    // MARK: - Nội bộ

    private struct CoverFileInfo {
        let isRegularFile: Bool
        let bytes: Int64
        /// Mốc ghi / đổi tên gần nhất: lấy lớn nhất của ngày sửa nội dung, ngày đổi thuộc tính (đổi tên, chuyển file) và
        /// ngày tạo — file chép từ bản sao lưu giữ ngày sửa cũ nhưng ngày đổi thuộc tính là lúc chuyển vào `covers/`.
        let lastTouched: Date
    }

    private static let fileKeys: Set<URLResourceKey> = [
        .isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey,
        .contentModificationDateKey, .attributeModificationDateKey, .creationDateKey
    ]

    /// Tên file trong `covers/`, bỏ file ẩn (tên bắt đầu bằng ".").
    private func coverFileNames() -> [String] {
        let names = (try? fileManager.contentsOfDirectory(atPath: coversDirectory.path)) ?? []
        return names.filter { !$0.hasPrefix(".") }
    }

    private func fileInfo(_ url: URL) -> CoverFileInfo? {
        guard let values = try? url.resourceValues(forKeys: Self.fileKeys) else { return nil }
        let dates = [values.contentModificationDate, values.attributeModificationDate, values.creationDate].compactMap { $0 }
        return CoverFileInfo(
            isRegularFile: values.isRegularFile == true,
            bytes: Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0),
            lastTouched: dates.max() ?? .distantFuture
        )
    }

    /// Tên file → `bookId` cho mọi tên một truyện có thể đang dùng (mới + kiểu cũ).
    private func ownerMap(for bookIds: Set<String>) -> [String: String] {
        var owners: [String: String] = [:]
        owners.reserveCapacity(bookIds.count * 2)
        for bookId in bookIds {
            owners[getNewFileName(for: bookId)] = bookId
            owners[getLegacyFileName(for: bookId)] = bookId
        }
        return owners
    }
}
