import SwiftUI

/// Hàng phụ dưới cụm nút của trang Đĩa: tốc độ đang dùng (bấm mở menu 0,5–2×), nút sang trang Danh sách, nút sang trang
/// Lời.
struct AudioSecondaryControls: View {
    let onShowPage: (AudioPlayerPage) -> Void

    private var session: AudioPlaybackSession { .shared }

    var body: some View {
        HStack(spacing: 4) {
            rateMenu
            Spacer(minLength: 8)
            pageButton(systemImage: "list.bullet", label: "Danh sách phát", page: .playlist)
            pageButton(systemImage: "quote.bubble", label: "Lời bài hát", page: .lyrics)
        }
        .buttonStyle(.plain)
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
