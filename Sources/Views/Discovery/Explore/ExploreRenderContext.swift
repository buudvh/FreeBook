import Foundation

/// Phần dùng chung của mọi view section Khám phá: Referer cho bìa, cờ dịch và hành động khi chạm item.
/// Gom lại để các view section chỉ nhận `items` + `shape` + context, không lặp tham số.
struct ExploreRenderContext {
    /// `source` của tiện ích — Referer dự phòng khi item không có `host`.
    let sourceHost: String?
    /// Cờ dịch của nguồn đang xem: chuỗi của section/chip theo nguồn, chuỗi của item theo truyện (override thắng nguồn).
    let translation: TranslationConfigSnapshot.Source
    let onSelect: (ExploreItem) -> Void

    /// Referer gửi kèm khi tải bìa: host của item → `source` của tiện ích (nhiều CDN trả 403 khi thiếu Referer).
    /// Truyền nguyên văn; `RemoteCoverImage` tự chuẩn hoá về origin.
    func referer(for item: ExploreItem) -> String? {
        ExtensionHostResolver.nonEmpty(item.host) ?? sourceHost
    }

    /// Chuỗi không thuộc truyện nào (tiêu đề/phụ đề section, chip): theo cờ dịch của nguồn.
    func display(_ text: String) -> String {
        display(text, translating: translation.isSourceEnabled)
    }

    /// Cờ dịch của một item — tính **một lần** mỗi item rồi truyền vào `display(_:translating:)`.
    func isTranslationEnabled(for item: ExploreItem) -> Bool {
        translation.isTranslationEnabled(itemLink: Self.detailUrl(for: item))
    }

    /// Chuỗi hiển thị: dịch Hán-Việt khi cờ bật và chuỗi có chữ Hán (giống các tab Khám phá cũ).
    func display(_ text: String, translating: Bool) -> String {
        guard translating, TranslateUtils.containsChinese(text) else { return text }
        return TranslateUtils.translateMeta(text)
    }

    /// URL chi tiết mà chạm item sẽ mở: action `detail` có `input` ⇒ `input`, còn lại `link`.
    static func detailUrl(for item: ExploreItem) -> String {
        guard let action = item.action, action.kind == .detail,
              !action.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return item.link }
        return action.input
    }
}
