import SwiftUI

/// Một dòng ngang (ảnh nhỏ + tên + mô tả) của section `list`, và của `ranking` khi có `rank`.
///
/// Nguồn âm thanh / phim (`context.playlist`) + item mở chi tiết được ⇒ ⋮ ở cuối dòng (1.3.810, `PlaylistListItemMenu`) —
/// nút anh em với nút mở dòng, không nằm trong `label` của nó.
struct ExploreListRow: View {
    let item: ExploreItem
    let shape: ExploreSection.Shape
    let context: ExploreRenderContext
    /// Thứ hạng (bắt đầu từ 1) — chỉ section `ranking` truyền.
    var rank: Int? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            Button {
                context.onSelect(item)
            } label: {
                content
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let playlist = context.playlist, let listItem = context.playlistItem(for: item) {
                PlaylistListItemMenu(item: listItem, context: playlist, style: .row)
            }
        }
    }

    private var content: some View {
        // `list` và `ranking` dùng chung một nấc cỡ: ảnh nhỏ + chữ tên/mô tả (nấc mặc định giữ nguyên font cũ).
        let size = context.sizes.list
        return HStack(alignment: .center, spacing: 12) {
            if let rank {
                Text("\(rank)")
                    .font(.system(size: rank < 100 ? 24 : 18, weight: .heavy, design: .rounded))
                    .foregroundColor(rankColor(rank))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: 34)
            }

            ExploreCoverView(
                url: item.cover,
                referer: context.referer(for: item),
                shape: shape,
                tag: context.display(item.tag),
                tagFontSize: 8
            )
            .frame(width: shape.scaledThumbnailWidth(size))

            VStack(alignment: .leading, spacing: 4) {
                Text(context.display(item.name))
                    .font(size.font(.system(size: 14.5, weight: .semibold), base: 14.5, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)

                if !item.description.isEmpty {
                    Text(context.display(item.description.cleanHTML()))
                        .font(size.font(.caption, base: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Ba hạng đầu nổi bật (vàng / bạc / đồng), còn lại màu phụ.
    private func rankColor(_ rank: Int) -> Color {
        switch rank {
        case 1: return Color(red: 1.0, green: 0.76, blue: 0.2)
        case 2: return Color(red: 0.78, green: 0.8, blue: 0.84)
        case 3: return Color(red: 0.85, green: 0.55, blue: 0.3)
        default: return .secondary
        }
    }
}
