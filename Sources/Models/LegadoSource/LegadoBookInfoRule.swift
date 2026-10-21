import Foundation

/// Nhóm rule `ruleBookInfo` (spec §1.7, §5.3). Giữ mọi khoá trong `values`; accessor trả `""` khi vắng.
public struct LegadoBookInfoRule: Sendable, Hashable {
    public let values: [String: String]

    public init(values: [String: String] = [:]) {
        self.values = values
    }

    public subscript(key: String) -> String {
        values[key] ?? ""
    }

    public var isEmpty: Bool {
        values.values.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// Rule chạy trước, đổi "nội dung hiện hành" cho các trường sau (spec §5.3.1 bước 2).
    public var initRule: String { self["init"] }
    public var name: String { self["name"] }
    public var author: String { self["author"] }
    public var kind: String { self["kind"] }
    public var wordCount: String { self["wordCount"] }
    public var lastChapter: String { self["lastChapter"] }
    public var intro: String { self["intro"] }
    public var coverUrl: String { self["coverUrl"] }
    /// Rỗng = mục lục nằm ngay trên trang sách (spec §5.3.1 bước 5).
    public var tocUrl: String { self["tocUrl"] }
    /// Giá trị thô (`1`, `true`, `True`…) — luật truthy do engine áp (spec §5.3.3).
    public var canReName: String { self["canReName"] }
    /// Loại tệp tải về (3) — không dùng ở đợt 1.
    public var downloadUrls: String { self["downloadUrls"] }
}
