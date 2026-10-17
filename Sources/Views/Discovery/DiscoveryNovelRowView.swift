import SwiftUI

/// Dòng truyện của các danh sách Khám phá kiểu cũ (tab `home` trong `DiscoveryCategoryTabView`, màn
/// `CategoryNovelsListView`).
///
/// Cùng bố cục với `BookListItemView` kiểu `.discovery` (bìa 50×70, tên in hoa đầu từ + dịch, mô tả 2 dòng, không
/// có mô tả thì hiện tác giả), khác hai điểm:
/// - Bìa tải qua `RemoteCoverImage` kèm Referer (host item → `source` của tiện ích) — nhiều CDN trả 403 khi thiếu.
///   Item tìm kiếm chưa phải sách đã lưu nên không ghi bìa xuống đĩa theo `link` như `BookCoverView`.
/// - Nhãn `tag` của item đè lên đáy bìa.
struct DiscoveryNovelRowView: View {
    let item: ExtensionItemResult
    /// `source` của tiện ích — Referer dự phòng khi item không có `host`.
    let sourceHost: String?

    @AppStorage("isTranslationEnabled") private var isTranslationEnabled = false

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
                .overlay(alignment: .bottom) {
                    if !item.tag.isEmpty {
                        DiscoveryCoverTag(text: translateIfNeeded(item.tag), fontSize: 8)
                            .padding(2)
                    }
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
