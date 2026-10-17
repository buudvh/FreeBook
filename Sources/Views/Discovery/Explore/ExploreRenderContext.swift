import Foundation

/// Phần dùng chung của mọi view section Khám phá: Referer cho bìa, cờ dịch tiêu đề và hành động khi chạm item.
/// Gom lại để các view section chỉ nhận `items` + `shape` + context, không lặp tham số.
struct ExploreRenderContext {
    /// `source` của tiện ích — Referer dự phòng khi item không có `host`.
    let sourceHost: String?
    let isTranslationEnabled: Bool
    let onSelect: (ExploreItem) -> Void

    /// Referer gửi kèm khi tải bìa: host của item → `source` của tiện ích (nhiều CDN trả 403 khi thiếu Referer).
    /// Truyền nguyên văn; `RemoteCoverImage` tự chuẩn hoá về origin.
    func referer(for item: ExploreItem) -> String? {
        ExtensionHostResolver.nonEmpty(item.host) ?? sourceHost
    }

    /// Chuỗi hiển thị: dịch Hán-Việt khi nguồn bật dịch và chuỗi có chữ Hán (giống các tab Khám phá cũ).
    func display(_ text: String) -> String {
        guard isTranslationEnabled, TranslateUtils.containsChinese(text) else { return text }
        return TranslateUtils.translateMeta(text)
    }
}
