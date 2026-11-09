import Foundation

/// Một nguồn lời bài hát của bài đang nghe — từ `lyrics: [{data, type, label, language}]` (hoặc phần tử chuỗi trần), hoặc
/// trường đơn `lyric` + `lyricType` của `track.js` (hợp đồng tiện ích, loại `audio`). Ánh xạ bởi `AudioLyricMapper`.
///
/// `data` giữ **nguyên văn**: URL http(s), URI `data:` hoặc chính nội dung lời. Định dạng lời tự nhận từ nội dung
/// (`AudioLyricParser`); `type` chỉ để tham khảo.
public struct AudioLyricSource: Sendable, Hashable, Identifiable {
    /// Vị trí trong danh sách nguồn lời của bài (0, 1, 2…) — ổn định trong một lượt nạp bài.
    public let id: Int
    public let data: String
    public let type: String?
    public let label: String?
    public let language: String?

    public init(id: Int, data: String, type: String? = nil, label: String? = nil, language: String? = nil) {
        self.id = id
        self.data = data
        self.type = type
        self.label = label
        self.language = language
    }

    /// Tên hiện ở bộ chọn nguồn lời: `label` → `language` → "Lời N".
    public var displayLabel: String {
        if let label, !label.isEmpty { return label }
        if let language, !language.isEmpty { return language }
        return "Lời \(id + 1)"
    }
}
