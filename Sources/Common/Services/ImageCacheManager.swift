import Foundation
import UIKit
import CryptoKit

public final class ImageCacheManager: @unchecked Sendable {
    public static let shared = ImageCacheManager()

    private let fileManager = FileManager.default

    /// Tính một lần lúc khởi tạo (trước đây mỗi lần truy cập lại gọi `urls(for:)` + `fileExists`).
    private let coversDirectory: URL
    /// Gốc đã chuẩn hoá của `coversDirectory` cho `validatePathSafety`, khỏi resolve symlink lại mỗi lần.
    private let canonicalRootComponents: [String]
    /// Thumbnail đã giải mã cho `BookCoverView`; xoá ở mọi chỗ ghi/xoá `covers/<sha>.jpg`.
    private let thumbnailCache = CoverThumbnailCache()

    /// Bảo vệ các bảng nhớ bên dưới: lớp này bị gọi từ main, worker tải truyện, backup và hàng đợi URLSession.
    private let stateLock = NSLock()
    /// bookId đã chạy migration legacy trong phiên chạy app này.
    private var migratedBookIds = Set<String>()
    /// bookId → URL bìa SHA-256 đã migrate + qua `validatePathSafety`.
    private var validatedCoverURLs: [String: URL] = [:]
    /// bookId → các completion đang chờ chung một lượt tải bìa.
    private var inFlightDownloads: [String: [(UIImage?) -> Void]] = [:]

    private static let hexDigits: [UInt8] = Array("0123456789abcdef".utf8)

    init() {
        let manager = FileManager.default
        let appSupportDirectory = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directoryURL = appSupportDirectory.appendingPathComponent("covers", isDirectory: true)
        if !manager.fileExists(atPath: directoryURL.path) {
            try? manager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
        }
        coversDirectory = directoryURL
        canonicalRootComponents = directoryURL.standardized.resolvingSymlinksInPath().pathComponents
    }

    /// Tạo lại thư mục `covers/` nếu bị mất, trước các lượt ghi.
    private func ensureCoversDirectory() {
        guard !fileManager.fileExists(atPath: coversDirectory.path) else { return }
        try? fileManager.createDirectory(at: coversDirectory, withIntermediateDirectories: true, attributes: nil)
    }

    /// Hex chữ thường qua bảng tra — cùng kết quả byte-for-byte với `String(format: "%02x")`.
    private func sha256Hex(_ string: String) -> String {
        let inputData = Data(string.utf8)
        let hashed = SHA256.hash(data: inputData)
        var hexBytes = [UInt8]()
        hexBytes.reserveCapacity(64)
        for byte in hashed {
            hexBytes.append(Self.hexDigits[Int(byte >> 4)])
            hexBytes.append(Self.hexDigits[Int(byte & 0x0F)])
        }
        return String(decoding: hexBytes, as: UTF8.self)
    }

    private func getNewFileName(for bookId: String) -> String {
        return sha256Hex(bookId) + ".jpg"
    }

    private func getLegacyFileName(for bookId: String) -> String {
        // Sanitize bookId to be a safe filename by replacing non-alphanumeric characters with underscores
        let safeName = bookId.replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "_", options: .regularExpression)
        return "\(safeName).jpg"
    }

    private func validatePathSafety(for targetURL: URL) throws {
        let canonicalTarget = targetURL.standardized.resolvingSymlinksInPath()
        guard canonicalTarget.pathComponents.starts(with: canonicalRootComponents) else {
            throw NSError(domain: "SecurityError", code: 403, userInfo: [NSLocalizedDescriptionKey: "Truy cập file ngoài thư mục Sandbox bị từ chối."])
        }
    }

    private func migrateLegacyFileIfNecessary(for bookId: String) {
        let newURL = coversDirectory.appendingPathComponent(getNewFileName(for: bookId))
        let oldURL = coversDirectory.appendingPathComponent(getLegacyFileName(for: bookId))

        guard (try? validatePathSafety(for: newURL)) != nil,
              (try? validatePathSafety(for: oldURL)) != nil else {
            return
        }

        let newExist = fileManager.fileExists(atPath: newURL.path)
        let oldExist = fileManager.fileExists(atPath: oldURL.path)

        if oldExist && !newExist {
            let safeName = bookId.replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "_", options: .regularExpression)
            if bookId == safeName {
                do {
                    try fileManager.moveItem(at: oldURL, to: newURL)
                    AppLogger.shared.log("🚚 Di chuyển thành công ảnh bìa cũ sang định dạng SHA-256 mới cho sách: \(bookId)")
                } catch {
                    AppLogger.shared.log("❌ Lỗi di chuyển ảnh bìa cũ sang mới: \(error.localizedDescription)")
                }
            } else {
                AppLogger.shared.log("⚠️ Bỏ qua di chuyển ảnh bìa legacy do có khả năng va chạm tên file: bookId=\(bookId), safeName=\(safeName)")
            }
        } else if oldExist && newExist {
            do {
                try fileManager.removeItem(at: oldURL)
            } catch {
                AppLogger.shared.log("❌ Lỗi dọn dẹp ảnh bìa cũ trùng lặp: \(error.localizedDescription)")
                let retryQueueKey = "failed_file_deletions_queue"
                var queue = UserDefaults.standard.stringArray(forKey: retryQueueKey) ?? []
                if !queue.contains(oldURL.path) {
                    queue.append(oldURL.path)
                    UserDefaults.standard.set(queue, forKey: retryQueueKey)
                }
            }
        }
    }

    /// Migration legacy chỉ chạy tối đa một lần cho mỗi bookId trong một phiên chạy app.
    private func migrateLegacyFileOnce(for bookId: String) {
        stateLock.lock()
        let isFirstRun = migratedBookIds.insert(bookId).inserted
        stateLock.unlock()
        guard isFirstRun else { return }
        migrateLegacyFileIfNecessary(for: bookId)
    }

    /// URL bìa SHA-256 đã migrate + kiểm path; kết quả hợp lệ được nhớ suốt phiên chạy app
    /// (giống `BookBinManager.resolvedBinURLs`), nên SHA-256/regex/lstat không lặp lại mỗi lần hiện bìa.
    private func validatedCoverURL(for bookId: String) -> URL? {
        stateLock.lock()
        let cached = validatedCoverURLs[bookId]
        stateLock.unlock()
        if let cached { return cached }

        migrateLegacyFileOnce(for: bookId)
        let url = coversDirectory.appendingPathComponent(getNewFileName(for: bookId))
        guard (try? validatePathSafety(for: url)) != nil else { return nil }
        stateLock.lock()
        validatedCoverURLs[bookId] = url
        stateLock.unlock()
        return url
    }

    public func localCoverURL(for bookId: String) -> URL {
        ensureCoversDirectory()
        return validatedCoverURL(for: bookId)
            ?? coversDirectory.appendingPathComponent(getNewFileName(for: bookId))
    }

    public func loadLocalCover(for bookId: String) -> UIImage? {
        guard let destinationURL = validatedCoverURL(for: bookId) else { return nil }
        let path = destinationURL.path
        guard fileManager.fileExists(atPath: path) else { return nil }
        return UIImage(contentsOfFile: path)
    }

    // MARK: - Thumbnail cho BookCoverView

    /// Chỉ tra cache RAM, không đụng đĩa — gọi đồng bộ trên main được.
    public func cachedCoverThumbnail(for bookId: String, pixelSize: CGSize) -> UIImage? {
        thumbnailCache.image(for: bookId, pixelSize: pixelSize)
    }

    /// Đọc bìa local, downsample về `pixelSize` (aspect-fill), giải mã sẵn rồi cất vào cache RAM.
    /// Có I/O và giải mã: chỉ gọi ở luồng nền. Trả `nil` khi chưa có file bìa.
    public func loadCoverThumbnail(for bookId: String, pixelSize: CGSize, scale: CGFloat) -> UIImage? {
        if let cached = thumbnailCache.image(for: bookId, pixelSize: pixelSize) { return cached }
        let generation = thumbnailCache.currentGeneration(for: bookId)
        guard let destinationURL = validatedCoverURL(for: bookId) else { return nil }
        let path = destinationURL.path
        guard fileManager.fileExists(atPath: path) else { return nil }
        guard let image = CoverThumbnailCache.makeThumbnail(contentsOf: destinationURL, pixelSize: pixelSize, scale: scale)
                ?? UIImage(contentsOfFile: path)?.preparingForDisplay() else {
            return nil
        }
        thumbnailCache.insert(image, for: bookId, pixelSize: pixelSize, generation: generation)
        return image
    }

    /// Bỏ thumbnail RAM của một sách — gọi sau MỌI lượt ghi/xoá `covers/<sha>.jpg`.
    public func invalidateCover(for bookId: String) {
        thumbnailCache.invalidate(bookId: bookId)
    }

    public func deleteCover(for bookId: String) throws {
        defer { invalidateCover(for: bookId) }
        let newURL = coversDirectory.appendingPathComponent(getNewFileName(for: bookId))
        let oldURL = coversDirectory.appendingPathComponent(getLegacyFileName(for: bookId))

        try validatePathSafety(for: newURL)
        try validatePathSafety(for: oldURL)

        var deletionError: Error? = nil

        if fileManager.fileExists(atPath: newURL.path) {
            do {
                try fileManager.removeItem(at: newURL)
                AppLogger.shared.log("🗑️ Đã xóa thành công ảnh bìa mới: \(newURL.path)")
            } catch {
                deletionError = error
                AppLogger.shared.log("❌ Lỗi xóa ảnh bìa mới: \(error.localizedDescription)")
            }
        }

        if fileManager.fileExists(atPath: oldURL.path) {
            do {
                try fileManager.removeItem(at: oldURL)
                AppLogger.shared.log("🗑️ Đã xóa thành công ảnh bìa cũ: \(oldURL.path)")
            } catch {
                if deletionError == nil {
                    deletionError = error
                }
                AppLogger.shared.log("❌ Lỗi xóa ảnh bìa cũ: \(error.localizedDescription)")
            }
        }

        if let error = deletionError {
            throw error
        }
    }

    /// Ghi ảnh bìa do người dùng chọn từ máy vào đúng chỗ mà `loadLocalCover` đọc.
    /// Ảnh được thu nhỏ về cạnh dài ≤ `maxDimension` px rồi nén JPEG để không phình thư mục `covers/`.
    @discardableResult
    public func saveCover(data: Data, for bookId: String, maxDimension: CGFloat = 1024, quality: CGFloat = 0.85) -> UIImage? {
        guard let image = UIImage(data: data) else { return nil }
        let resized = downscaled(image, maxDimension: maxDimension)
        guard let jpegData = resized.jpegData(compressionQuality: quality) else { return nil }

        ensureCoversDirectory()
        let destinationURL = coversDirectory.appendingPathComponent(getNewFileName(for: bookId))
        do {
            try validatePathSafety(for: destinationURL)
            try jpegData.write(to: destinationURL, options: .atomic)
            invalidateCover(for: bookId)
            AppLogger.shared.log("💾 Đã lưu ảnh bìa do người dùng chọn cho sách: \(bookId)")
            return resized
        } catch {
            AppLogger.shared.log("❌ Lỗi ghi ảnh bìa người dùng chọn: \(error.localizedDescription)")
            return nil
        }
    }

    private func downscaled(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longestSide = max(image.size.width, image.size.height)
        guard longestSide > maxDimension, longestSide > 0 else { return image }
        let scale = maxDimension / longestSide
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    public func downloadAndSaveCover(urlStr: String, bookId: String, completion: @escaping (UIImage?) -> Void = { _ in }) {
        guard !urlStr.isEmpty, let url = URL(string: urlStr) else {
            completion(nil)
            return
        }

        let destinationURL = localCoverURL(for: bookId)

        // Nếu đã tồn tại file local thì nạp trực tiếp và trả về, không tải lại
        if fileManager.fileExists(atPath: destinationURL.path) {
            if let image = UIImage(contentsOfFile: destinationURL.path) {
                completion(image)
                return
            }
        }

        // Gộp lượt tải trùng: bookId đã có lượt đang bay thì chỉ xếp completion chờ chung kết quả.
        stateLock.lock()
        if inFlightDownloads[bookId] != nil {
            inFlightDownloads[bookId]?.append(completion)
            stateLock.unlock()
            return
        }
        inFlightDownloads[bookId] = [completion]
        stateLock.unlock()

        URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data = data, error == nil,
                  let image = UIImage(data: data) else {
                self.finishDownload(for: bookId, image: nil)
                return
            }

            // Nén ảnh JPEG ở mức chất lượng 80% để tiết kiệm tài nguyên bộ nhớ
            if let jpegData = image.jpegData(compressionQuality: 0.8) {
                do {
                    try jpegData.write(to: destinationURL, options: .atomic)
                    self.invalidateCover(for: bookId)
                    AppLogger.shared.log("💾 Đã tải và lưu ảnh bìa offline thành công cho sách: \(bookId)")
                    self.finishDownload(for: bookId, image: image)
                } catch {
                    AppLogger.shared.log("❌ Lỗi ghi tệp ảnh bìa local: \(error.localizedDescription)")
                    self.finishDownload(for: bookId, image: nil)
                }
            } else {
                self.finishDownload(for: bookId, image: nil)
            }
        }.resume()
    }

    /// Trả kết quả cho mọi completion đang chờ lượt tải của bookId, trên main như trước.
    private func finishDownload(for bookId: String, image: UIImage?) {
        stateLock.lock()
        let waiters = inFlightDownloads.removeValue(forKey: bookId) ?? []
        stateLock.unlock()
        DispatchQueue.main.async {
            for waiter in waiters {
                waiter(image)
            }
        }
    }
}
