import Foundation

public struct SearchEngine: Codable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var urlTemplate: String
    
    public init(id: UUID = UUID(), name: String, urlTemplate: String) {
        self.id = id
        self.name = name
        self.urlTemplate = urlTemplate
    }
}

extension SearchEngine {
    public static let defaults: [SearchEngine] = [
        SearchEngine(
            name: "Google",
            urlTemplate: "https://www.google.com/search?q=Giải thích ý nghĩa đoạn văn hoặc cụm từ tiếng Trung: “%s”. Nếu có tên tiếng Nhật hoặc tiếng Anh thì liệt kê riêng từng tên kèm nghĩa hoặc cách đọc tương ứng. Nếu có thành ngữ hoặc tục ngữ tiếng Việt đồng nghĩa hãy liệt kê ra. Trả lời ngắn gọn, chính xác, tự nhiên, không thêm bình luận ngoài phạm vi yêu cầu."
        ),
        SearchEngine(
            name: "Copilot",
            urlTemplate: "https://www.bing.com/copilotsearch?q=Giải thích ý nghĩa đoạn văn hoặc cụm từ tiếng Trung: “%s”. Nếu có tên tiếng Nhật hoặc tiếng Anh thì liệt kê riêng từng tên kèm nghĩa hoặc cách đọc tương ứng. Nếu có thành ngữ hoặc tục ngữ tiếng Việt đồng nghĩa hãy liệt kê ra. Trả lời ngắn gọn, chính xác, tự nhiên, không thêm bình luận ngoài phạm vi yêu cầu."
        ),
        SearchEngine(
            name: "Hanzii",
            urlTemplate: "https://hanzii.net/search/word/%s?hl=vi-VN"
        )
    ]
    
    public static func loadEngines() -> [SearchEngine] {
        guard let data = UserDefaults.standard.data(forKey: "custom_search_engines") else {
            saveEngines(defaults)
            return defaults
        }
        
        do {
            return try JSONDecoder().decode([SearchEngine].self, from: data)
        } catch {
            return defaults
        }
    }
    
    public static func saveEngines(_ engines: [SearchEngine]) {
        if let data = try? JSONEncoder().encode(engines) {
            UserDefaults.standard.set(data, forKey: "custom_search_engines")
        }
    }
}
