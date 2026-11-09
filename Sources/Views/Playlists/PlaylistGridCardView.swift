import SwiftUI

/// Một thẻ playlist trong lưới tab Playlist: bìa ghép (`PlaylistCoverMosaicView`) + tên viết hoa + số mục. Chạm ⇒ trang
/// chi tiết (`PlaylistDetailView`, trang đẩy vào của `NavigationStack` Kệ sách); nhấn giữ ⇒ Đổi tên / Xoá playlist (như
/// thẻ Bộ sưu tập, hai việc nhận bằng closure để tab giữ vai trò mở hộp thoại).
struct PlaylistGridCardView: View {
    let playlist: Playlist
    /// Mục đang hiện (đã bỏ mục của nguồn NSFW khi công tắc tắt) — bìa và số đếm theo đúng tập này.
    let visibleItems: [PlaylistItem]
    let size: CGFloat
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        NavigationLink(destination: PlaylistDetailView(playlistId: playlist.id)) {
            VStack(alignment: .leading, spacing: 6) {
                PlaylistCoverMosaicView(items: visibleItems, kind: playlist.kind, size: size)

                VStack(alignment: .leading, spacing: 2) {
                    ZStack(alignment: .topLeading) {
                        CollectionGridCardView.titleReserve
                        Text(playlist.name)
                            .font(CollectionGridCardView.titleFont)
                            .textCase(.uppercase)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    Text(playlist.kind.countLabel(visibleItems.count))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .frame(width: size, alignment: .topLeading)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: onRename) {
                Label("Đổi tên", systemImage: "pencil")
            }
            Button(role: .destructive, action: onDelete) {
                Label("Xoá playlist", systemImage: "trash")
            }
        }
    }
}
