import Foundation

/// Bộ lưu trữ và quản lý lịch sử duyệt web của Trình duyệt Bypass.
public final class BrowserHistoryStore: @unchecked Sendable {
    public static let shared = BrowserHistoryStore()
    public static let didChangeNotification = Notification.Name("BrowserHistoryStoreDidChangeNotification")

    public struct Item: Codable, Identifiable, Equatable, Sendable {
        public let id: String
        public let title: String
        public let urlString: String
        public let timestamp: Date

        public init(
            id: String = UUID().uuidString,
            title: String,
            urlString: String,
            timestamp: Date = Date()
        ) {
            self.id = id
            self.title = title
            self.urlString = urlString
            self.timestamp = timestamp
        }
    }

    private let userDefaultsKey = "bypass_browser_history_items"
    private let maxItemCount = 200
    private let queue = DispatchQueue(label: "com.freebook.browserhistory", qos: .utility)

    private init() {}

    public func load() -> [Item] {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let items = try? JSONDecoder().decode([Item].self, from: data) else {
            return []
        }
        return items
    }

    public func add(title: String, urlString: String) {
        let cleanUrl = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanUrl.isEmpty,
              cleanUrl != "about:blank",
              !cleanUrl.hasPrefix("data:"),
              !cleanUrl.hasPrefix("blob:") else { return }

        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = cleanTitle.isEmpty ? (URL(string: cleanUrl)?.host ?? cleanUrl) : cleanTitle

        queue.async { [weak self] in
            guard let self = self else { return }
            var items = self.load()
            items.removeAll { $0.urlString == cleanUrl }
            let newItem = Item(title: displayTitle, urlString: cleanUrl, timestamp: Date())
            items.insert(newItem, at: 0)

            if items.count > self.maxItemCount {
                items = Array(items.prefix(self.maxItemCount))
            }

            if let encoded = try? JSONEncoder().encode(items) {
                UserDefaults.standard.set(encoded, forKey: self.userDefaultsKey)
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
                }
            }
        }
    }

    public func delete(id: String) {
        queue.async { [weak self] in
            guard let self = self else { return }
            var items = self.load()
            items.removeAll { $0.id == id }
            if let encoded = try? JSONEncoder().encode(items) {
                UserDefaults.standard.set(encoded, forKey: self.userDefaultsKey)
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
                }
            }
        }
    }

    public func clearAll() {
        queue.async { [weak self] in
            guard let self = self else { return }
            UserDefaults.standard.removeObject(forKey: self.userDefaultsKey)
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
            }
        }
    }
}
