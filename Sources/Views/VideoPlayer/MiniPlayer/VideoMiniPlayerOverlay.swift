import SwiftUI

/// Lớp nút phủ trên hình của cửa sổ phim nhỏ (1.3.751): chạm vùng hình ⇒ mở lại màn xem, ‖/▶ giữa, ✕ góc phải trên,
/// vạch tiến độ ở đáy. Đang nạp ⇒ vòng xoay thay ‖/▶; lỗi ⇒ dấu cảnh báo (chạm để mở màn xem xem lỗi). Kéo cửa sổ do
/// `VideoMiniPlayerViewController` (UIKit) lo — cử chỉ kéo huỷ chạm của các nút khi tay bắt đầu di chuyển.
///
/// Màu cố ý trắng trên nền phim (như trình phát), không theo màu nhấn — trừ vạch tiến độ.
struct VideoMiniPlayerOverlay: View {
    let session: VideoPlaybackSession
    let onExpand: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: onExpand)
                .accessibilityLabel("Mở lại trình phát")
                .accessibilityAddTraits(.isButton)
            centerControl
            VStack {
                HStack {
                    Spacer(minLength: 0)
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Color.black.opacity(0.55)))
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Tắt phim")
                }
                Spacer(minLength: 0)
            }
            progressBar
        }
    }

    @ViewBuilder
    private var centerControl: some View {
        switch session.phase {
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .allowsHitTesting(false)
        case .playing, .buffering, .embed:
            if session.isBuffering {
                spinner
            } else {
                Button {
                    session.togglePlayPause()
                } label: {
                    Image(systemName: session.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color.black.opacity(0.55)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(session.isPlaying ? "Tạm dừng" : "Phát")
            }
        case .idle, .loadingEpisodes, .loadingServers, .resolving:
            spinner
        }
    }

    private var spinner: some View {
        ProgressView()
            .tint(.white)
            .allowsHitTesting(false)
    }

    /// Đọc `currentSeconds` (nhịp 0,5 giây) chỉ ở đây.
    private var progressBar: some View {
        VStack {
            Spacer(minLength: 0)
            GeometryReader { geometry in
                let duration = session.durationSeconds
                let fraction = duration > 0 ? min(1, max(0, session.currentSeconds / duration)) : 0
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: geometry.size.width * fraction, height: 3)
            }
            .frame(height: 3)
        }
        .allowsHitTesting(false)
    }
}
