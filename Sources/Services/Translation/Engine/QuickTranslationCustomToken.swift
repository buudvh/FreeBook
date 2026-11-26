import Foundation

/// Một **token tùy chọn** của rule dịch nhanh (1.3.1063, anh Bửu: "thêm chức năng thêm và sử dụng bộ token tùy chọn"):
/// người dùng tự đặt tên, tự nhập danh sách `chữ gốc=nghĩa`; trong rule viết `<@tên>` để khớp **một** từ của danh sách,
/// `{i}` ra nghĩa của từ đó (từ dài thử trước, như `<ho>`).
///
/// Lưu cả bộ ở `UserDefaults` khoá `quickTranslateCustomTokens` (`QuickTranslationCustomTokenStore`). Tên chỉ đặt lúc
/// tạo, không đổi được: rule gọi token bằng tên, đổi tên là rule cũ âm thầm thôi khớp.
public struct QuickTranslationCustomToken: Codable, Equatable, Sendable, Identifiable {
    /// Một từ của danh sách. Khoá JSON viết tắt `k` / `m` để bộ vài nghìn từ không phình `UserDefaults`.
    public struct Entry: Codable, Equatable, Sendable, Identifiable {
        /// Chữ gốc, 1–12 đơn vị UTF-16 (`QuickTranslationCustomTokenListParser.maxKeyUTF16Length`).
        public var key: String
        /// Chữ `{i}` trả ra khi `key` khớp.
        public var meaning: String

        public var id: String { key }

        public init(key: String, meaning: String) {
            self.key = key
            self.meaning = meaning
        }

        enum CodingKeys: String, CodingKey {
            case key = "k"
            case meaning = "m"
        }
    }

    /// `a-z`, `0-9`, `_`, bắt đầu bằng chữ (`QuickTranslationCustomTokenListParser.nameError`). Rule viết `<@name>`.
    public let name: String
    /// Mô tả hiện ở chip bảng token và hàng danh sách; rỗng ⇒ hiện tên.
    public var title: String
    /// `false` = rule có `<@name>` tạm không khớp; danh sách từ giữ nguyên.
    public var isEnabled: Bool
    /// Theo thứ tự hiện ở màn danh sách từ (từ thêm tay đứng đầu, từ nhập file nối theo thứ tự file).
    public var entries: [Entry]

    public var id: String { name }

    /// Cú pháp trong rule: `<@name>`.
    public var syntax: String { "<@\(name)>" }

    /// Nhãn ngắn: mô tả, hoặc tên khi chưa có mô tả.
    public var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? name : trimmed
    }

    public init(name: String, title: String, isEnabled: Bool = true, entries: [Entry] = []) {
        self.name = name
        self.title = title
        self.isEnabled = isEnabled
        self.entries = entries
    }

    enum CodingKeys: String, CodingKey {
        case name
        case title
        case isEnabled = "enabled"
        case entries
    }

    /// Trường vắng = giá trị mặc định: JSON sửa tay hay của bản sau thiếu trường vẫn đọc được.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        entries = try container.decodeIfPresent([Entry].self, forKey: .entries) ?? []
    }
}
