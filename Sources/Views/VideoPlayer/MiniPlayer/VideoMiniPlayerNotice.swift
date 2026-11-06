import SwiftUI

/// Dòng báo ngắn **dưới** cửa sổ phim nhỏ (1.3.751) — `session.playbackNotice` (tự sang phim đề xuất "Tự sang: <tên>",
/// tự đổi link vì mất tiếng). Tự ẩn theo session; không nhận chạm.
struct VideoMiniPlayerNotice: View {
    let session: VideoPlaybackSession

    var body: some View {
        VStack {
            if let notice = session.playbackNotice {
                Text(notice)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.black.opacity(0.8)))
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.25), value: session.playbackNotice)
        .allowsHitTesting(false)
    }
}
