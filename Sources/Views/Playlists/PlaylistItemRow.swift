import SwiftUI

/// Một hàng của trang chi tiết playlist: bìa (vuông nhỏ cho nhạc, ngang 16:9 cho phim), dòng 1 tên bài / tập `.headline`,
/// dòng 2 nghệ sĩ / tên phim `.subheadline` màu phụ. Thuần trình bày — xoá / đổi thứ tự do `List` của trang lo.
struct PlaylistItemRow: View {
    let item: PlaylistItem
    let kind: PlaylistKind
    /// Số thứ tự hiển thị (vị trí trong danh sách đang hiện, từ 1).
    let position: Int

    private var coverSize: CGSize {
        switch kind {
        case .audio: return CGSize(width: 52, height: 52)
        case .video: return CGSize(width: 92, height: 52)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("\(position)")
                .font(.subheadline.monospacedDigit())
                .foregroundColor(.secondary)
                .frame(minWidth: 22, alignment: .trailing)
            RemoteCoverImage(url: item.coverUrl, referer: item.coverReferer, placeholderSymbol: kind.symbolName)
                .frame(width: coverSize.width, height: coverSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle(kind: kind))
                    .font(.headline)
                    .lineLimit(2)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}
