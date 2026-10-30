import Foundation

/// Yêu cầu mở bảng chia sẻ của trình duyệt (`BypassBrowserTabStore.shareRequest`): giao diện gán, phần menu nhấn giữ
/// trình bày `ShareSheet(activityItems:)` rồi xoá về `nil`. Mỗi lần gán là một `id` mới để sheet mở lại kể cả cùng nội dung.
struct BrowserShareRequest: Identifiable {
    let id = UUID()
    let items: [Any]
}
