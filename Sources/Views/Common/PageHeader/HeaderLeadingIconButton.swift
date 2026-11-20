import SwiftUI

/// Nút icon đứng **trước tiêu đề** ở hàng nút (1.3.1021, anh Bửu: "Kiểm tra tiện ích / Kiểm tra nguồn, khi mở dạng sheet /
/// Màn AI toàn màn của Reader dời ⌄", "size tiêu đề bằng size tiêu đề bình thường") — vd ⌄ thu nhỏ / đóng của sheet, màn
/// toàn màn. Trước đây ⌄ đứng chung cụm bên phải.
///
/// Icon SF 17pt nửa đậm, khung 36×44 **canh trái** ⇒ đặt ở ô `topBarLeading` thì icon chạm lề. Tiêu đề 22pt đậm đặt ngay
/// sau, lùi `titleOverlap` vào khung (khung rộng hơn icon) để icon cách chữ ~10pt — như nút back cạnh tiêu đề. Nút back
/// thật thì dùng `HeaderBackButton`.
///
/// ```swift
/// .pageTitle("Kiểm tra nguồn", leadingIcon: HeaderLeadingIconButton(
///     systemName: "chevron.down", accessibilityLabel: "Thu nhỏ", action: minimize))
/// ```
struct HeaderLeadingIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    /// `nil` ⇒ màu nhấn (như các nút khác trên thanh điều hướng).
    var tint: Color? = nil
    let action: () -> Void

    /// Phần khung icon mà tiêu đề được lùi đè lên (khung 36pt, icon ~16pt canh trái ⇒ còn ~10pt giữa icon và chữ). Tiêu đề
    /// đè lên phải `.allowsHitTesting(false)` để chạm vào vẫn tới nút.
    static let titleOverlap: CGFloat = 10

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: HeaderMetrics.iconFontSize, weight: .semibold))
                .foregroundStyle(tint ?? Color.accentColor)
                .frame(width: HeaderMetrics.iconFrameWidth, height: HeaderMetrics.backFrameHeight, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}
