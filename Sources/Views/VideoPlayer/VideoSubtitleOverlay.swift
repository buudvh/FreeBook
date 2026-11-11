import SwiftUI

/// Phụ đề vẽ trong khung phim (trên `AVPlayerLayer`), đẩy lên khi thanh dưới đang hiện để không bị che.
/// Tách riêng để chỉ view này vẽ lại khi dòng phụ đề đổi theo tick.
///
/// Dòng có bản dịch (`currentCueTranslation`) vẽ theo kiểu hiển thị (`MediaCaptionDisplayMode`, chọn ở menu phụ đề của
/// thanh trên): Gốc / Bản dịch / Song ngữ (dòng dịch to, dòng gốc nhỏ mờ bên dưới). Chưa có bản dịch ⇒ nguyên văn.
struct VideoSubtitleOverlay: View {
    let session: VideoPlaybackSession
    let liftsAboveControls: Bool

    @AppStorage(MediaCaptionDisplayMode.videoDefaultsKey) private var displayMode = MediaCaptionDisplayMode.defaultValue

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            if session.subtitlesEnabled, !session.currentCueText.isEmpty {
                let lines = displayMode.lines(original: session.currentCueText, translation: session.currentCueTranslation)
                VStack(spacing: 2) {
                    Text(lines.primary)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    if let secondary = lines.secondary {
                        Text(secondary)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.8), radius: 2)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.55)))
                .padding(.horizontal, 16)
            }
        }
        .padding(.bottom, liftsAboveControls ? 84 : 16)
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.2), value: liftsAboveControls)
    }
}
