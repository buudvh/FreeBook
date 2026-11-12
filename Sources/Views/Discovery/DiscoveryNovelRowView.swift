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
    /// Chữ Trung **theo nguồn** (phồn → giản + QT, Nguồn ⇒ Tất cả; bộ dịch tiện ích ⇒ tên / mô tả / nhãn hiện bản QT
    /// trước rồi thay bằng bản tiện ích) — màn cha giữ và cập nhật; không đọc công tắc dịch toàn app.
    let textStore: ExtensionTextTranslationStore
    /// Cỡ dòng của kiểu Danh sách (`BookListLayout.rowSize`); nấc mặc định giữ đúng bố cục cũ.
    var rowSize: BookListRowSize = .default

    var body: some View {
        HStack(spacing: 12) {
            Color(.secondarySystemBackground)
                .frame(width: rowSize.coverWidth, height: rowSize.coverHeight)
                .overlay {
                    RemoteCoverImage(
                        url: item.cover,
                        referer: ExtensionHostResolver.nonEmpty(item.host) ?? sourceHost,
                        contentMode: .fill
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(alignment: .bottomLeading) {
                    CoverTagBadge(tag: textStore.text(item.tag, kind: .meta))
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(DisplayTextFormatter.titleCase(displayedName))
                    .font(rowSize.font(.system(size: 14.5, weight: .semibold), base: 14.5, weight: .semibold))
                    .lineLimit(rowSize.titleLineLimit)

                if !item.description.isEmpty {
                    Text(textStore.text(item.description.cleanHTML(), kind: .meta))
                        .font(rowSize.font(.caption2, base: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(rowSize.isCompact ? 1 : 2)
                } else if !item.author.isEmpty {
                    Text(DisplayTextFormatter.titleCase(ChineseTextPipeline.author(item.author, textStore.options))) // giữ phiên âm
                        .font(rowSize.font(.system(size: 13), base: 13))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
    }

    /// Tên: bộ dịch tiện ích ⇒ bản tiện ích (QT trước); QT ⇒ tra từ điển riêng theo `link` như trước.
    private var displayedName: String {
        guard textStore.request == nil else { return textStore.text(item.name, kind: .meta) }
        var options = textStore.options
        options.dictionaryBookId = item.link
        return ChineseTextPipeline.meta(item.name, options)
    }
}
