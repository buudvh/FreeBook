import SwiftUI

/// Thẻ item dạng đứng (bìa + tên + mô tả ngắn) dùng cho section `grid` và `horizontal_list`.
/// Bề rộng do nơi dùng đặt (cột lưới hoặc `.frame(width:)`); bìa theo `shape` của section.
///
/// Nguồn âm thanh / phim (`context.playlist`) + item mở chi tiết được ⇒ ⋮ nhỏ cạnh tên dưới bìa (1.3.810,
/// `PlaylistListItemMenu`): thẻ tách thành nút bìa + hàng [nút chữ | ⋮] như `VideoWatchSuggestCard` để ⋮ không nằm trong
/// `label` của nút mở. Thẻ tròn (thường là nghệ sĩ / danh mục) không có ⋮.
struct ExploreItemCard: View {
    let item: ExploreItem
    let shape: ExploreSection.Shape
    let context: ExploreRenderContext

    private var isCircle: Bool { shape == .circle }

    var body: some View {
        if !isCircle, let playlist = context.playlist, let listItem = context.playlistItem(for: item) {
            VStack(alignment: .leading, spacing: 5) {
                Button {
                    context.onSelect(item)
                } label: {
                    cover
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                HStack(alignment: .top, spacing: 2) {
                    Button {
                        context.onSelect(item)
                    } label: {
                        texts
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    PlaylistListItemMenu(item: listItem, context: playlist, style: .card)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            Button {
                context.onSelect(item)
            } label: {
                VStack(alignment: isCircle ? .center : .leading, spacing: 5) {
                    cover
                    texts
                }
                .frame(maxWidth: .infinity, alignment: isCircle ? .top : .topLeading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var cover: some View {
        ExploreCoverView(
            url: item.cover,
            referer: context.referer(for: item),
            shape: shape,
            tag: context.display(item.tag)
        )
    }

    private var texts: some View {
        VStack(alignment: isCircle ? .center : .leading, spacing: 5) {
            Text(context.display(item.name))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(isCircle ? .center : .leading)

            if !isCircle, !item.description.isEmpty {
                Text(context.display(item.description.cleanHTML()))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
