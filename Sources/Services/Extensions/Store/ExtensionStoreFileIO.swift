import Foundation

/// Đọc/ghi file JSON của `extension_store/` — dùng chung cho `ExtensionIndexStore` và
/// `ExtensionLocalStorageStore`. Đồng bộ, không tự chọn queue: caller quyết định chạy ở đâu.
///
/// Luật an toàn:
/// - Mọi đường dẫn phải qua `ExtensionStorePaths.validatePathSafety`.
/// - Ghi `.atomic` (file tạm rồi đổi tên) ⇒ crash giữa chừng không để lại file nửa vời.
/// - Đọc/decode lỗi **không** bao giờ dẫn tới ghi đè im lặng: file hỏng được đổi tên thành
///   `<tên>.corrupt-<timestamp>` (giữ lại để cứu tay) rồi coi như rỗng, kèm log `❌`.
enum ExtensionStoreFileIO {
    /// `nil` khi file chưa có, hoặc hỏng (đã cách ly).
    static func read<T: Decodable>(_ type: T.Type, from url: URL, label: String) -> T? {
        guard ExtensionStorePaths.validatePathSafety(url) else {
            AppLogger.shared.log("❌ 🧩 [ExtStore] Từ chối đọc \(label): đường dẫn nằm ngoài extension_store")
            return nil
        }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try ExtensionStoreEnvelope.makeDecoder().decode(T.self, from: data)
        } catch {
            AppLogger.shared.log("❌ 🧩 [ExtStore] Đọc \(label) lỗi, cách ly file và coi như rỗng: \(error)")
            quarantine(url, label: label)
            return nil
        }
    }

    @discardableResult
    static func write<T: Encodable>(_ value: T, to url: URL, label: String) -> Bool {
        guard ExtensionStorePaths.validatePathSafety(url) else {
            AppLogger.shared.log("❌ 🧩 [ExtStore] Từ chối ghi \(label): đường dẫn nằm ngoài extension_store")
            return false
        }
        do {
            ExtensionStorePaths.ensureDirectories()
            let data = try ExtensionStoreEnvelope.makeEncoder().encode(value)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch {
            AppLogger.shared.log("❌ 🧩 [ExtStore] Ghi \(label) thất bại: \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    static func remove(at url: URL, label: String) -> Bool {
        guard ExtensionStorePaths.validatePathSafety(url) else {
            AppLogger.shared.log("❌ 🧩 [ExtStore] Từ chối xoá \(label): đường dẫn nằm ngoài extension_store")
            return false
        }
        guard FileManager.default.fileExists(atPath: url.path) else { return true }
        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch {
            AppLogger.shared.log("❌ 🧩 [ExtStore] Xoá \(label) thất bại: \(error.localizedDescription)")
            return false
        }
    }

    /// Đổi tên file hỏng thành `<tên>.corrupt-<timestamp>` — không còn đuôi `.json` nên không bị đọc lại.
    static func quarantine(_ url: URL, label: String) {
        let stamp = Int(Date().timeIntervalSince1970)
        let target = url.deletingLastPathComponent().appendingPathComponent("\(url.lastPathComponent).corrupt-\(stamp)")
        do {
            try FileManager.default.moveItem(at: url, to: target)
        } catch {
            AppLogger.shared.log("❌ 🧩 [ExtStore] Không cách ly được \(label): \(error.localizedDescription)")
        }
    }
}
