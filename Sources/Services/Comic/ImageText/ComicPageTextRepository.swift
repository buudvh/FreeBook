import CoreGraphics
import Foundation

/// Kết quả nhận chữ của từng ảnh truyện tranh (dịch ảnh, 1.3.826) — chủ duy nhất của `Caches/comic_ocr/`.
///
/// Thứ tự tra: RAM (`NSCache`) → đĩa (JSON `ComicTextPage`; hỏng hay sai `schemaVersion` ⇒ coi như chưa có) → nhận chữ
/// (`ComicTextRecognizer`, mỗi lúc một ảnh) rồi gom khối (`ComicTextBlockGrouper`). Ảnh không có chữ cũng được lưu (mảng
/// rỗng) để khỏi nhận chữ lại.
///
/// - Khoá = `ComicImageRequest.cacheKey`, như cache ảnh: cache đĩa tự băm sha256 làm tên file; khoá RAM băm khi dài (khoá
///   `data:` có thể cả MB). Ảnh đọc online và bản tải offline có khoá khác nhau ⇒ nhận chữ riêng — chấp nhận.
/// - Thư mục nằm ở `Caches` (hệ điều hành được xoá, Backup không gói); nút "Xoá" cache ảnh truyện tranh của màn Dung lượng
///   và lịch tự dọn xoá luôn thư mục này qua `StorageUsageCleaner` → `clearAll()`.
/// - Hai hàng cùng một ảnh hỏi chồng nhau thì nhận chữ hai lần — hiếm, chấp nhận, không gộp lượt.
/// - Chỉ giữ chữ **gốc**; bản dịch dựng lại mỗi lần hiện (`ComicPageTextTranslator`).
final class ComicPageTextRepository: @unchecked Sendable {
    static let shared = ComicPageTextRepository()

    static let directoryName = "comic_ocr"
    static let byteLimit: Int64 = 30 * 1024 * 1024

    /// `NSCache` chỉ giữ object ⇒ bọc mảng khối.
    private final class Entry {
        let blocks: [ComicTextBlock]

        init(_ blocks: [ComicTextBlock]) {
            self.blocks = blocks
        }
    }

    private let memory = NSCache<NSString, Entry>()
    private let disk = ComicImageDiskCache(
        directoryName: ComicPageTextRepository.directoryName,
        byteLimit: ComicPageTextRepository.byteLimit
    )

    private init() {
        memory.countLimit = 300
    }

    /// Khối chữ (chữ gốc) của ảnh `request`, nhận trên `image` — đúng ảnh màn đọc đang vẽ. Ném `CancellationError` khi hàng
    /// rời màn; lỗi khác đã được log `❌`.
    func blocks(for request: ComicImageRequest, image: CGImage) async throws -> [ComicTextBlock] {
        let key = request.cacheKey
        let memoryKey = (key.count > 512 ? key.sha256() : key) as NSString
        if let cached = memory.object(forKey: memoryKey) {
            return cached.blocks
        }
        if let stored = Self.decode(disk.data(forKey: key)) {
            memory.setObject(Entry(stored), forKey: memoryKey)
            return stored
        }

        let started = Date()
        do {
            let lines = try await ComicTextRecognizer.shared.recognizeLines(in: image)
            try Task.checkCancellation()
            let blocks = ComicTextBlockGrouper.blocks(from: lines, image: image)
            if let data = try? JSONEncoder().encode(ComicTextPage(blocks: blocks)) {
                disk.store(data, forKey: key)
            }
            memory.setObject(Entry(blocks), forKey: memoryKey)
            let elapsed = Int(Date().timeIntervalSince(started) * 1000)
            AppLogger.shared.log("🈶 [ComicOCR] Ảnh \(image.width)×\(image.height): \(lines.count) dòng, \(blocks.count) khối, \(elapsed) ms")
            return blocks
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            AppLogger.shared.log("❌ [ComicOCR] Nhận chữ ảnh \(image.width)×\(image.height) lỗi: \(error.localizedDescription)")
            throw error
        }
    }

    /// Xoá cả RAM lẫn `Caches/comic_ocr/`, chờ xoá xong (màn Dung lượng đo lại ngay sau đó). Không chặn main.
    func clearAll() async {
        memory.removeAllObjects()
        let disk = self.disk
        await Task.detached(priority: .utility) {
            disk.removeAllAndWait()
        }.value
    }

    private static func decode(_ data: Data?) -> [ComicTextBlock]? {
        guard let data,
              let page = try? JSONDecoder().decode(ComicTextPage.self, from: data),
              page.schemaVersion == ComicTextPage.currentSchemaVersion else { return nil }
        return page.blocks
    }
}
