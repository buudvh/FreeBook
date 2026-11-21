import SwiftUI

/// Danh sách xổ dưới dải playlist của màn xem (`VideoWatchPlaylistBar`): các mục của playlist phim theo **thứ tự người dùng
/// xếp** (không theo thứ tự xáo — như trang Danh sách của màn nghe), lấy bản mới nhất của playlist (mục thêm / bớt giữa
/// chừng hiện ngay, NSFW ẩn theo công tắc chung); playlist đã bị xoá ⇒ bản chụp của hàng đợi.
///
/// Hàng là `PlaylistItemRow` (bìa ngang 16:9 như trang chi tiết playlist; màn xem ép nền tối nên chữ trắng), mục đang phát
/// tô màu nhấn theo **id mục**. Từ `visibleRowLimit` mục trở xuống hiện hết; dài hơn ⇒ khung cao `scrollHeight` cuộn bên
/// trong, xổ ra / đổi mục thì cuộn tới mục đang phát. Chạm ⇒ `PlaylistPlaybackCoordinator.jumpVideo(to:)`.
struct VideoWatchPlaylistQueueList: View {
    let queue: PlaylistPlaybackQueue

    @AppStorage(RepositoryFilterPolicy.includeNsfwDefaultsKey) private var includeNsfw = false

    /// Số hàng hiện hết không cần cuộn.
    private static let visibleRowLimit = 4
    /// ≈ 4,5 hàng (hàng 68 pt) — hàng dưới cùng lộ một nửa để biết còn cuộn được.
    private static let scrollHeight: CGFloat = 310

    private var items: [PlaylistItem] {
        guard let playlist = PlaylistRepository.shared.playlist(id: queue.playlistId) else { return queue.items }
        return PlaylistRepository.visibleItems(of: playlist, includeNsfw: includeNsfw)
    }

    var body: some View {
        let rows = items
        let current = queue.currentItemId
        Group {
            if rows.count <= Self.visibleRowLimit {
                rowStack(rows, current: current)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        rowStack(rows, current: current)
                    }
                    .frame(height: Self.scrollHeight)
                    .onAppear { scroll(proxy, to: current, animated: false) }
                    .onChange(of: current) { _, newValue in scroll(proxy, to: newValue, animated: true) }
                }
            }
        }
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func rowStack(_ rows: [PlaylistItem], current: UUID?) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { position, item in
                VStack(spacing: 0) {
                    if position > 0 {
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 0.5)
                    }
                    Button {
                        AppLogger.shared.log("🎶 [VideoWatch] Chọn mục \(position + 1) của playlist «\(queue.name)»")
                        PlaylistPlaybackCoordinator.shared.jumpVideo(to: item.id)
                    } label: {
                        PlaylistItemRow(item: item, kind: .video, position: position + 1, isCurrent: item.id == current)
                            .padding(.vertical, 8)
                            .padding(.leading, 8)
                            .padding(.trailing, 12)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Phát mục này")
                }
                .id(item.id)
            }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy, to id: UUID?, animated: Bool) {
        guard let id else { return }
        if animated {
            withAnimation(.easeInOut(duration: 0.3)) {
                proxy.scrollTo(id, anchor: .center)
            }
        } else {
            proxy.scrollTo(id, anchor: .center)
        }
    }
}
