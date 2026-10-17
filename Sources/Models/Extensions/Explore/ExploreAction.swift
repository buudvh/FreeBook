import Foundation

/// Hành động của trang Khám phá dạng section theo hợp đồng extension (extension-api.md): `more` của section
/// ("Xem thêm") và `action` của item.
///
/// - Thiếu `type` ⇒ parser bỏ cả action (`nil`): item rơi về mặc định `link` → chi tiết.
/// - `type` lạ ⇒ `.unsupported`: hợp đồng yêu cầu bỏ qua, chạm không làm gì (khác với thiếu `type`).
/// - `input` giữ **nguyên văn**: với `detail` nó là URL item — khoá nhận diện sách, không resolve lúc parse.
struct ExploreAction: Hashable, Sendable {
    enum Kind: String, Hashable, Sendable {
        /// Mở màn danh sách phân trang: chạy `script` với `input` làm `query` (`args[0]`), phân trang như `search`.
        case list
        /// Mở chi tiết; `input` là URL item.
        case detail
        /// Loại không hỗ trợ — chạm không làm gì.
        case unsupported
    }

    let kind: Kind
    /// `type` gốc đã trim + chữ thường, giữ để log khi gặp loại lạ.
    let rawType: String
    /// Tiêu đề màn danh sách mà action `list` mở.
    let name: String
    /// Tên file script (vd `latest.js`), chỉ dùng cho `list`.
    let script: String
    let input: String
}
