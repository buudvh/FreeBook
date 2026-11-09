import SwiftUI

/// Thanh bung của kiểu **Thanh nghe nhạc** (1.3.796) — cùng dáng thanh phát mini nghe nhạc (`MiniPlayerBarChrome`: 56 pt,
/// bo 14, nền kính theo độ trong suốt đã cài, vạch tiến độ chương ở mép trên).
///
/// Bố cục: đĩa bìa 40 pt xoay (góc chung với kiểu Đĩa nổi) · tên truyện / "Ch. N · tên chương" + viên phút hẹn giờ còn lại
/// · ⏯ · ⏭ (đoạn kế) · ⏱ (sheet Hẹn giờ, Cài đặt TTS mở từ đó) · ✕ (dừng) · vạch mảnh · ô » hẹp sát mép phải (thu gọn).
/// Chạm bìa hoặc chữ ⇒ mở chương đang đọc.
struct TTSWidgetBarView: View {
    let model: TTSWidgetBarViewModel
    @ObservedObject var info: TTSWidgetBarInfoReader
    let snapshot: TTSWidgetSnapshot
    let coverImage: UIImage?
    let rotationState: CoverRotationState
    let isCoverRotating: Bool

    private static let controlWidth: CGFloat = 36

    var body: some View {
        HStack(spacing: 2) {
            Button(action: { model.openCurrentChapter() }) {
                HStack(spacing: 10) {
                    TTSCoverView(
                        image: coverImage,
                        size: 40,
                        rotationState: rotationState,
                        isRotating: isCoverRotating
                    )
                    titles
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Mở chương đang đọc")

            MiniPlayerControlButton(
                systemImage: snapshot.isPlaying ? "pause.fill" : "play.fill",
                label: snapshot.isPlaying ? "Tạm dừng" : "Phát tiếp",
                width: Self.controlWidth,
                action: { model.togglePlayback() }
            )
            MiniPlayerControlButton(
                systemImage: "forward.fill",
                label: "Tua tới đoạn tiếp theo",
                width: Self.controlWidth,
                action: { model.skipForward() }
            )
            MiniPlayerControlButton(
                systemImage: "timer",
                label: "Hẹn giờ và cài đặt",
                width: Self.controlWidth,
                action: { model.presentTimerSheet() }
            )
            MiniPlayerControlButton(
                systemImage: "xmark",
                label: "Dừng đọc",
                width: Self.controlWidth,
                action: { model.stop() }
            )
            collapseCell
        }
        .miniPlayerBarChrome(trailingPadding: 0) {
            TTSWidgetBarProgressLine()
        }
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(info.bookTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(info.chapterLine.isEmpty ? " " : info.chapterLine)
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.65))
                    .lineLimit(1)
                if snapshot.timerMode != .off {
                    timerBadge
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Phút hẹn giờ còn lại (cùng chữ với viên hẹn giờ trên capsule của kiểu Đĩa nổi), không bao giờ bị cắt.
    private var timerBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "timer")
                .font(.system(size: 9, weight: .bold))
            Text(snapshot.sleepTimerBadgeText)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.white.opacity(0.18)))
        .fixedSize()
        .layoutPriority(1)
        .accessibilityLabel("Hẹn giờ còn \(snapshot.sleepTimerBadgeText)")
    }

    /// Ô » hẹp sát mép phải, ngăn với cụm nút bằng vạch mảnh.
    private var collapseCell: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.white.opacity(0.2))
                .frame(width: 0.75, height: 28)
            Button(action: { model.collapseByUser() }) {
                Image(systemName: "chevron.right.2")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .frame(width: 28, height: MiniPlayerBarChrome.height)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Thu gọn")
        }
    }
}
