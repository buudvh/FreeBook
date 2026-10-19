import Foundation

/// Trạng thái hiển thị của một bộ lọc cho màn Cài đặt → Trình duyệt (`AdBlockRuleListProvider.statuses`).
struct AdBlockFilterStatus: Equatable, Sendable {
    /// Số luật WebKit sau chuyển đổi; `nil` = chưa từng biên dịch.
    var safariRuleCount: Int?
    /// Thời điểm file bộ lọc được tải về; bản đóng gói ⇒ ngày ghi trong `adblock_bundled_meta.json`.
    var updatedAt: Date?
    /// Đang tải/biên dịch lại bộ này.
    var isUpdating: Bool
    /// Lỗi tải gần nhất (vẫn dùng bản cũ nếu có). Tải thành công thì xoá.
    var lastError: String?
    /// Có file (tải hoặc đóng gói) đã biên dịch thành rule list.
    var hasData: Bool

    static let empty = AdBlockFilterStatus(
        safariRuleCount: nil,
        updatedAt: nil,
        isUpdating: false,
        lastError: nil,
        hasData: false
    )
}
