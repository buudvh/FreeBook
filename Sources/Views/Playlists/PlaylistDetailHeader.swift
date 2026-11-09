import SwiftUI

/// Đầu trang chi tiết playlist: bìa ghép lớn, tên, "Nhạc · 12 bài" (+ số mục đang ẩn vì NSFW). Hàng nút phát của phần
/// phát playlist nằm ngay **dưới** khối này trong `PlaylistDetailView` (khối này chỉ trình bày).
struct PlaylistDetailHeader: View {
    let playlist: Playlist
    /// Mục đang hiện (đã bỏ mục của nguồn NSFW khi công tắc tắt).
    let visibleItems: [PlaylistItem]

    private static let coverSize: CGFloat = 168

    private var hiddenCount: Int { playlist.items.count - visibleItems.count }

    var body: some View {
        VStack(spacing: 10) {
            PlaylistCoverMosaicView(items: visibleItems, kind: playlist.kind, size: Self.coverSize, cornerRadius: 14)
            Text(playlist.name)
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
                .lineLimit(3)
            HStack(spacing: 4) {
                Image(systemName: playlist.kind.symbolName)
                Text("\(playlist.kind.title) · \(playlist.kind.countLabel(visibleItems.count))")
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
            if hiddenCount > 0 {
                Text("Đang ẩn \(hiddenCount) mục của nguồn NSFW")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}
