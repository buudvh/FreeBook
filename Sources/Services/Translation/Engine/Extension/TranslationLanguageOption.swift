import Foundation

/// Một ngôn ngữ do `language.js` trả về. `direction` theo trường `type` của hợp đồng: `"from"` chỉ làm nguồn, `"to"`
/// chỉ làm đích, thiếu = cả hai. `name` thiếu ⇒ tên ngôn ngữ của mã `id` theo tiếng Việt.
public struct TranslationLanguageOption: Hashable, Sendable, Identifiable {
    public enum Direction: String, Sendable {
        case both
        case from
        case to
    }

    public let id: String
    public let name: String
    public let direction: Direction

    public init(id: String, name: String?, direction: Direction) {
        self.id = id
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.name = trimmed.isEmpty ? Self.displayName(forCode: id) : trimmed
        self.direction = direction
    }

    public var canBeSource: Bool { direction != .to }
    public var canBeTarget: Bool { direction != .from }

    /// Mục "Tự nhận" của ô nguồn (mã `""`), chỉ hiện khi tiện ích khai `support_auto_detect`.
    public static let autoDetect = TranslationLanguageOption(id: "", name: "Tự nhận", direction: .from)

    /// Tên tiếng Việt của mã ngôn ngữ (`zh` ⇒ "Tiếng Trung"); không biết mã ⇒ trả lại mã.
    public static func displayName(forCode code: String) -> String {
        guard !code.isEmpty else { return "Tự nhận" }
        let locale = Locale(identifier: "vi_VN")
        let name = locale.localizedString(forIdentifier: code) ?? locale.localizedString(forLanguageCode: code) ?? code
        guard let first = name.first else { return code }
        return first.uppercased() + name.dropFirst()
    }
}
