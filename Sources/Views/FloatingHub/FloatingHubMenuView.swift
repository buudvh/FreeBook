import SwiftUI

/// Thẻ menu của nút hub nổi (1.3.524) — chỉ mở khi hub có **từ 2 mục**.
///
/// Vẽ trong **chính cửa sổ hub** (`FloatingHubContainerViewController.menuContainerView`), không phải popover
/// hay sheet của UIKit: không thêm `presentedViewController` thứ hai chen vào luồng sheet Thông báo (luật 25/26
/// trong `rules.md`), và hit-test kiểm soát được hoàn toàn.
///
/// Mỗi hàng là `Button` SwiftUI thật nên VoiceOver kích hoạt được. View **chỉ vẽ**: chọn hàng thì gọi
/// `onSelect`, container lo đóng menu rồi mở mục.
struct FloatingHubMenuView: View {
    static let width: CGFloat = 232

    let items: [FloatingHubItem]
    /// Quyết định glyph chuông của hàng Thông báo (có chấm hay trơn).
    let unreadCount: Int
    let onSelect: (FloatingHubItem.Kind) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Divider()
                        .padding(.leading, 52)
                }
                row(item)
            }
        }
        .frame(width: Self.width)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.22), radius: 14, x: 0, y: 6)
    }

    @ViewBuilder
    private func row(_ item: FloatingHubItem) -> some View {
        Button {
            onSelect(item.kind)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.kind.systemImage(unreadCount: unreadCount))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(item.kind.tint)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.kind.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                    if !item.detail.isEmpty {
                        Text(item.detail)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Mở \(item.kind.title)"))
    }
}
