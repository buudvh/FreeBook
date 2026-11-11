import Foundation

/// Một mục của `model.js` hoặc `style.js`: `id` truyền cho `translate.js`, `name` thiếu ⇒ dùng `id`. Mục có `id` rỗng
/// bị bỏ khi đọc (hợp đồng). `isNetworkRequired` của model chưa dùng.
public struct TranslationPickerOption: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let description: String

    public init(id: String, name: String?, description: String?) {
        self.id = id
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.name = trimmedName.isEmpty ? id : trimmedName
        self.description = description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
