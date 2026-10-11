import Foundation

/// Lưu `GeminiWebConversationState` theo id phiên chat của app, để mở lại app vẫn nối tiếp đúng cuộc chat Gemini.
///
/// Lưu **riêng** chứ không nhét vào `AIChatSession`: màn AI và `AIRuntimeCoordinator` cùng ghi phiên chat gần như
/// đồng thời khi một lượt kết thúc, nên một trường mới trong phiên dễ bị bên kia ghi đè mất. Chỉ `GeminiWebClient`
/// (actor) gọi vào đây nên không có ghi đồng thời. Giữ tối đa `maxEntries` cuộc chat dùng gần nhất — phiên đã xoá
/// trong app chỉ để lại một mục nhỏ, tự rơi khỏi danh sách.
enum GeminiWebConversationStore {
    /// Công tắc "Lưu chat vào lịch sử Gemini" (mặc định tắt = chat tạm). Khoá chữ thường ⇒ được sao lưu cùng cài đặt.
    static let saveHistoryKey = "geminiWebSaveHistory"

    private static let storageKey = "geminiWebConversations"
    private static let maxEntries = 100

    static var saveToHistory: Bool {
        UserDefaults.standard.bool(forKey: saveHistoryKey)
    }

    static func load(sessionId: UUID) -> GeminiWebConversationState? {
        all()[sessionId.uuidString]
    }

    static func save(_ state: GeminiWebConversationState, sessionId: UUID) {
        var entries = all()
        entries[sessionId.uuidString] = state
        if entries.count > maxEntries {
            let keep = entries.sorted { $0.value.updatedAt > $1.value.updatedAt }.prefix(maxEntries)
            entries = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    static func remove(sessionId: UUID) {
        var entries = all()
        guard entries.removeValue(forKey: sessionId.uuidString) != nil,
              let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private static func all() -> [String: GeminiWebConversationState] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let entries = try? JSONDecoder().decode([String: GeminiWebConversationState].self, from: data) else {
            return [:]
        }
        return entries
    }
}
