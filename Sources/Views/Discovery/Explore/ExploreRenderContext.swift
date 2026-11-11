import Foundation

/// Phần dùng chung của mọi view section Khám phá: Referer cho bìa, cấu hình chữ Trung và hành động khi chạm item.
/// Gom lại để các view section chỉ nhận `items` + `shape` + context, không lặp tham số.
struct ExploreRenderContext {
    /// `source` của tiện ích — Referer dự phòng khi item không có `host`.
    let sourceHost: String?
    /// Phồn → giản + dịch của nguồn (Nguồn ⇒ Tất cả, `ChineseTextPipeline.sourceOptions`), `DiscoveryView` tính một lần.
    let textOptions: ChineseTextPipeline.Options
    /// Cỡ từng bố cục theo loại nguồn (`ExploreLayoutSizePreferences`).
    var sizes: ExploreLayoutSizes = .default
    let onSelect: (ExploreItem) -> Void
    /// Nguồn âm thanh / phim ⇒ item mở được có ⋮ "Thêm vào playlist / Thêm vào kệ" (1.3.810); `nil` với truyện chữ /
    /// truyện tranh.
    var playlist: PlaylistListAddContext? = nil

    /// Referer gửi kèm khi tải bìa: host của item → `source` của tiện ích (nhiều CDN trả 403 khi thiếu Referer).
    /// Truyền nguyên văn; `RemoteCoverImage` tự chuẩn hoá về origin.
    func referer(for item: ExploreItem) -> String? {
        ExtensionHostResolver.nonEmpty(item.host) ?? sourceHost
    }

    /// Chuỗi hiển thị: phồn → giản nếu nguồn bật, rồi dịch nếu nguồn bật dịch (giống các tab Khám phá cũ).
    func display(_ text: String) -> String {
        ChineseTextPipeline.meta(text, textOptions)
    }

    /// Item cho ⋮ "Thêm vào playlist": chỉ khi nguồn có playlist và item mở chi tiết được (không action / action
    /// `detail`) — item action `list` là danh mục, không phải album / phim.
    func playlistItem(for item: ExploreItem) -> ExtensionItemResult? {
        guard playlist != nil, let url = Self.detailUrl(of: item) else { return nil }
        return Self.listItem(item, detailUrl: url)
    }

    /// Link chi tiết khi chạm mở item: không action ⇒ `link`; action `detail` ⇒ `input` (rỗng ⇒ `link`); action khác
    /// hoặc link rỗng ⇒ `nil`.
    static func detailUrl(of item: ExploreItem) -> String? {
        let url: String
        if let action = item.action {
            guard action.kind == .detail else { return nil }
            url = action.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? item.link : action.input
        } else {
            url = item.link
        }
        return url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : url
    }

    /// Item danh sách dựng từ mục Khám phá (như lúc mở chi tiết): `link` = link chi tiết.
    static func listItem(_ item: ExploreItem, detailUrl: String) -> ExtensionItemResult {
        ExtensionItemResult(
            name: item.name,
            description: item.description,
            cover: item.cover,
            link: detailUrl,
            host: item.host,
            tag: item.tag,
            type: item.type
        )
    }
}
