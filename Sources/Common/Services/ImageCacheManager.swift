import Foundation
import UIKit
import CryptoKit

public final class ImageCacheManager {
    public static let shared = ImageCacheManager()

    private let fileManager = FileManager.default

    private var coversDirectory: URL {
        let paths = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupportDirectory = paths[0]
        let directoryURL = appSupportDirectory.appendingPathComponent("covers", isDirectory: true)

        if !fileManager.fileExists(atPath: directoryURL.path) {
            try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
        }

        return directoryURL
    }

    private func sha256Hex(_ string: String) -> String {
        let inputData = Data(string.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.map { String(format: "%02x", $0) }.joined()
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
        let canonicalRoot = coversDirectory.standardized.resolvingSymlinksInPath()
        let canonicalTarget = targetURL.standardized.resolvingSymlinksInPath()
        guard canonicalTarget.pathComponents.starts(with: canonicalRoot.pathComponents) else {
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

    public func localCoverURL(for bookId: String) -> URL {
        migrateLegacyFileIfNecessary(for: bookId)
        return coversDirectory.appendingPathComponent(getNewFileName(for: bookId))
    }

    public func loadLocalCover(for bookId: String) -> UIImage? {
        migrateLegacyFileIfNecessary(for: bookId)
        let destinationURL = coversDirectory.appendingPathComponent(getNewFileName(for: bookId))
        guard (try? validatePathSafety(for: destinationURL)) != nil else { return nil }
        let path = destinationURL.path
        guard fileManager.fileExists(atPath: path) else { return nil }
        return UIImage(contentsOfFile: path)
    }

    public func deleteCover(for bookId: String) throws {
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

        let destinationURL = coversDirectory.appendingPathComponent(getNewFileName(for: bookId))
        do {
            try validatePathSafety(for: destinationURL)
            try jpegData.write(to: destinationURL, options: .atomic)
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

        URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data = data, error == nil,
                  let image = UIImage(data: data) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            // Nén ảnh JPEG ở mức chất lượng 80% để tiết kiệm tài nguyên bộ nhớ
            if let jpegData = image.jpegData(compressionQuality: 0.8) {
                do {
                    try jpegData.write(to: destinationURL)
                    AppLogger.shared.log("💾 Đã tải và lưu ảnh bìa offline thành công cho sách: \(bookId)")
                    DispatchQueue.main.async { completion(image) }
                } catch {
                    AppLogger.shared.log("❌ Lỗi ghi tệp ảnh bìa local: \(error.localizedDescription)")
                    DispatchQueue.main.async { completion(nil) }
                }
            } else {
                DispatchQueue.main.async { completion(nil) }
            }
        }.resume()
    }
}
