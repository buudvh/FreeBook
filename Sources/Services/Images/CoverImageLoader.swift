import Foundation
import UIKit
import ImageIO

/// Tải ảnh bìa / ảnh mục (kết quả tìm kiếm, gợi ý, danh sách Khám phá) kèm `Referer` + UA iPhone Safari —
/// `AsyncImage` không gửi được header nên CDN chặn hotlink trả 403.
///
/// Thứ tự tra: RAM (`NSCache`, theo URL + cỡ downsample) → cache đĩa `Caches/cover_images/<sha256(url)>` → mạng.
/// Chỉ cache byte của phản hồi 2xx mà ImageIO nhận ra là ảnh (trang lỗi HTML trả 200 không bị giữ lại).
///
/// Actor chỉ giữ bộ đếm request mạng (tối đa `maxConcurrentRequests`) và sổ log lỗi; giải mã ImageIO, I/O đĩa và chờ
/// mạng chạy trong các hàm `nonisolated`. Caller bị huỷ (ô cuộn khỏi màn) thì lượt đang chờ slot cũng bị huỷ.
/// `Caches` là chủ ý: tải lại được, hệ điều hành được xoá khi thiếu chỗ; vẫn tự dọn về ~75% khi vượt `diskByteLimit`.
public actor CoverImageLoader {
    public static let shared = CoverImageLoader()

    static let maxConcurrentRequests = 4
    static let requestTimeout: TimeInterval = 20
    static let memoryCostLimit = 48 * 1024 * 1024
    static let diskByteLimit: Int64 = 150 * 1024 * 1024
    /// Chặn cứng cạnh dài sau downsample — caller truyền cỡ lạ (0, cực lớn) vẫn không giải mã full-res.
    static let maxPixelSizeLimit = 4096

    /// `NSCache` bọc trong lớp `Sendable` để đọc được từ các hàm `nonisolated`.
    private final class MemoryCache: @unchecked Sendable {
        private let cache = NSCache<NSString, UIImage>()

        init(costLimit: Int) {
            cache.totalCostLimit = costLimit
        }

        func image(forKey key: String) -> UIImage? {
            cache.object(forKey: key as NSString)
        }

        func insert(_ image: UIImage, forKey key: String) {
            let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 1
            cache.setObject(image, forKey: key as NSString, cost: cost)
        }
    }

    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }

    private let memoryCache = MemoryCache(costLimit: CoverImageLoader.memoryCostLimit)
    private let diskDirectory: URL
    private var activeRequests = 0
    private var waiters: [Waiter] = []
    /// `host|mã lỗi` đã log trong phiên — danh sách dài cùng một CDN chặn không làm ngập `app_logs.txt`.
    private var loggedFailures: Set<String> = []

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let directory = caches.appendingPathComponent("cover_images", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        diskDirectory = directory
        Task.detached(priority: .utility) {
            Self.trimDiskCache(at: directory)
        }
    }

    // MARK: - API

    /// Ảnh đã downsample bằng ImageIO, cạnh dài ≤ `maxPixelSize` (px). `nil` khi URL không hợp lệ/tương đối,
    /// tải lỗi, không phải ảnh hoặc caller bị huỷ. `referer` nhận host, `source` hay URL — tự chuẩn hoá về origin + "/".
    public nonisolated func image(url: String, referer: String?, maxPixelSize: Int) async -> UIImage? {
        let pixelSize = Self.clampedPixelSize(maxPixelSize)
        let key = Self.memoryKey(url: url, pixelSize: pixelSize)
        if let cached = memoryCache.image(forKey: key) {
            return cached
        }
        guard let bytes = await self.data(url: url, referer: referer), !Task.isCancelled else { return nil }
        guard let image = Self.downsample(bytes, maxPixelSize: pixelSize) else { return nil }
        memoryCache.insert(image, forKey: key)
        return image
    }

    /// Byte gốc của ảnh (cache đĩa → mạng). URI `data:` được giải trực tiếp, không cache.
    public nonisolated func data(url: String, referer: String?) async -> Data? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.lowercased().hasPrefix("data:") {
            guard let decoded = Self.decodeDataURI(trimmed), Self.isImageData(decoded) else { return nil }
            return decoded
        }
        guard let requestURL = URL(string: trimmed),
              let scheme = requestURL.scheme?.lowercased(), scheme == "http" || scheme == "https",
              requestURL.host != nil else { return nil }

        let fileURL = diskDirectory.appendingPathComponent(trimmed.sha256())
        if let cached = try? Data(contentsOf: fileURL), !cached.isEmpty {
            // "Cũ nhất" tính theo lần dùng gần nhất: chạm mtime khi trúng cache.
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: fileURL.path)
            return cached
        }

        // `coverDecodeJs` của nguồn Legado (spec §8.7): chỉ URL bìa runtime Legado đã đăng ký — byte tải về là ảnh mã hoá,
        // giải mã xong mới kiểm "có phải ảnh" và mới cache. Tiện ích JS: một lần tra từ điển, không đổi gì.
        let decodePlan = LegadoCoverDecoder.shared.plan(url: trimmed, packageId: nil)
        guard var downloaded = await fetchRemote(requestURL, referer: referer, requiresImage: decodePlan == nil) else {
            return nil
        }
        if let decodePlan {
            downloaded = await LegadoCoverDecoder.shared.decode(downloaded, plan: decodePlan)
            guard !Task.isCancelled, Self.isImageData(downloaded) else { return nil }
        }
        do {
            try downloaded.write(to: fileURL, options: .atomic)
        } catch {
            AppLogger.shared.log("❌ [CoverImageLoader] Lỗi ghi cache ảnh bìa: \(error.localizedDescription)")
        }
        return downloaded
    }

    /// Chỉ tra RAM, không I/O — View gọi đồng bộ được để ảnh đã có không nháy placeholder khi cuộn lại.
    public nonisolated func cachedImage(url: String, maxPixelSize: Int) -> UIImage? {
        memoryCache.image(forKey: Self.memoryKey(url: url, pixelSize: Self.clampedPixelSize(maxPixelSize)))
    }

    // MARK: - Mạng

    /// `requiresImage == false` (bìa cần giải mã `coverDecodeJs`): bỏ bước kiểm "có phải ảnh" — caller kiểm sau khi giải mã.
    private nonisolated func fetchRemote(_ url: URL, referer: String?, requiresImage: Bool = true) async -> Data? {
        let request = CoverRequestResolver.request(for: url, referer: referer, timeout: Self.requestTimeout)
        let hostLabel = url.host ?? "?"
        do {
            try await acquireRequestSlot()
        } catch {
            return nil
        }
        let result: (Data, URLResponse)
        do {
            // Ô cuộn khỏi màn trong lúc chờ lượt thì không tải nữa.
            try Task.checkCancellation()
            result = try await URLSession.shared.data(for: request)
        } catch {
            await releaseRequestSlot()
            if !(error is CancellationError), (error as? URLError)?.code != .cancelled {
                await logFailureOnce(host: hostLabel, reason: error.localizedDescription)
            }
            return nil
        }
        await releaseRequestSlot()

        let (data, response) = result
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            await logFailureOnce(host: hostLabel, reason: "HTTP \(http.statusCode)")
            return nil
        }
        guard !requiresImage || Self.isImageData(data) else {
            await logFailureOnce(host: hostLabel, reason: "phản hồi không phải ảnh")
            return nil
        }
        return data
    }

    /// Chỉ log host + lý do (URL ảnh có thể chứa token), mỗi cặp một lần trong phiên chạy app.
    private func logFailureOnce(host: String, reason: String) {
        guard loggedFailures.insert("\(host)|\(reason)").inserted else { return }
        AppLogger.shared.log("❌ [CoverImageLoader] Tải ảnh bìa thất bại (\(host)): \(reason)")
    }

    // MARK: - Giới hạn request đồng thời

    private func acquireRequestSlot() async throws {
        try Task.checkCancellation()
        if activeRequests < Self.maxConcurrentRequests {
            activeRequests += 1
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                waiters.append(Waiter(id: id, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancelWaiter(id: id) }
        }
    }

    /// Trao slot thẳng cho người chờ đầu hàng (giữ nguyên `activeRequests`) hoặc trả slot.
    private func releaseRequestSlot() {
        if waiters.isEmpty {
            activeRequests = max(0, activeRequests - 1)
        } else {
            waiters.removeFirst().continuation.resume()
        }
    }

    private func cancelWaiter(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    // MARK: - Giải mã

    private static func clampedPixelSize(_ value: Int) -> Int {
        min(max(value, 1), maxPixelSizeLimit)
    }

    /// Khoá RAM: URI `data:` có thể dài cả MB base64 nên băm cho gọn.
    private static func memoryKey(url: String, pixelSize: Int) -> String {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let identity = trimmed.count > 512 ? trimmed.sha256() : trimmed
        return "\(identity)|\(pixelSize)"
    }

    /// Downsample bằng ImageIO (không bao giờ giải mã ảnh gốc full-res), cạnh dài ≤ `maxPixelSize`.
    static func downsample(_ data: Data, maxPixelSize: Int) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
              CGImageSourceGetCount(source) > 0 else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: clampedPixelSize(maxPixelSize)
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }

    /// ImageIO nhận ra định dạng (JPEG/PNG/GIF/WebP/HEIC/AVIF…) — chặn trang HTML/JSON lỗi trả về mã 200.
    static func isImageData(_ data: Data) -> Bool {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetType(source) != nil else { return false }
        return CGImageSourceGetCount(source) > 0
    }

    /// `data:[mime][;base64],payload` → byte.
    private static func decodeDataURI(_ uri: String) -> Data? {
        guard let comma = uri.firstIndex(of: ",") else { return nil }
        let header = uri[uri.startIndex..<comma].lowercased()
        let body = String(uri[uri.index(after: comma)...])
        if header.contains(";base64") {
            return Data(base64Encoded: body, options: .ignoreUnknownCharacters)
        }
        return body.removingPercentEncoding.map { Data($0.utf8) }
    }

    // MARK: - Dọn cache đĩa

    /// Vượt `diskByteLimit` thì xoá file dùng lâu nhất (theo mtime) về ~75% giới hạn. Chạy một lần lúc khởi tạo.
    private static func trimDiskCache(at directory: URL) {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return }

        var entries: [(url: URL, date: Date, size: Int64)] = []
        var total: Int64 = 0
        for file in files {
            guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            let size = Int64(values.fileSize ?? 0)
            total += size
            entries.append((url: file, date: values.contentModificationDate ?? .distantPast, size: size))
        }
        guard total > diskByteLimit else { return }

        let target = diskByteLimit * 3 / 4
        var removedCount = 0
        for entry in entries.sorted(by: { $0.date < $1.date }) where total > target {
            do {
                try FileManager.default.removeItem(at: entry.url)
                total -= entry.size
                removedCount += 1
            } catch {
                AppLogger.shared.log("❌ [CoverImageLoader] Lỗi dọn cache ảnh bìa: \(error.localizedDescription)")
                break
            }
        }
        AppLogger.shared.log("🧹 [CoverImageLoader] Đã dọn \(removedCount) ảnh bìa cũ trong cache")
    }
}
