import SwiftUI

/// Phụ đề vẽ trong khung phim (trên `AVPlayerLayer`), đẩy lên khi thanh dưới đang hiện để không bị che.
/// Tách riêng để chỉ view này vẽ lại khi dòng phụ đề đổi theo tick.
struct VideoSubtitleOverlay: View {
    let session: VideoPlaybackSession
    let liftsAboveControls: Bool

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            if session.subtitlesEnabled, !session.currentCueText.isEmpty {
                Text(session.currentCueText)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
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
