import Foundation

/// Lưu các kết quả AI "đã xong — chưa xem" qua lần mở app (1.3.630): một file JSON nhỏ
/// `applicationSupportDirectory/ai_unseen_results.json`, mỗi truyện một bản ghi `AIUnseenResult`.
///
/// Bản trong RAM là nguồn đọc (nạp một lần lúc khởi tạo — file chỉ vài trăm byte mỗi truyện vì không giữ nội dung
/// chương); mọi lần sửa ghi lại cả file trên queue nền riêng, theo đúng thứ tự gọi, để luồng gọi (MainActor) không
/// chờ đĩa.
public final class AIUnseenResultStore: @unchecked Sendable {
    public static let shared = AIUnseenResultStore()

    private let lock = NSLock()
    private var results: [String: AIUnseenResult]
    private let writeQueue = DispatchQueue(label: "FreeBook.AIUnseenResultStore.write", qos: .utility)

    private static var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("ai_unseen_results.json")
    }

    private init() {
        results = Self.loadFromDisk()
    }

    /// Mọi bản ghi còn giữ.
    public func all() -> [AIUnseenResult] {
        lock.lock()
        defer { lock.unlock() }
        return Array(results.values)
    }

    /// Thêm hoặc thay bản ghi của truyện.
    public func upsert(_ result: AIUnseenResult) {
        lock.lock()
        results[result.bookId] = result
        let snapshot = results
        lock.unlock()
        persist(snapshot)
    }

    /// Bỏ bản ghi của truyện; không có bản ghi ⇒ không ghi đĩa.
    public func remove(bookId: String) {
        lock.lock()
        guard results.removeValue(forKey: bookId) != nil else {
            lock.unlock()
            return
        }
        let snapshot = results
        lock.unlock()
        persist(snapshot)
    }

    private func persist(_ snapshot: [String: AIUnseenResult]) {
        writeQueue.async {
            let url = Self.fileURL
            do {
                if snapshot.isEmpty {
                    if FileManager.default.fileExists(atPath: url.path) {
                        try FileManager.default.removeItem(at: url)
                    }
                    return
                }
                let data = try JSONEncoder().encode(Array(snapshot.values))
                try data.write(to: url, options: .atomic)
            } catch {
                AppLogger.shared.log("❌ 🤖 [AI] Không ghi được danh sách kết quả AI chưa xem: \(error.localizedDescription)")
            }
        }
    }

    private static func loadFromDisk() -> [String: AIUnseenResult] {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        do {
            let data = try Data(contentsOf: url)
            let list = try JSONDecoder().decode([AIUnseenResult].self, from: data)
            return Dictionary(list.map { ($0.bookId, $0) }, uniquingKeysWith: { _, latest in latest })
        } catch {
            AppLogger.shared.log("❌ 🤖 [AI] Không đọc được danh sách kết quả AI chưa xem: \(error.localizedDescription)")
            return [:]
        }
    }
}
