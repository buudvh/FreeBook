import SwiftUI

/// Gốc SwiftUI của cửa sổ ngăn kéo (`SideDrawerMenuHostingController`). `presentation == nil` ⇒ rỗng (cửa sổ đang ẩn).
///
/// Cửa sổ riêng không thừa hưởng environment của màn như `fullScreenCover` cũ, nên tông tối và màu nhấn trắng của app
/// được gắn lại ở đây. Nội dung các hàng chỉ dùng Binding / giá trị do màn truyền vào, không đọc environment của màn.
struct SideDrawerMenuWindowRoot: View {
    /// Một lượt mở ngăn kéo. `token` đổi mỗi lượt ⇒ panel dựng mới (state trượt vào/ra không sót từ lượt trước).
    struct Presentation {
        let token: UUID
        let title: String
        /// Ảnh chụp màn bên dưới lúc mở — nền nhoè của ngăn kéo (`SideDrawerGlassBackground`); `nil` = không nhoè.
        let backdrop: UIImage?
        /// Gọi lại trong `body` của panel mỗi lần vẽ ⇒ luôn đọc state mới nhất của màn.
        let content: () -> AnyView
        let onAppeared: () -> Void
        /// Ngăn kéo bắt đầu trượt ra; tham số là action của hàng thao tác vừa chọn (`nil` = chỉ đóng).
        let onCloseBegan: ((() -> Void)?) -> Void
        /// Ngăn kéo đã trượt ra hết.
        let onClosed: () -> Void
    }

    let presentation: Presentation?

    var body: some View {
        ZStack {
            if let presentation {
                SideDrawerMenuPanel(
                    title: presentation.title,
                    backdrop: presentation.backdrop,
                    onAppeared: presentation.onAppeared,
                    onCloseBegan: presentation.onCloseBegan,
                    onClosed: presentation.onClosed,
                    content: presentation.content
                )
                .id(presentation.token)
            }
        }
        .environment(\.colorScheme, .dark)
        .tint(.white)
    }
}
