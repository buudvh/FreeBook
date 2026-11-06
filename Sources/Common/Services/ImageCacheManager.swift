import Foundation
import UIKit
import CryptoKit

public final class ImageCacheManager: @unchecked Sendable {
    public static let shared = ImageCacheManager()

    /// `internal` (không `private`) cho các phần `ImageCacheManager+…` ở file khác — vẫn chỉ owner này đụng `covers/`.
    let fileManager = FileManager.default

    /// Tính một lần lúc khởi tạo (trước đây mỗi lần truy cập lại gọi `urls(for:)` + `fileExists`).
    let coversDirectory: URL
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
    /// bookId → các completion đang chờ chung một lượt tải bìa **chỉ RAM** (`fetchTransientCoverData`).
    private var inFlightTransientFetches: [String: [(Data?) -> Void]] = [:]
    /// Byte bìa chỉ RAM vừa tải (trang Chi tiết của truyện chưa lưu): bìa lớn và nền mờ dùng chung, đổi cỡ khung không
    /// tải lại. Vài trang gần nhất, iOS tự nhả khi thiếu bộ nhớ.
    private let transientCoverData: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.countLimit = 8
        cache.totalCostLimit = 8 * 1024 * 1024
        return cache
    }()

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
    func sha256Hex(_ string: String) -> String {
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

    func getNewFileName(for bookId: String) -> String {
        return sha256Hex(bookId) + ".jpg"
    }

    func getLegacyFileName(for bookId: String) -> String {
        // Sanitize bookId to be a safe filename by replacing non-alphanumeric characters with underscores
        let safeName = bookId.replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "_", options: .regularExpression)
        return "\(safeName).jpg"
    }

    func validatePathSafety(for targetURL: URL) throws {
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
        guard let image = UIImage(contentsOfFile: path) else {
            // File có mà không đọc được: nếu bảng fd đã sát giới hạn thì chụp lại để chẩn đoán.
            FileDescriptorCensus.noteOpenFailure(context: "ImageCacheManager.loadLocalCover", error: nil)
            return nil
        }
        return image
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
    /// Ảnh được thu nhỏ về cạnh dài ≤ `maxDimension` **pixel** rồi nén JPEG (`CoverImageEncoder`) để không phình `covers/`.
    @discardableResult
    public func saveCover(data: Data, for bookId: String, maxDimension: CGFloat = 1024, quality: CGFloat = 0.85) -> UIImage? {
        guard let encoded = CoverImageEncoder.encode(data, maxPixelSize: Int(maxDimension), quality: quality) else { return nil }

        ensureCoversDirectory()
        let destinationURL = coversDirectory.appendingPathComponent(getNewFileName(for: bookId))
        do {
            try validatePathSafety(for: destinationURL)
            try encoded.jpeg.write(to: destinationURL, options: .atomic)
            invalidateCover(for: bookId)
            AppLogger.shared.log("💾 Đã lưu ảnh bìa do người dùng chọn cho sách: \(bookId)")
            return encoded.image
        } catch {
            AppLogger.shared.log("❌ Lỗi ghi ảnh bìa người dùng chọn: \(error.localizedDescription)")
            return nil
        }
    }

    /// Tải bìa rồi ghi `covers/<sha256(bookId)>.jpg`. `urlStr` phải là URL tuyệt đối (bìa tương đối đã ghép host ở
    /// caller — `CoverRequestResolver.displayURL`). `referer` (host, `source` hay URL; chuẩn hoá về origin + "/") gửi
    /// kèm UA iPhone Safari: CDN chặn hotlink trả 403 khi thiếu. `nil` ⇒ không gửi `Referer`.
    /// `packageId` (nguồn của sách): nguồn Legado có `coverDecodeJs` (spec §8.7) ⇒ giải mã byte trước khi dựng ảnh và
    /// lưu bản đã giải mã; tiện ích JS / `nil` ⇒ như cũ.
    public func downloadAndSaveCover(urlStr: String, bookId: String, referer: String? = nil, packageId: String? = nil, completion: @escaping (UIImage?) -> Void = { _ in }) {
        guard !urlStr.isEmpty, let url = URL(string: urlStr), url.scheme != nil else {
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

        fetchCoverBytes(url: url, urlStr: urlStr, referer: referer, packageId: packageId) { data in
            guard let data else {
                self.finishDownload(for: bookId, image: nil)
                return
            }
            self.storeDownloadedCover(data, bookId: bookId, destinationURL: destinationURL)
        }
    }

    /// Tải bìa **chỉ giữ trong RAM** (1.3.762) cho trang Chi tiết của truyện chưa lưu: `bookId` của nó ngẫu nhiên mỗi
    /// lần mở, ghi `covers/` là thành file mồ côi vĩnh viễn. Trả byte ảnh (đã giải mã `coverDecodeJs` nếu có) qua
    /// `completion` trên luồng nền; caller tự dựng thumbnail. Không ghi đĩa, không vào cache thumbnail dùng chung.
    /// Lượt trùng `bookId` (bìa lớn + nền mờ) gộp chung; byte vừa tải giữ ở `transientCoverData` cho lần đổi cỡ khung.
    public func fetchTransientCoverData(urlStr: String, bookId: String, referer: String? = nil, packageId: String? = nil, completion: @escaping (Data?) -> Void) {
        if let cached = transientCoverData.object(forKey: bookId as NSString) {
            completion(cached as Data)
            return
        }
        guard !urlStr.isEmpty, let url = URL(string: urlStr), url.scheme != nil else {
            completion(nil)
            return
        }

        stateLock.lock()
        if inFlightTransientFetches[bookId] != nil {
            inFlightTransientFetches[bookId]?.append(completion)
            stateLock.unlock()
            return
        }
        inFlightTransientFetches[bookId] = [completion]
        stateLock.unlock()

        fetchCoverBytes(url: url, urlStr: urlStr, referer: referer, packageId: packageId) { data in
            if let data {
                self.transientCoverData.setObject(data as NSData, forKey: bookId as NSString, cost: data.count)
            }
            self.stateLock.lock()
            let waiters = self.inFlightTransientFetches.removeValue(forKey: bookId) ?? []
            self.stateLock.unlock()
            for waiter in waiters {
                waiter(data)
            }
        }
    }

    /// Một lượt tải byte bìa (kèm `Referer` + UA) rồi giải mã `coverDecodeJs` của nguồn Legado nếu có. `nil` khi lỗi
    /// mạng / HTTP không 2xx. `completion` chạy trên luồng nền.
    private func fetchCoverBytes(url: URL, urlStr: String, referer: String?, packageId: String?, completion: @escaping @Sendable (Data?) -> Void) {
        let request = CoverRequestResolver.request(for: url, referer: referer, timeout: 30)
        URLSession.shared.dataTask(with: request) { data, response, error in
            let statusOK = (response as? HTTPURLResponse).map { (200...299).contains($0.statusCode) } ?? true
            guard let data = data, error == nil, statusOK else {
                completion(nil)
                return
            }
            // Tra ở queue của URLSession (lần đầu có thể đọc `source.json` của nguồn), không trên main.
            if let plan = LegadoCoverDecoder.shared.plan(url: urlStr, packageId: packageId) {
                Task.detached(priority: .utility) {
                    completion(await LegadoCoverDecoder.shared.decode(data, plan: plan))
                }
                return
            }
            completion(data)
        }.resume()
    }

    /// Thu nhỏ + nén byte đã tải (`CoverImageEncoder`, cạnh dài ≤ 1024 px), ghi `covers/<sha>.jpg` rồi trả cho mọi
    /// completion đang chờ. Trước 1.3.762 ghi nguyên cỡ — nguồn trả bìa lớn thì mỗi file vài trăm KB.
    private func storeDownloadedCover(_ data: Data, bookId: String, destinationURL: URL) {
        guard let encoded = CoverImageEncoder.encode(data) else {
            finishDownload(for: bookId, image: nil)
            return
        }
        do {
            try encoded.jpeg.write(to: destinationURL, options: .atomic)
            invalidateCover(for: bookId)
            AppLogger.shared.log("💾 Đã tải và lưu ảnh bìa offline thành công cho sách: \(bookId)")
            finishDownload(for: bookId, image: encoded.image)
        } catch {
            AppLogger.shared.log("❌ Lỗi ghi tệp ảnh bìa local: \(error.localizedDescription)")
            finishDownload(for: bookId, image: nil)
        }
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
