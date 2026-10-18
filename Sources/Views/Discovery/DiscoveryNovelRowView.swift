import SwiftUI

/// Dòng truyện của các danh sách Khám phá kiểu cũ (tab `home` trong `DiscoveryCategoryTabView`, màn
/// `CategoryNovelsListView`).
///
/// Cùng bố cục với `BookListItemView` kiểu `.discovery` (bìa 50×70, tên in hoa đầu từ + dịch, mô tả 2 dòng, không
/// có mô tả thì hiện tác giả). Giữ view riêng thay vì dùng `BookListItemView` vì bìa ở đây **không được ghi xuống đĩa**:
/// - `BookListItemView` dùng `BookCoverView`, ghi bìa vào `covers/` theo `link` như sách đã lưu; item Khám phá chỉ là
///   danh sách tạm, nên tải qua `RemoteCoverImage` (cache ở `Caches`) kèm Referer (host item → `source` của tiện
///   ích) — nhiều CDN trả 403 khi thiếu.
/// - Nhãn `tag` dùng chung `CoverTagBadge` (cùng kiểu với Tìm kiếm/Gợi ý), đè góc dưới bìa.
struct DiscoveryNovelRowView: View {
    let item: ExtensionItemResult
    /// `source` của tiện ích — Referer dự phòng khi item không có `host`.
    let sourceHost: String?
    /// Cờ dịch **theo nguồn** (`TranslationConfigStore`, do màn cha tính) — không đọc công tắc dịch toàn app, nếu không
    /// tắt dịch cho một nguồn thì danh sách vẫn dịch.
    let isTranslationEnabled: Bool

    var body: some View {
        HStack(spacing: 12) {
            Color(.secondarySystemBackground)
                .frame(width: 50, height: 70)
                .overlay {
                    RemoteCoverImage(
                        url: item.cover,
                        referer: ExtensionHostResolver.nonEmpty(item.host) ?? sourceHost,
                        contentMode: .fill
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(alignment: .bottomLeading) {
                    CoverTagBadge(tag: translateIfNeeded(item.tag))
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(DisplayTextFormatter.titleCase(translateIfNeeded(item.name, bookId: item.link)))
                    .font(.system(size: 14.5, weight: .semibold))
                    .lineLimit(2)

                if !item.description.isEmpty {
                    Text(translateIfNeeded(item.description.cleanHTML()))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                } else if !item.author.isEmpty {
                    Text(DisplayTextFormatter.titleCase(displayedAuthor))
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
    }

    private var displayedAuthor: String {
        guard isTranslationEnabled else { return item.author }
        return TranslateUtils.translateAuthorHanViet(item.author)
    }

    private func translateIfNeeded(_ text: String, bookId: String? = nil) -> String {
        guard isTranslationEnabled && TranslateUtils.containsChinese(text) else {
            return text
        }
        return TranslateUtils.translateMeta(text, bookId: bookId)
    }
}
