import SwiftUI

/// Thời gian đang xem · thanh tua · thời gian còn lại. View duy nhất của thanh dưới đọc các giá trị đổi theo tick;
/// đang kéo thì hiện giây xem trước (`controller.scrubSeconds`).
struct VideoTimelineRow: View {
    let session: VideoPlaybackSession
    let controller: VideoPlayerController

    var body: some View {
        let duration = session.durationSeconds
        let shown = controller.scrubSeconds ?? session.currentSeconds
        HStack(spacing: 8) {
            Text(Self.format(shown))
                .frame(minWidth: 40, alignment: .leading)
            VideoSeekBar(
                progress: duration > 0 ? shown / duration : 0,
                buffered: duration > 0 ? session.bufferedSeconds / duration : 0,
                isEnabled: duration > 0 && session.hasPlayableItem,
                onScrubBegan: { controller.beginScrub() },
                onScrubChanged: { controller.updateScrub(fraction: $0) },
                onScrubEnded: { controller.endScrub() }
            )
            Text(duration > 0 ? "-" + Self.format(max(0, duration - shown)) : "--:--")
                .frame(minWidth: 44, alignment: .trailing)
        }
        .font(.caption.monospacedDigit().weight(.semibold))
        .foregroundStyle(.white)
    }

    /// `m:ss` hoặc `h:mm:ss`.
    static func format(_ seconds: Double) -> String {
        let total = seconds.isFinite ? max(0, Int(seconds)) : 0
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
