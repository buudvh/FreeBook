import SwiftUI

/// Trang Danh sách của màn nghe ở **chế độ playlist** (`PlaylistPlaybackCoordinator.audioQueue`): "Phát từ playlist <tên>"
/// rồi các mục theo thứ tự người dùng xếp (không theo thứ tự xáo), lấy bản mới nhất của playlist — mục thêm / bớt giữa
/// chừng hiện ngay; playlist đã bị xoá ⇒ bản chụp của hàng đợi. Mục đang phát tô màu nhấn theo **id mục** (cùng chỉ số bài
/// có thể ở hai album). Chạm ⇒ phát mục đó. Không có phần gợi ý của nguồn (playlist không tự phát gợi ý).
struct AudioPlaylistQueueList: View {
    let queue: PlaylistPlaybackQueue
    let isVisible: Bool
    let drag: AudioMinimizeDragState
    let onMinimize: () -> Void

    @AppStorage(RepositoryFilterPolicy.includeNsfwDefaultsKey) private var includeNsfw = false

    private var items: [PlaylistItem] {
        guard let playlist = PlaylistRepository.shared.playlist(id: queue.playlistId) else { return queue.items }
        return PlaylistRepository.visibleItems(of: playlist, includeNsfw: includeNsfw)
    }

    var body: some View {
        let rows = items
        let current = queue.currentItemId
        VStack(alignment: .leading, spacing: 8) {
            header(count: rows.count)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { position, item in
                            AudioPlaylistRow(
                                position: position + 1,
                                title: item.displayTitle(kind: .audio),
                                artist: item.subtitle,
                                isCurrent: item.id == current
                            ) {
                                AppLogger.shared.log("🎵 [AudioPlayerUI] Chọn mục \(position + 1) của playlist «\(queue.name)»")
                                PlaylistPlaybackCoordinator.shared.jumpAudio(to: item.id)
                            }
                            .id(item.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 24)
                }
                .onAppear { scroll(proxy, to: current, animated: false) }
                .onChange(of: isVisible) { _, visible in
                    if visible { scroll(proxy, to: queue.currentItemId, animated: false) }
                }
                .onChange(of: current) { _, newValue in
                    if isVisible { scroll(proxy, to: newValue, animated: true) }
                }
            }
        }
    }

    private func header(count: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Phát từ playlist \(queue.name)")
                .font(.headline)
                .foregroundStyle(Color.white)
                .lineLimit(1)
            Text("\(count) bài\(queue.isShuffled ? " · Xáo trộn" : "")")
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.6))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .audioMinimizeDrag(drag, onCommit: onMinimize)
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
