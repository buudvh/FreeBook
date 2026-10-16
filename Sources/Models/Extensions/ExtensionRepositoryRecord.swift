import Foundation

/// Bản ghi tối thiểu của một kho tiện ích (`extension_store/repositories.json`), thay `@Model Repository`.
///
/// Không còn `isEnabled` (không có UI bật/tắt) và `lastUpdated` (UI chỉ hiện `name` + `url`; cooldown làm mới
/// kho do `RepositoryRefreshPolicy` giữ riêng). Thứ tự trong file = thứ tự thêm kho.
public struct ExtensionRepositoryRecord: Codable, Identifiable, Hashable, Sendable {
    public var url: String
    public var name: String
    public var author: String?
    public var desc: String?
    public var addedAt: Date

    public var id: String { url }

    public init(url: String, name: String, author: String? = nil, desc: String? = nil, addedAt: Date = Date()) {
        self.url = url
        self.name = name
        self.author = author
        self.desc = desc
        self.addedAt = addedAt
    }

    private enum CodingKeys: String, CodingKey {
        case url, name, author, desc, addedAt
    }

    /// Decode khoan dung: chỉ `url` bắt buộc.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = try c.decode(String.self, forKey: .url)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? url
        author = try c.decodeIfPresent(String.self, forKey: .author)
        desc = try c.decodeIfPresent(String.self, forKey: .desc)
        addedAt = try c.decodeIfPresent(Date.self, forKey: .addedAt) ?? Date(timeIntervalSince1970: 0)
    }
}
