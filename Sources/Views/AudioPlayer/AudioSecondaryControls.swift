import SwiftUI

/// Hàng phụ dưới cụm nút của trang Đĩa: tốc độ đang dùng (bấm mở menu 0,5–2×), ⏱ hẹn giờ tắt (sheet `MediaSleepTimerSheet`;
/// đang hẹn ⇒ viên thuốc màu nhấn kèm thời gian còn lại như badge TTS), nút thêm bài đang phát vào playlist
/// (`PlaylistAddSheet`), nút sang trang Danh sách, nút sang trang Lời.
struct AudioSecondaryControls: View {
    let onShowPage: (AudioPlayerPage) -> Void

    @State private var showingSleepTimer = false
    @State private var playlistRequest: PlaylistAddRequest? = nil

    private var session: AudioPlaybackSession { .shared }

    var body: some View {
        HStack(spacing: 4) {
            rateMenu
            sleepTimerButton
            playlistButton
            Spacer(minLength: 8)
            pageButton(systemImage: "list.bullet", label: "Danh sách phát", page: .playlist)
            pageButton(systemImage: "quote.bubble", label: "Lời bài hát", page: .lyrics)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingSleepTimer) {
            Group {
                MediaSleepTimerSheet(timer: session.sleepTimer)
            }
            .appGlassSheet()
        }
        .sheet(item: $playlistRequest) { request in
            Group {
                PlaylistAddSheet(request: request)
            }
            .appGlassSheet()
        }
    }

    /// Thêm bài đang phát vào playlist — ẩn khi chưa có bài (đang nạp mục lục).
    @ViewBuilder
    private var playlistButton: some View {
        if session.currentTrackIndex != nil {
            Button {
                playlistRequest = PlaylistItemMapper.addRequestForCurrentTrack(of: session)
            } label: {
                Image(systemName: "text.badge.plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Thêm bài đang phát vào playlist")
        }
    }

    /// Chưa hẹn ⇒ chỉ icon; đang hẹn ⇒ viên thuốc như ô tốc độ, chữ + nền nhấn mờ. Thời gian còn lại nằm trong view lá
    /// (`MediaSleepTimerCountdownText`) để hàng này không vẽ lại mỗi giây.
    private var sleepTimerButton: some View {
        let timer = session.sleepTimer
        return Button {
            showingSleepTimer = true
        } label: {
            Group {
                if timer.isActive {
                    HStack(spacing: 4) {
                        Image(systemName: "timer")
                            .font(.system(size: 13, weight: .semibold))
                        MediaSleepTimerCountdownText(timer: timer)
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(Color.accentColor.opacity(0.18), in: Capsule())
                } else {
                    Image(systemName: "timer")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .frame(width: 44, height: 32)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(timer.modeSummary.map { "Hẹn giờ tắt: \($0)" } ?? "Hẹn giờ tắt")
    }

    private var rateMenu: some View {
        Menu {
            ForEach(AudioPlaybackSession.playbackRates, id: \.self) { rate in
                Button {
                    session.setPlaybackRate(rate)
                } label: {
                    if rate == session.playbackRate {
                        Label(AudioPlayerFormat.rate(rate), systemImage: "checkmark")
                    } else {
                        Text(AudioPlayerFormat.rate(rate))
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 13, weight: .semibold))
                Text(AudioPlayerFormat.rate(session.playbackRate))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
            }
            .foregroundStyle(Color.white.opacity(0.85))
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Color.white.opacity(0.12), in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Tốc độ phát \(AudioPlayerFormat.rate(session.playbackRate))")
    }

    private func pageButton(systemImage: String, label: String, page: AudioPlayerPage) -> some View {
        Button {
            onShowPage(page)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.85))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }
}
