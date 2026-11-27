import Foundation

/// Một đuôi trong **danh sách hiệu lực** "Đuôi địa danh, tổ chức, thuật ngữ" của Lọc name local = danh sách gốc đóng trong app
/// (`NameFilterSuffixes.txt`) trộn lớp riêng của người dùng (`LocalNameFilterSuffixOverrides`). Màn danh sách vẽ thẳng
/// từ đây; bộ lọc nhận **mọi** đuôi dưới dạng `LocalNameFilter.Suffix` (`LocalNameFilterSuffixStore.allSuffixes()`) — từ
/// cách A (2026-11-27) danh sách chỉ dùng để ghép nghĩa, không còn bật / tắt.
struct LocalNameFilterSuffixEntry: Identifiable, Equatable, Sendable {
    enum Origin: Equatable, Sendable {
        /// Có trong `NameFilterSuffixes.txt` của app.
        case bundled
        /// Người dùng tự thêm (khoá không có trong bản gốc).
        case userAdded
    }

    /// Phần sửa được của một đuôi.
    struct Value: Codable, Equatable, Hashable, Sendable {
        var meaning: String
        var kind: LocalNameFilter.SuffixKind
        var position: LocalNameFilter.MeaningPosition
    }

    /// 1–2 chữ Hán, ví dụ `城`, `山脉`.
    let key: String
    let value: Value
    let origin: Origin
    /// Giá trị của bản gốc; `nil` với đuôi tự thêm.
    let bundledValue: Value?

    var id: String { key }
    var meaning: String { value.meaning }
    var kind: LocalNameFilter.SuffixKind { value.kind }
    var position: LocalNameFilter.MeaningPosition { value.position }

    /// Đuôi gốc đã đổi nghĩa / loại / vị trí (khác bản gốc).
    var isEdited: Bool {
        origin == .bundled && bundledValue != nil && value != bundledValue
    }

    /// Đúng dạng bộ lọc dùng.
    var suffix: LocalNameFilter.Suffix {
        LocalNameFilter.Suffix(key: key, meaning: value.meaning, kind: value.kind, position: value.position)
    }
}
