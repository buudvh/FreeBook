import Foundation

public struct TOCRule: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let rule: String
    public let example: String?
    public var enabled: Bool
    public let replace: String
    public let isRegex: Bool

    public var pattern: String { rule }

    public init(
        id: String = UUID().uuidString,
        name: String,
        rule: String,
        example: String? = nil,
        enabled: Bool = true,
        replace: String = "",
        isRegex: Bool = true
    ) {
        self.id = id
        self.name = name
        self.rule = rule
        self.example = example
        self.enabled = enabled
        self.replace = replace
        self.isRegex = isRegex
    }

    public init(
        name: String,
        pattern: String,
        replace: String,
        isRegex: Bool = true
    ) {
        self.id = name
        self.name = name
        self.rule = pattern
        self.example = nil
        self.enabled = true
        self.replace = replace
        self.isRegex = isRegex
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, rule, example, enabled, replace, isRegex
    }

    /// Đọc được cả file kiểu cũ: trước 2026-08-13 `TOCRule` chỉ có `id, name, rule, example, enabled`, sau đó
    /// mới thêm `replace`/`isRegex` **bắt buộc** — decoder tự sinh vì thế làm hỏng `toc_rules.json` cũ (app lẳng
    /// lặng rơi về bộ mặc định), file rule xuất từ bản cũ và bản sao lưu cũ. Trường thiếu lấy đúng giá trị
    /// mặc định của `init`; `id`, `name`, `rule` vẫn bắt buộc. Trường mới thêm sau này cũng phải `decodeIfPresent`.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.rule = try container.decode(String.self, forKey: .rule)
        self.example = try container.decodeIfPresent(String.self, forKey: .example)
        self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        self.replace = try container.decodeIfPresent(String.self, forKey: .replace) ?? ""
        self.isRegex = try container.decodeIfPresent(Bool.self, forKey: .isRegex) ?? true
    }
}
