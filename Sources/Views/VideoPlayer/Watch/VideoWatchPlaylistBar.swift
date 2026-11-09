import SwiftUI

/// Dải "Playlist <tên> · 3/12" của màn xem, ngay dưới khối tên, khi phim đang mở là mục đang phát của playlist phim
/// (`PlaylistPlaybackCoordinator.videoQueue` — kể cả lúc phim của mục kế đang tải), kèm nút sang mục kế. Không ở chế độ
/// playlist ⇒ không vẽ gì. Kiểu chip đang chọn: chữ màu nhấn, nền nhấn mờ, viền nhấn.
struct VideoWatchPlaylistBar: View {
    let model: VideoWatchModel

    private var coordinator: PlaylistPlaybackCoordinator { .shared }

    var body: some View {
        if let queue = coordinator.videoQueue, !queue.currentBookId.isEmpty, queue.currentBookId == model.bookId {
            HStack(spacing: 8) {
                Image(systemName: queue.kind.symbolName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.tint)
                Text("Playlist \(queue.name) · \(queue.displayPosition)/\(queue.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                if queue.hasNext(wraps: false) {
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
            .padding(.horizontal, 16)
        }
    }
}
