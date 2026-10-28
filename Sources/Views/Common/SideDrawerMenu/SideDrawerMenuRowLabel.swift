import SwiftUI

/// Bố cục chung của một hàng ngăn kéo: icon cột trái rộng cố định, tiêu đề **một dòng** (co chữ tới 80% khi quá dài,
/// không xuống hàng), phần phụ bên phải (chữ phụ, công tắc…), cao ≥ 46pt, vạch mảnh ở đáy thẳng cột chữ.
///
/// Tự làm mờ khi bị `.disabled` — nút kiểu tuỳ biến không tự mờ như `Menu` của hệ thống.
struct SideDrawerMenuRowLabel<Trailing: View>: View {
    let icon: SideDrawerMenuIcon
    let title: String
    let tint: Color
    @ViewBuilder let trailing: () -> Trailing

    @Environment(\.isEnabled) private var isEnabled

    private static var iconColumnWidth: CGFloat { 26 }
    private static var horizontalPadding: CGFloat { 16 }
    private static var spacing: CGFloat { 12 }

    var body: some View {
        HStack(spacing: Self.spacing) {
            icon.image(size: 17)
                .foregroundStyle(tint)
                .frame(width: Self.iconColumnWidth)
                .accessibilityHidden(true)

            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)

            trailing()
        }
        .padding(.horizontal, Self.horizontalPadding)
        .frame(minHeight: 46)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5)
                .padding(.leading, Self.horizontalPadding + Self.iconColumnWidth + Self.spacing)
                .accessibilityHidden(true)
        }
        .opacity(isEnabled ? 1 : 0.4)
        .contentShape(Rectangle())
    }
}
