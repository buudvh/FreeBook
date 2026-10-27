import SwiftUI

/// Khối lỗi mục lục khi **chưa có chương nào** — danh sách hàng (`BookDetailTOCView`) và lưới tập video
/// (`BookDetailVideoTOCGrid`) dùng chung: câu lỗi đỏ + dòng URL xám + `[Tải lại mục lục] [Mở link lỗi]`.
/// Màn cha (`BookDetailView`) gắn `.errorLinkBrowser` cho `openingLink`, thử lại = `onReload`.
struct BookDetailTOCErrorBlock: View {
    let message: String
    let link: SourceErrorLink?
    @Binding var openingLink: SourceErrorLink?
    let onReload: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text(message)
                .font(.subheadline)
                .foregroundColor(.red)
                .multilineTextAlignment(.center)
            ErrorLinkCaption(link: link)
            HStack(spacing: 10) {
                Button("Tải lại mục lục", action: onReload)
                    .buttonStyle(.bordered)
                ErrorLinkButton(link: link, presenting: $openingLink, style: .bordered)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
    }
}
