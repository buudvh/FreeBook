import Foundation

/// Một item trong section của trang Khám phá (script `explore`).
///
/// Khác item danh sách (`ExtensionItemResult`): hợp đồng extension **không** lọc trùng item khám phá, nên `id`
/// theo vị trí trong section chứ không theo `link`.
struct ExploreItem: Identifiable, Hashable, Sendable {
    /// `<id section>#<vị trí>` — ổn định qua các lượt tải lại cùng dữ liệu.
    let id: String
    /// Đã trim, luôn khác rỗng (item tên rỗng bị bỏ lúc parse).
    let name: String
    /// Đã resolve theo `ExtensionURLFormatter.resolveAssetURL` (host item → `source` của tiện ích).
    let cover: String
    /// Nguyên văn từ script — khoá nhận diện sách, không resolve lúc parse.
    let link: String
    let description: String
    /// Nhãn ngắn trên bìa ("Hoàn thành", "Tập 12", "FHD"…); `""` khi không có.
    let tag: String
    /// Nguyên văn: `""` khi script không trả `host` (nơi mở chi tiết tự rơi về `source`).
    let host: String
    /// Loại nội dung (`stream`, `short`, rỗng…), chữ thường. Hiện mọi loại đều mở chi tiết như thường.
    let type: String
    /// `nil` ⇒ chạm mở chi tiết theo `link`.
    let action: ExploreAction?
}
