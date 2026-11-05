import SwiftUI

/// Lưới chọn **3 cột** của trình phát (Khung hình / Server / Chất lượng trong ngăn kéo `⋯`; màn xem dùng lại cho lưới
/// Server). Ô đang chọn cùng kiểu chip đang chọn của app (`ExtensionKindFilterBar`): chữ màu nhấn, nền nhấn mờ ~18%, viền
/// ~60% — **không** tô nền nhấn đặc (luật `WHITE_TINT_FILL`). Ô thường nền xám tối. Tên dài cắt "…" một dòng.
///
/// Bấm ô ⇒ áp dụng ngay; trong ngăn kéo thì ngăn kéo **vẫn mở** và được vẽ lại theo state mới (như `SideDrawerOptionRow`
/// — ngăn kéo ở cửa sổ riêng). Ngoài ngăn kéo `refreshContent()` không làm gì.
struct VideoPlayerOptionGrid: View {
    struct Option: Identifiable {
        let id: String
        let title: String
        var systemImage: String? = nil
        let isSelected: Bool
        let action: () -> Void
    }

    let options: [Option]
    /// Lề ngang của lưới — ngăn kéo dùng cùng lề 16 của các hàng.
    var horizontalPadding: CGFloat = 16

    @Environment(\.sideDrawerMenuDismiss) private var drawer

    private static let spacing: CGFloat = 8
    private static let cellHeight: CGFloat = 38
    private static let cornerRadius: CGFloat = 10
    private let columns = Array(repeating: GridItem(.flexible(), spacing: Self.spacing), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: Self.spacing) {
            ForEach(options) { option in
                cell(option)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, 4)
    }

    private func cell(_ option: Option) -> some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        return Button {
            option.action()
            drawer.refreshContent()
        } label: {
            HStack(spacing: 4) {
                if let systemImage = option.systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(option.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(option.isSelected ? Color.accentColor : Color.white)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: Self.cellHeight)
            .background(shape.fill(option.isSelected ? Color.accentColor.opacity(0.18) : Color.white.opacity(0.1)))
            .overlay(shape.strokeBorder(option.isSelected ? Color.accentColor.opacity(0.6) : Color.white.opacity(0.12), lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(option.isSelected ? .isSelected : [])
    }
}
