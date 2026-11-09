import SwiftUI

/// Một thẻ playlist trong lưới tab Playlist: bìa ghép (`PlaylistCoverMosaicView`) + tên viết hoa + số mục. Chạm ⇒ trang
/// chi tiết (`PlaylistDetailView`, trang đẩy vào của `NavigationStack` Kệ sách); nhấn giữ ⇒ Đổi tên / Xoá playlist (như
/// thẻ Bộ sưu tập, hai việc nhận bằng closure để tab giữ vai trò mở hộp thoại). Chip "Tất cả" (1.3.810) ⇒ dòng số mục có
/// icon loại (`music.note` / `play.rectangle`) để phân biệt playlist Nhạc với Video.
struct PlaylistGridCardView: View {
    let playlist: Playlist
    /// Mục đang hiện (đã bỏ mục của nguồn NSFW khi công tắc tắt) — bìa và số đếm theo đúng tập này.
    let visibleItems: [PlaylistItem]
    let size: CGFloat
    /// Hiện icon loại trước số mục (chip "Tất cả" trộn hai loại).
    var showsKindIcon: Bool = false
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
                    HStack(spacing: 3) {
                        if showsKindIcon {
                            Image(systemName: playlist.kind.symbolName)
                                .accessibilityLabel(playlist.kind.title)
                        }
                        Text(playlist.kind.countLabel(visibleItems.count))
                            .lineLimit(1)
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
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
