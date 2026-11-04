import Foundation

/// Một cặp ngoặc của **bộ ngoặc** mà token `<[>` / `<]>` của rule dịch nhanh dùng (1.3.692).
///
/// Bộ ngoặc là **dữ liệu**, không phải cú pháp rule: mẫu chỉ viết `<[>`/`<]>`, nên `<` `>` `{` `}` nằm
/// trong bộ ngoặc không làm parser hiểu nhầm token hay `{i}`. Lưu ở hai chỗ cùng một định dạng JSON
/// `[{open, close, name, enabled}]`: bộ chung (`QuickTranslationRuleBracketStore`, `UserDefaults`) và bộ
/// riêng truyện (trường `brackets` của `QuickTranslateEngineConfig.json`).
///
/// Decode **chịu lỗi**: thiếu `name` ⇒ rỗng, thiếu `enabled` ⇒ bật — file sửa tay hoặc bản app khác vẫn
/// đọc được. Cặp sai luật (nhiều ký tự, trùng ký tự) không bị loại ở đây mà bị bỏ qua khi dựng
/// `QuickTranslationRuleBracketSet`; màn sửa kiểm bằng `QuickTranslationRuleBracketStore.validationError`.
public struct QuickTranslationRuleBracketPair: Codable, Hashable, Sendable {
    public var open: String
    public var close: String
    /// Tên hiển thị ngắn (vd "Ngoặc tròn toàn khổ"); chỉ để người dùng nhận ra cặp, engine không đọc.
    public var name: String
    public var isEnabled: Bool

    public init(open: String, close: String, name: String, isEnabled: Bool = true) {
        self.open = open
        self.close = close
        self.name = name
        self.isEnabled = isEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case open
        case close
        case name
        case isEnabled = "enabled"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        open = try container.decode(String.self, forKey: .open)
        close = try container.decode(String.self, forKey: .close)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(open, forKey: .open)
        try container.encode(close, forKey: .close)
        try container.encode(name, forKey: .name)
        try container.encode(isEnabled, forKey: .isEnabled)
    }

    /// Đơn vị UTF-16 duy nhất của một ô; `nil` khi ô rỗng hoặc dài hơn một đơn vị (ký tự ngoài BMP,
    /// cụm ghép). Engine so khớp theo **đơn vị UTF-16**, không theo `Character`.
    public static func singleUnit(of value: String) -> UInt16? {
        let units = Array(value.utf16)
        guard units.count == 1 else { return nil }
        return units[0]
    }
}
