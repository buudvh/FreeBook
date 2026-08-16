import Foundation

/// Lưu trữ lịch sử tìm kiếm dùng chung (key `search_history` trong UserDefaults),
/// được đọc/ghi bởi màn hình Tìm Kiếm (`SearchView`) và màn hình Tìm trong Kệ sách
/// (`ShelfSearchView`) — một lịch sử cho cả hai.
enum SearchHistoryStore {
    static let storageKey = "search_history"
    static let maxCount = 15

    static func decode(_ json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let history = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return history
    }

    static func encode(_ items: [String]) -> String {
        guard let data = try? JSONEncoder().encode(items),
              let jsonString = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return jsonString
    }

    /// Thêm query vào lịch sử: trim, dedup, chèn đầu, giới hạn `maxCount`.
    static func addQuery(_ query: String, to history: [String]) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return history }
        var result = history
        result.removeAll { $0 == trimmed }
        result.insert(trimmed, at: 0)
        if result.count > maxCount {
            result = Array(result.prefix(maxCount))
        }
        return result
    }
}