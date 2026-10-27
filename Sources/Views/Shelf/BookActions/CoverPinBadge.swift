import SwiftUI

/// Dấu ghim ở **góc trên trái bìa** của truyện đang ghim đầu kệ: pin cam xoay chéo trên nền tròn tối.
///
/// Dùng chung cho dòng danh sách Kệ (`ShelfBookRowView`), ô lưới (`ShelfBookGridCardView`) và sheet nhấn giữ
/// (`BookActionSheet`) để mọi nơi trông như nhau — thay cho ghim nằm bên phải dòng / ghim đứng thẳng / dòng chữ
/// "Đang ghim đầu kệ" trước 1.3.607. Chỉ là dấu hiệu: không bắt chạm, ghim/bỏ ghim vẫn qua sheet nhấn giữ.
///
/// Cũng dùng cho nút NE/VP, R/C đang ghim mặc định ở panel Dịch (`ReaderDefinitionOverlayView+Rows`, nghiêng 20°).
struct CoverPinBadge: View {
    /// Đường kính nền tròn; icon ≈ 55% đường kính.
    var diameter: CGFloat = 20
    /// Góc nghiêng của ghim (độ). Kệ giữ 35°.
    var angle: Double = 35
    /// Nhãn trợ năng — mặc định là nghĩa ở Kệ.
    var accessibilityText: String = "Đang ghim đầu kệ"

    /// Cỡ theo bìa của dòng danh sách (bìa rộng 32…80pt theo `BookListRowSize`): không to quá bìa nhỏ.
    static func diameter(forCoverWidth width: CGFloat) -> CGFloat {
        min(max(width * 0.36, 14), 20)
    }

    var body: some View {
        Image(systemName: "pin.fill")
            .font(.system(size: diameter * 0.55, weight: .semibold))
            .foregroundColor(.orange)
            .rotationEffect(.degrees(angle))
            .frame(width: diameter, height: diameter)
            .background(Color.black.opacity(0.6), in: Circle())
            .allowsHitTesting(false)
            .accessibilityLabel(accessibilityText)
    }
}
