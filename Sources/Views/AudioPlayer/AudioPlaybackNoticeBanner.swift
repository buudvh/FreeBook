import SwiftUI

/// Dòng báo ngắn của trình nghe (`AudioPlaybackNotice` — "Tự sang: <tên>" khi tự phát bài gợi ý), cùng kiểu
/// `VideoMiniPlayerNotice` của phim: viên thuốc đen chữ trắng, tự ẩn theo `AudioPlaybackNotice`, không nhận chạm.
/// Gắn ở màn nghe (đầu vùng trang); ngoài màn nghe dòng báo là toast (1.3.808). Chỉ đọc `AudioPlaybackNotice` — không chạm
/// `AudioPlaybackSession` (chạm là dựng `AVPlayer`).
struct AudioPlaybackNoticeBanner: View {
    @ObservedObject private var notice = AudioPlaybackNotice.shared

    var body: some View {
        ZStack {
            if let text = notice.text {
                Text(text)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.black.opacity(0.8)))
                    .padding(.horizontal, 16)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: notice.text)
        .allowsHitTesting(false)
    }
}
