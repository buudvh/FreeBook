import SwiftUI

/// Ảnh đại diện tròn của người bình luận / trả lời. Không có URL ⇒ hình người xám (như trước khi có avatar);
/// đang tải hoặc tải lỗi ⇒ placeholder hình người của `RemoteCoverImage`.
struct CommentAvatarView: View {
    let url: String
    /// Host sách — `CoverImageLoader` gửi làm `Referer` cho CDN chặn hotlink.
    let referer: String?
    let size: CGFloat

    var body: some View {
        Group {
            if url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .foregroundColor(.secondary.opacity(0.6))
            } else {
                RemoteCoverImage(url: url, referer: referer, contentMode: .fill, placeholderSymbol: "person.fill")
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}
