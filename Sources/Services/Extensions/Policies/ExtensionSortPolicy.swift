import Foundation

/// Thứ tự tiện ích **đã cài** ở chọn nguồn Khám phá và tab "Tất cả tiện ích" của Kho Tiện Ích:
///
/// 1. Đã ghim — `pinnedAt` **tăng dần** (ghim sau nằm cuối nhóm, không đẩy cái ghim trước xuống).
/// 2. Chưa ghim, đã từng dùng — `lastUsedAt` **giảm dần** (vừa dùng nằm trên).
/// 3. Chưa dùng bao giờ — tên A-Z.
///
/// Hoà nhau (cùng `pinnedAt` — migrator gán một mốc chung cho mọi tiện ích đã ghim — hoặc cùng `lastUsedAt`)
/// thì rơi về tên A-Z, nên ngay sau migrate thứ tự vẫn y như bản cũ (ghim → A-Z).
///
/// Thuần, không trạng thái, không actor — gọi được từ mọi nơi. Màn Tìm kiếm và danh sách TTS tiện ích
/// **không** dùng thứ tự này (giữ thứ tự cũ).
public enum ExtensionSortPolicy {
    /// `true` nếu `lhs` phải đứng trước `rhs` — dùng trực tiếp làm `sorted(by:)`.
    public static func areInIncreasingOrder(_ lhs: Extension, _ rhs: Extension) -> Bool {
        switch (lhs.pinnedAt, rhs.pinnedAt) {
        case let (left?, right?):
            return left != right ? left < right : isNameAscending(lhs, rhs)
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            break
        }

        switch (lhs.lastUsedAt, rhs.lastUsedAt) {
        case let (left?, right?) where left != right:
            return left > right
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            return isNameAscending(lhs, rhs)
        }
    }

    public static func sorted(_ extensions: [Extension]) -> [Extension] {
        extensions.sorted(by: areInIncreasingOrder)
    }

    static func isNameAscending(_ lhs: Extension, _ rhs: Extension) -> Bool {
        lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}
