import SwiftUI

/// Thanh tua + thời gian hai đầu của màn nghe. View **duy nhất** của trang đọc `currentSeconds` (tick 0,5 s) ⇒ mỗi tick
/// chỉ hàng này vẽ lại. Đang kéo thì hiện giờ của vị trí kéo, nhả tay mới `seek` (session kẹp trong độ dài bài).
struct AudioPlayerSeekRow: View {
    /// Vị trí đang kéo `0…1`; `nil` = không kéo.
    @State private var scrubFraction: Double? = nil

    private var session: AudioPlaybackSession { .shared }

    var body: some View {
        let duration = session.durationSeconds
        let hasDuration = duration.isFinite && duration > 0
        let playedFraction = hasDuration ? session.currentSeconds / duration : 0
        let fraction = scrubFraction ?? playedFraction
        VStack(spacing: 0) {
            VideoSeekBar(
                progress: fraction,
                buffered: 0,
                isEnabled: hasDuration,
                onScrubBegan: { scrubFraction = playedFraction },
                onScrubChanged: { scrubFraction = $0 },
                onScrubEnded: {
                    if let target = scrubFraction, hasDuration {
                        session.seek(to: target * duration)
                    }
                    scrubFraction = nil
                }
            )
            HStack {
                Text(AudioPlayerFormat.time(hasDuration ? fraction * duration : session.currentSeconds))
                Spacer(minLength: 8)
                Text(hasDuration ? AudioPlayerFormat.time(duration) : "--:--")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(Color.white.opacity(0.7))
        }
    }
}
