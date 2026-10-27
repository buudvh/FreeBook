import SwiftUI

/// Nút "Mở link lỗi" đứng cạnh "Thử lại" ở các chỗ báo lỗi tải nội dung từ nguồn. Bấm ⇒ gán `presenting = link`;
/// màn gắn `.errorLinkBrowser(link: $presenting, packageId:, onRetry:)` để mở trình duyệt và tự thử lại khi đóng.
/// `link == nil` (không có URL nào để mở) ⇒ không vẽ gì.
///
/// ```swift
/// HStack(spacing: 10) {
///     Button("Thử lại") { retry() }.buttonStyle(.bordered)
///     ErrorLinkButton(link: errorLink, presenting: $openingErrorLink, style: .bordered)
/// }
/// ErrorLinkButton(link: errorLink, presenting: $openingErrorLink, style: .icon)   // dải lỗi gọn / header
/// ```
///
/// Màu nhấn app là trắng ⇒ không dùng `.borderedProminent`; capsule là nền trắng mờ như `ComicReaderView.actionButton`.
struct ErrorLinkButton: View {
    enum Style {
        /// Capsule nền trắng mờ 16%, cao 38pt — khối lỗi giữa màn (comic, video, Reader, Khám phá…).
        case capsule
        /// `.buttonStyle(.bordered)` hệ thống — khi nút "Thử lại" cạnh nó cũng là `.bordered`.
        case bordered
        /// Chỉ icon la bàn (17pt semibold, hitbox 36×36) — dải lỗi gọn (Tìm kiếm, Gợi ý, Bình luận), header, mục lục.
        case icon
    }

    static let title = "Mở link lỗi"
    static let accessibilityText = "Mở link lỗi trong trình duyệt"
    static let systemImage = "safari"

    let link: SourceErrorLink?
    @Binding var presenting: SourceErrorLink?
    var style: Style = .capsule

    init(link: SourceErrorLink?, presenting: Binding<SourceErrorLink?>, style: Style = .capsule) {
        self.link = link
        self._presenting = presenting
        self.style = style
    }

    var body: some View {
        if let link {
            button(opening: link)
                .accessibilityLabel(Self.accessibilityText)
                .accessibilityHint(link.displayText)
        }
    }

    @ViewBuilder
    private func button(opening link: SourceErrorLink) -> some View {
        switch style {
        case .capsule:
            Button { presenting = link } label: {
                Label(Self.title, systemImage: Self.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .frame(height: 38)
                    .background(Color.white.opacity(0.16), in: Capsule())
                    .foregroundStyle(Color.white)
            }
            .buttonStyle(.plain)
        case .bordered:
            Button { presenting = link } label: {
                Label(Self.title, systemImage: Self.systemImage)
            }
            .buttonStyle(.bordered)
        case .icon:
            Button { presenting = link } label: {
                Image(systemName: Self.systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
