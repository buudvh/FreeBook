import Foundation
import UIKit
import ImageIO

/// Nơi duy nhất tải ảnh comic — cho màn đọc (`image(for:maxPixelWidth:)`) và tải offline (`data(for:scriptRunner:)`).
///
/// Thứ tự tra: RAM (`NSCache` ~120 MB, theo kích thước downsample) → cache đĩa (`ComicImageDiskCache`) → nguồn:
/// script ảnh khi có `script`, ngược lại `link` rồi lần lượt từng `fallback` (`http(s)`, `file://`, `data:`).
///
/// Actor chỉ giữ bộ đếm request mạng (tối đa `maxConcurrentRequests`). Giải mã ImageIO, I/O đĩa và chờ mạng chạy
/// trong các hàm `nonisolated` — không xếp hàng sau nhau trên actor. Ảnh luôn được downsample: bề ngang
/// ≤ `maxPixelWidth`, tổng ≤ `maxDecodedPixels` (chống OOM với trang webtoon rất dài), cạnh dài ≤ `maxTextureSide`.
///
/// Script ảnh: màn đọc dùng `scriptRunner` riêng của loader; tải offline truyền runner của chính tác vụ, để
/// `releaseScriptRunners()` bên này không nhả executor bên kia và ảnh màn đọc không xếp hàng sau ảnh đang tải.
public actor ComicImageLoader {
    public static let shared = ComicImageLoader()

    static let maxConcurrentRequests = 3
    static let maxDecodedPixels: Double = 16_000_000
    /// Cạnh dài tối đa sau downsample — giới hạn texture GPU, quá cỡ thì `UIImageView` không vẽ được.
    static let maxTextureSide: Double = 16_384
    static let memoryCostLimit = 120 * 1024 * 1024
    static let requestTimeout: TimeInterval = 30

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

        func removeAll() {
            cache.removeAllObjects()
        }
    }

    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }

    private let memoryCache = MemoryCache(costLimit: ComicImageLoader.memoryCostLimit)
    private let diskCache = ComicImageDiskCache()
    private let scriptRunner = ComicImageScriptRunner()
    private var activeRequests = 0
    private var waiters: [Waiter] = []

    // MARK: - API

    /// Ảnh đã downsample bằng ImageIO: bề ngang ≤ `maxPixelWidth` (≤ 0 = không giới hạn ngang), tổng ≤ ~16 MP.
    /// Thứ tự: `NSCache` → cache đĩa → mạng (`link` rồi `fallbacks`) hoặc script. Hỗ trợ `file://` và `data:`.
    public nonisolated func image(for request: ComicImageRequest, maxPixelWidth: Int) async throws -> UIImage {
        // Khoá `data:` có thể dài cả MB base64: băm cho gọn trước khi làm khoá `NSCache`.
        let identity = request.cacheKey.count > 512 ? request.cacheKey.sha256() : request.cacheKey
        let memoryKey = "\(identity)|w\(max(maxPixelWidth, 0))"
        if let cached = memoryCache.image(forKey: memoryKey) {
            return cached
        }
        let data = try await loadData(for: request, storeInDiskCache: true, scriptRunner: scriptRunner)
        try Task.checkCancellation()
        guard let image = Self.downsample(data, maxPixelWidth: maxPixelWidth) else {
            // Byte hỏng đã vào cache đĩa thì "Thử lại" sẽ trúng lại đúng nó: bỏ mục đó để lần sau tải lại từ nguồn.
            if !request.isLocalOnly {
                diskCache.remove(forKey: request.cacheKey)
            }
            AppLogger.shared.log("❌ [ComicImageLoader] Không giải mã được ảnh (\(data.count) byte)")
            throw Self.error("Không giải mã được ảnh")
        }
        memoryCache.insert(image, forKey: memoryKey)
        return image
    }

    /// Byte gốc cho tải offline, cùng chuỗi thử `link` → `fallbacks` / script. Đọc cache đĩa nếu màn đọc đã tải
    /// ảnh này, nhưng **không** ghi vào đó (bản offline đã nằm ở `ComicOfflineStore`, ghi thêm chỉ đẩy ảnh khác ra).
    public nonisolated func data(for request: ComicImageRequest) async throws -> Data {
        try await loadData(for: request, storeInDiskCache: false, scriptRunner: scriptRunner)
    }

    /// Như `data(for:)` nhưng script ảnh chạy trên `runner` của caller (tác vụ tải offline tự tạo và tự
    /// `releaseAll()` khi xong/huỷ) — không dùng chung executor/lượt chạy với màn đọc.
    nonisolated func data(for request: ComicImageRequest, scriptRunner runner: ComicImageScriptRunner) async throws -> Data {
        try await loadData(for: request, storeInDiskCache: false, scriptRunner: runner)
    }

    /// Giải phóng các `JSExecutor` script ảnh của **màn đọc** (gọi khi rời chương / đóng màn đọc).
    public func releaseScriptRunners() {
        let runner = scriptRunner
        Task {
            await runner.releaseAll()
        }
    }

    public func clearMemoryCache() {
        memoryCache.removeAll()
    }

    // MARK: - Nguồn byte

    private nonisolated func loadData(
        for request: ComicImageRequest,
        storeInDiskCache: Bool,
        scriptRunner: ComicImageScriptRunner
    ) async throws -> Data {
        let usesDiskCache = !request.isLocalOnly
        let diskKey = request.cacheKey
        if usesDiskCache, let cached = diskCache.data(forKey: diskKey) {
            return cached
        }

        if let script = request.scriptName {
            do {
                let data = try await scriptRunner.run(
                    script: script,
                    link: request.source.link,
                    localPath: request.extensionLocalPath,
                    downloadUrl: request.downloadUrl,
                    configJson: request.configJson
                )
                // Base64 giải được nhưng không phải ảnh thì không được vào cache đĩa / bản offline.
                guard Self.isImageData(data) else {
                    throw Self.error("Script ảnh không trả về ảnh hợp lệ")
                }
                if storeInDiskCache {
                    diskCache.store(data, forKey: diskKey)
                }
                return data
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                AppLogger.shared.log("❌ [ComicImageLoader] Script ảnh \(script) lỗi: \(error.localizedDescription)")
                throw error
            }
        }

        let candidates = request.candidates
        guard !candidates.isEmpty else {
            AppLogger.shared.log("❌ [ComicImageLoader] Phần tử ảnh không có link hợp lệ")
            throw Self.error("Ảnh không có đường dẫn hợp lệ")
        }

        var lastError: Error?
        for candidate in candidates {
            try Task.checkCancellation()
            do {
                let data = try await fetch(candidate, headers: request.httpHeaders)
                if storeInDiskCache && candidate.isRemote {
                    diskCache.store(data, forKey: diskKey)
                }
                return data
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
        }

        let hosts = Set(candidates.map(ComicImageRequest.logLabel(for:))).sorted().joined(separator: ",")
        AppLogger.shared.log("❌ [ComicImageLoader] Tải ảnh thất bại sau \(candidates.count) ứng viên (\(hosts)): \(lastError?.localizedDescription ?? "?")")
        throw lastError ?? Self.error("Không tải được ảnh")
    }

    private nonisolated func fetch(_ candidate: ComicImageRequest.Candidate, headers: [String: String]) async throws -> Data {
        switch candidate {
        case .inline(let uri):
            guard let data = ComicImageScriptRunner.decodeImagePayload(uri), Self.isImageData(data) else {
                throw Self.error("URI data: không chứa ảnh hợp lệ")
            }
            return data
        case .file(let url):
            let data = try Data(contentsOf: url)
            guard Self.isImageData(data) else { throw Self.error("File ảnh offline hỏng") }
            return data
        case .remote(let url):
            return try await fetchRemote(url, headers: headers)
        }
    }

    private nonisolated func fetchRemote(_ url: URL, headers: [String: String]) async throws -> Data {
        var urlRequest = URLRequest(url: url, timeoutInterval: Self.requestTimeout)
        for (key, value) in headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        try await acquireRequestSlot()
        let result: (Data, URLResponse)
        do {
            // Ô ảnh cuộn khỏi màn trong lúc chờ lượt thì không tải nữa.
            try Task.checkCancellation()
            result = try await URLSession.shared.data(for: urlRequest)
        } catch {
            await releaseRequestSlot()
            throw error
        }
        await releaseRequestSlot()

        let (data, response) = result
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw Self.error("HTTP \(http.statusCode)")
        }
        // Trang lỗi HTML trả 200 (chặn hotlink, Cloudflare) không được coi là ảnh để còn thử fallback.
        guard Self.isImageData(data) else {
            throw Self.error("Phản hồi không phải ảnh (\(data.count) byte)")
        }
        return data
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

    /// Downsample bằng ImageIO, không bao giờ giải mã ảnh gốc full-res. `kCGImageSourceThumbnailMaxPixelSize`
    /// chặn **cạnh dài**, nên phải tự quy đổi từ giới hạn bề ngang + tổng điểm ảnh sang cạnh dài.
    static func downsample(_ data: Data, maxPixelWidth: Int) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
              CGImageSourceGetCount(source) > 0 else { return nil }

        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let rawWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
           let rawHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
           rawWidth > 0, rawHeight > 0 {
            // EXIF orientation 5...8 xoay 90°: bề ngang hiển thị là chiều cao gốc.
            let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
            let width = orientation >= 5 ? rawHeight : rawWidth
            let height = orientation >= 5 ? rawWidth : rawHeight
            var scale = min(1, (maxDecodedPixels / (width * height)).squareRoot())
            if maxPixelWidth > 0 {
                scale = min(scale, Double(maxPixelWidth) / width)
            }
            scale = min(scale, maxTextureSide / max(width, height))
            options[kCGImageSourceThumbnailMaxPixelSize] = max(1, Int((max(width, height) * scale).rounded(.up)))
        } else {
            // Không đọc được kích thước: vẫn chặn cứng cạnh dài để không giải mã full-res.
            options[kCGImageSourceThumbnailMaxPixelSize] = 4096
        }

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }

    /// ImageIO nhận ra định dạng (JPEG/PNG/GIF/WebP/HEIC/AVIF…) — chặn trang HTML/JSON lỗi trả về mã 200.
    static func isImageData(_ data: Data) -> Bool {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetType(source) != nil else { return false }
        return CGImageSourceGetCount(source) > 0
    }

    private static func error(_ message: String) -> NSError {
        NSError(domain: "ComicImageLoader", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
