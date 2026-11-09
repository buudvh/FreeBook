import SwiftUI

/// Khối lỗi của trang Đĩa khi bài / album không phát được (`AudioPlaybackSession.Phase.failed`): câu lỗi, dòng URL xám,
/// "Thử lại" (`retry()`) và "Mở link lỗi" khi có link (màn gắn `.errorLinkBrowser` với cùng binding).
struct AudioPlaybackErrorView: View {
    let message: String
    let link: SourceErrorLink?
    @Binding var openingErrorLink: SourceErrorLink?

    var body: some View {
        VStack(spacing: 8) {
            Text(message)
                .font(.footnote)
                .foregroundStyle(Color.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .lineLimit(3)
            ErrorLinkCaption(link: link)
            HStack(spacing: 10) {
                Button {
                    AppLogger.shared.log("🎵 [AudioPlayerUI] Bấm Thử lại ở màn nghe")
                    AudioPlaybackSession.shared.retry()
                } label: {
                    Label("Thử lại", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .frame(height: 38)
                        .background(Color.white.opacity(0.16), in: Capsule())
                        .foregroundStyle(Color.white)
                }
                .buttonStyle(.plain)
                ErrorLinkButton(link: link, presenting: $openingErrorLink)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
