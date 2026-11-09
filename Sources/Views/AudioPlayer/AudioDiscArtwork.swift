import SwiftUI

/// Mặt đĩa của `AudioSpinningDisc`: bìa album cắt tròn, viền mảnh. Bìa qua `RemoteCoverImage` (không ghi `covers/`);
/// không có bìa ⇒ nốt nhạc trên nền tối. Tách view để mỗi nhịp xoay chỉ đổi `rotationEffect`, không dựng lại ảnh.
struct AudioDiscArtwork: View {
    let coverUrl: String
    let referer: String?

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.08))
            if coverUrl.isEmpty {
                Image(systemName: "music.note")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.5))
            } else {
                RemoteCoverImage(url: coverUrl, referer: referer, placeholderSymbol: "music.note")
                    .clipShape(Circle())
            }
            Circle()
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
        }
        .aspectRatio(1, contentMode: .fit)
        .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 10)
    }
}
