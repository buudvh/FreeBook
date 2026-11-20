import SwiftUI

/// Vòng chọn của một truyện trong chế độ chọn nhiều (Kệ Sách / Lịch Sử): đã chọn = `checkmark.circle.fill` dấu trắng trên
/// vòng màu nhấn; chưa chọn = vòng rỗng. Cỡ ~24pt. Chỉ để nhìn — chạm do hàng / thẻ xử lý (`ShelfBooksLayoutView`).
///
/// `onCover`: nằm trên bìa (kiểu Lưới / Chỉ bìa) ⇒ vòng rỗng trắng trên nền đen mờ để đọc được trên mọi bìa; ngoài bìa
/// (kiểu Danh sách) vòng rỗng màu xám.
struct ShelfBookSelectionMark: View {
    let isSelected: Bool
    var onCover: Bool = false

    var body: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 22, weight: .regular))
            .symbolRenderingMode(.palette)
            .foregroundStyle(checkColor, Color.accentColor)
            .background {
                if onCover && !isSelected {
                    Circle()
                        .fill(Color.black.opacity(0.35))
                        .padding(1)
                }
            }
            .accessibilityHidden(true)
    }

    /// Lớp đầu của palette: dấu ✓ (đã chọn) hoặc chính vòng rỗng (chưa chọn).
    private var checkColor: Color {
        if isSelected || onCover { return .white }
        return Color(.systemGray)
    }
}
