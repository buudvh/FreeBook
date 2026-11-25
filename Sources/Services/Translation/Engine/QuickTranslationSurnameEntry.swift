import Foundation

/// Một họ trong **danh sách hiệu lực** của token `<ho>` (1.3.1062) = danh sách gốc đóng trong app trộn lớp riêng của
/// người dùng (`QuickTranslationSurnameOverrides`). Màn Danh sách họ vẽ thẳng từ đây; engine chỉ dùng bảng tra
/// `QuickTranslationSurnameStore.lookupTable()` (họ đang bật).
public struct QuickTranslationSurnameEntry: Identifiable, Equatable, Sendable {
    public enum Origin: Equatable, Sendable {
        /// Có trong `ChineseSurnames.txt` của app.
        case bundled
        /// Người dùng tự thêm (khoá không có trong bản gốc).
        case userAdded
    }

    /// 1–2 chữ Hán (độ dài UTF-16 ≤ 2), ví dụ `王`, `欧阳`.
    public let key: String
    /// Âm Hán-Việt đang dùng — chính là chữ `{i}` của `<ho>` trả ra.
    public let reading: String
    public let origin: Origin
    /// Âm của bản gốc; `nil` với họ tự thêm.
    public let bundledReading: String?
    /// `false` = họ vẫn hiện trong danh sách nhưng `<ho>` không khớp nó.
    public let isEnabled: Bool

    public var id: String { key }

    /// Họ gốc đã đổi âm (khác âm của bản gốc).
    public var isEdited: Bool {
        origin == .bundled && bundledReading != nil && reading != bundledReading
    }
}
