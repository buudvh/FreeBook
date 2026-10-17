import Foundation

/// Một dòng trong registry (`plugin.json` cấp kho) của một kho tiện ích.
///
/// Chuyển từ `ExtensionManager.swift` sang Models vì giờ nó còn là dữ liệu **lưu đĩa**: cache registry của
/// từng kho (`ExtensionRegistrySnapshot`) giữ nguyên văn danh sách này để tab Tiện ích dựng được danh mục
/// tiện ích chưa cài khi offline. Tên field giữ nguyên để decode được JSON registry thật.
///
/// Decode **khoan dung**: chỉ `name` và `path` là bắt buộc; trường tuỳ chọn sai kiểu (vd `"version": "2"`,
/// `"nsfw": "true"`) rơi về giá trị đọc được hoặc `nil` thay vì làm hỏng cả registry.
public struct ExtensionRegistryItem: Codable, Sendable, Hashable {
    public let name: String
    public let author: String?
    public let path: String // Link tải file plugin.zip
    public let version: Int?
    public let source: String? // URL trang web nguồn (ví dụ: https://truyenfull.vn)
    public let icon: String?
    public let description: String?
    public let type: String? // "novel", "chinese_novel", "comic", "tts"
    public let locale: String? // "vi_VN", "zh_CN", ...
    /// Cờ nội dung người lớn (`metadata.nsfw` của hợp đồng extension) — `nil` khi registry không khai.
    public let nsfw: Bool?
    /// Kiểu cũ: `"tag": "nsfw"`.
    public let tag: String?
    public let tags: [String]?

    private enum CodingKeys: String, CodingKey {
        case name, author, path, version, source, icon, description, type, locale, nsfw, tag, tags
    }

    public init(
        name: String,
        author: String? = nil,
        path: String,
        version: Int? = nil,
        source: String? = nil,
        icon: String? = nil,
        description: String? = nil,
        type: String? = nil,
        locale: String? = nil,
        nsfw: Bool? = nil,
        tag: String? = nil,
        tags: [String]? = nil
    ) {
        self.name = name
        self.author = author
        self.path = path
        self.version = version
        self.source = source
        self.icon = icon
        self.description = description
        self.type = type
        self.locale = locale
        self.nsfw = nsfw
        self.tag = tag
        self.tags = tags
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        path = try c.decode(String.self, forKey: .path)
        author = Self.lenientString(c, .author)
        version = (try? c.decodeIfPresent(Int.self, forKey: .version))
            ?? Self.lenientString(c, .version).flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        source = Self.lenientString(c, .source)
        icon = Self.lenientString(c, .icon)
        description = Self.lenientString(c, .description)
        type = Self.lenientString(c, .type)
        locale = Self.lenientString(c, .locale)
        nsfw = Self.lenientBool(c, .nsfw)
        tag = Self.lenientString(c, .tag) ?? (try? c.decodeIfPresent([String].self, forKey: .tag))?.joined(separator: ",")
        tags = (try? c.decodeIfPresent([String].self, forKey: .tags))
            ?? Self.lenientString(c, .tags).map { [$0] }
    }

    /// `true` khi registry khai `nsfw` hoặc gắn thẻ `nsfw` (`tag`/`tags`); `false` khi chỉ khai `nsfw: false`;
    /// `nil` khi không khai gì.
    public var isNsfw: Bool? {
        let tagValues = [tag].compactMap { $0 } + (tags ?? [])
        if tagValues.contains(where: Self.isNsfwTag) { return true }
        return nsfw
    }

    /// Một giá trị thẻ (`"nsfw"`, `"18+,nsfw"`, `"NSFW; comic"`…) có chứa thẻ `nsfw` không.
    public static func isNsfwTag(_ raw: String) -> Bool {
        raw.lowercased()
            .components(separatedBy: CharacterSet(charactersIn: ",;|/").union(.whitespacesAndNewlines))
            .contains("nsfw")
    }

    /// Chuỗi, hoặc số ⇒ chuỗi; sai kiểu ⇒ `nil` (không ném).
    private static func lenientString(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> String? {
        if let text = try? c.decodeIfPresent(String.self, forKey: key) { return text }
        if let number = try? c.decodeIfPresent(Int.self, forKey: key) { return String(number) }
        return nil
    }

    /// `true`/`false`, `"true"`/`"1"`/`"yes"`, `1`/`0`; sai kiểu ⇒ `nil`.
    private static func lenientBool(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Bool? {
        if let flag = try? c.decodeIfPresent(Bool.self, forKey: key) { return flag }
        if let number = try? c.decodeIfPresent(Int.self, forKey: key) { return number != 0 }
        guard let text = try? c.decodeIfPresent(String.self, forKey: key) else { return nil }
        switch text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "1", "yes": return true
        case "false", "0", "no": return false
        default: return nil
        }
    }
}
