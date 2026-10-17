import SwiftUI

/// Thẻ menu của nút hub nổi (1.3.524). Từ 1.3.533 chạm hub là **luôn** mở menu, và menu luôn có đủ ba dòng.
///
/// Vẽ trong **chính cửa sổ hub** (`FloatingHubContainerViewController.menuContainerView`), không phải popover
/// hay sheet của UIKit: không thêm `presentedViewController` thứ hai chen vào luồng sheet Thông báo (luật 25/26
/// trong `rules.md`), và hit-test kiểm soát được hoàn toàn.
///
/// ## Không vẽ lại
/// Dòng dựng theo `FloatingHubItem.Kind.allCases` (hằng), danh tính là `kind` — **không** theo mảng `items`.
/// Đổi trạng thái chỉ đổi thuộc tính của dòng đã có (sáng/xám, badge, chữ); không có nhánh `if` nào thêm/bớt
/// dòng, không đổi `.id`. Container gán lại `rootView` của **cùng** hosting controller, SwiftUI chỉ diff thuộc
/// tính. Item thiếu trong `items` (không xảy ra với reader hiện tại) rơi về dòng xám mặc định.
///
/// View **chỉ vẽ**: chạm dòng thì gọi `onSelect`, container lo đóng menu rồi mở mục; hai nút của dòng Video
/// gọi thẳng closure tương ứng và để menu mở.
struct FloatingHubMenuView: View {
    /// Rộng hơn bản 1.3.524 (232) để dòng Video còn chỗ cho tên phim cạnh hai nút phát/dừng và đóng.
    static let width: CGFloat = 260

    let items: [FloatingHubItem]
    let onSelect: (FloatingHubItem.Kind) -> Void
    let onToggleVideoPlayback: () -> Void
    let onStopVideo: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(FloatingHubItem.Kind.allCases, id: \.self) { kind in
                FloatingHubMenuRow(
                    item: item(for: kind),
                    // Đường kẻ trên mọi dòng trừ dòng đầu — hằng theo `kind`, ẩn bằng opacity chứ không bằng `if`.
                    showsSeparator: kind != FloatingHubItem.Kind.allCases.first,
                    onSelect: { onSelect(kind) },
                    onTogglePlayback: onToggleVideoPlayback,
                    onStop: onStopVideo
                )
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

    private func item(for kind: FloatingHubItem.Kind) -> FloatingHubItem {
        items.first(where: { $0.kind == kind }) ?? FloatingHubItem(kind: kind)
    }
}
