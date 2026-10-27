import Foundation

/// Cuộc chat Chế độ AI của Google gắn với từng phiên chat của app (1.3.609): token `mstk` **mới nhất** + băm khối ngữ
/// cảnh hệ thống đã gửi. Thử thật: mở `search?udm=50&mstk=<token mới nhất>` hiện lại đủ mọi lượt của cuộc chat.
///
/// Lưu riêng chứ không nhét vào `AIChatSession` — cùng lý do với `GeminiWebConversationStore` (màn AI và coordinator cùng
/// ghi phiên). Token ghi ngay khi trang để lộ (kể cả lượt sau đó lỗi/bị huỷ) để lượt sau không khôi phục bản cũ hơn.
enum GoogleAIModeConversationStore {
    struct Entry: Codable, Sendable {
        var mstk: String
        var contextFingerprint: String
        var updatedAt: Date
    }

    private static let storageKey = "FreeBook_AIMode_Conversations_V1"
    private static let maxEntries = 200
    private static let lock = NSLock()

    static func load(sessionId: UUID) -> Entry? {
        lock.lock()
        defer { lock.unlock() }
        return all()[sessionId.uuidString]
    }

    static func save(mstk: String, contextFingerprint: String, sessionId: UUID) {
        guard !mstk.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        var entries = all()
        entries[sessionId.uuidString] = Entry(mstk: mstk, contextFingerprint: contextFingerprint, updatedAt: Date())
        if entries.count > maxEntries {
            let keep = entries.sorted { $0.value.updatedAt > $1.value.updatedAt }.prefix(maxEntries)
            entries = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    /// Quên cuộc chat của một phiên (1.3.614): tráo sang tài khoản Google khác thì `mstk` cũ thuộc tài khoản trước,
    /// mở lại chỉ ra `threadUnavailable` — xoá trước để lượt sau mở cuộc chat mới với đủ ngữ cảnh.
    static func delete(sessionId: UUID) {
        lock.lock()
        defer { lock.unlock() }
        var entries = all()
        guard entries.removeValue(forKey: sessionId.uuidString) != nil else { return }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private static func all() -> [String: Entry] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let entries = try? JSONDecoder().decode([String: Entry].self, from: data) else {
            return [:]
        }
        return entries
    }
}
