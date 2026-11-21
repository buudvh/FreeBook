import SwiftUI

/// Dải "Playlist <tên> · 3/12" của màn xem, ngay dưới khối tên, khi phim đang mở là mục đang phát của playlist phim
/// (`PlaylistPlaybackCoordinator.videoQueue` — kể cả lúc phim của mục kế đang tải), kèm nút sang mục kế. Không ở chế độ
/// playlist ⇒ không vẽ gì. Kiểu chip đang chọn: chữ màu nhấn, nền nhấn mờ, viền nhấn.
///
/// Chạm dải (trừ nút ⏭) ⇒ xổ / thu danh sách mục ngay bên dưới (`VideoWatchPlaylistQueueList`, bìa ngang 16:9); mũi ⌄
/// lật lên khi đang xổ. Trạng thái xổ nằm ở view này nên giữ qua lượt đổi phim tại chỗ của màn (chạm hàng sang phim khác).
struct VideoWatchPlaylistBar: View {
    let model: VideoWatchModel

    @State private var isExpanded = false

    private var coordinator: PlaylistPlaybackCoordinator { .shared }

    var body: some View {
        if let queue = coordinator.videoQueue, !queue.currentBookId.isEmpty, queue.currentBookId == model.bookId {
            VStack(spacing: 8) {
                bar(queue)
                if isExpanded {
                    VideoWatchPlaylistQueueList(queue: queue)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func bar(_ queue: PlaylistPlaybackQueue) -> some View {
        let hasNext = queue.hasNext(wraps: false)
        return HStack(spacing: 0) {
            Button {
                AppLogger.shared.log("🎶 [VideoWatch] \(isExpanded ? "Thu" : "Xổ") danh sách playlist «\(queue.name)»")
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: queue.kind.symbolName)
                        .font(.system(size: 15, weight: .semibold))
                    Text("Playlist \(queue.name) · \(queue.displayPosition)/\(queue.count)")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .padding(.trailing, hasNext ? 0 : 8)
                }
                .foregroundStyle(.tint)
                .frame(minHeight: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Playlist \(queue.name), mục \(queue.displayPosition) trên \(queue.count)")
            .accessibilityHint(isExpanded ? "Thu danh sách" : "Xổ danh sách mục của playlist")
            if hasNext {
                Button {
                    AppLogger.shared.log("⏭️ [VideoWatch] Bấm sang mục kế của playlist")
                    coordinator.videoNext(in: VideoPlaybackSession.shared)
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.tint)
                        .frame(width: 36, height: 38)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mục kế trong playlist")
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(minHeight: 40)
        .background(Color.accentColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.accentColor.opacity(0.6), lineWidth: 1)
        )
    }
}
