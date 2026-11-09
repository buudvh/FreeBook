import SwiftUI

/// Hàng nút điều khiển của màn nghe. `.full` (trang Đĩa): Xáo · ⏮ · ⏯ · ⏭ · Lặp; `.compact` (cuối trang Lời): ⏮ · ⏯ · ⏭.
/// Xáo / Lặp tô màu nhấn khi đang bật (Lặp: khác `off`, icon theo `AudioRepeatMode.symbolName`). Nút ⏯ tròn viền trắng;
/// đang nạp / đệm ⇒ vòng xoay thay icon (bấm vẫn dừng / phát như thường).
struct AudioTransportControls: View {
    enum Style {
        case full
        case compact
    }

    let style: Style

    private var session: AudioPlaybackSession { .shared }

    private var playSize: CGFloat { style == .full ? 68 : 54 }
    private var skipIconSize: CGFloat { style == .full ? 26 : 22 }

    var body: some View {
        HStack(spacing: 0) {
            if style == .full {
                modeButton(
                    systemImage: "shuffle",
                    isOn: session.isShuffled,
                    label: session.isShuffled ? "Tắt xáo trộn" : "Bật xáo trộn"
                ) { session.toggleShuffle() }
                Spacer(minLength: 0)
            }
            skipButton(systemImage: "backward.end.fill", label: "Bài trước", isEnabled: !session.tracks.isEmpty) {
                session.previous()
            }
            Spacer(minLength: 0)
            playPauseButton
            Spacer(minLength: 0)
            skipButton(systemImage: "forward.end.fill", label: "Bài sau", isEnabled: session.hasNextTrack) {
                session.next()
            }
            if style == .full {
                Spacer(minLength: 0)
                modeButton(
                    systemImage: session.repeatMode.symbolName,
                    isOn: session.repeatMode != .off,
                    label: session.repeatMode.title
                ) { session.cycleRepeatMode() }
            }
        }
        .padding(.horizontal, style == .full ? 0 : 36)
        .buttonStyle(.plain)
    }

    private var isBusy: Bool {
        session.phase == .loading || session.phase == .buffering
    }

    private var playPauseButton: some View {
        Button {
            session.togglePlayPause()
        } label: {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
                if isBusy {
                    ProgressView()
                        .tint(.white)
                        .controlSize(style == .full ? .large : .regular)
                } else {
                    Image(systemName: session.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: style == .full ? 28 : 22, weight: .semibold))
                        .foregroundStyle(Color.white)
                        // Tam giác "play" lệch tâm thị giác sang trái.
                        .offset(x: session.isPlaying ? 0 : 2)
                }
            }
            .frame(width: playSize, height: playSize)
            .contentShape(Circle())
        }
        .accessibilityLabel(session.isPlaying ? "Tạm dừng" : "Phát")
    }

    private func skipButton(systemImage: String, label: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: skipIconSize, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 52, height: 52)
                .contentShape(Rectangle())
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .accessibilityLabel(label)
    }

    private func modeButton(systemImage: String, isOn: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.white.opacity(0.75)))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }
}
