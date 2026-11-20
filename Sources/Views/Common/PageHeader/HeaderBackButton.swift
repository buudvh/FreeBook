import SwiftUI

/// Nút back **tự dựng** dùng chung (1.3.1017): mũi giống nút back hệ thống (`chevron.backward` 17pt nửa đậm, cỡ ảnh
/// lớn), khung chạm 38×44, **mũi canh trái** trong khung ⇒ đặt sát lề (ô `topBarLeading` của thanh hệ thống, hoặc header
/// tự dựng có `.padding(.horizontal, HeaderMetrics.horizontalMargin)`) thì mũi chạm lề, thẳng hàng với nội dung bên dưới.
///
/// Dùng cho: trang con trong sheet (`PageTitleModifier` khi có `\.sheetPageBack`), trang trình bày bằng UIKit có nút back
/// riêng, header Reader / truyện tranh, sheet hub. Nút thu nhỏ `chevron.down` / đóng `xmark` của màn phim, màn nghe là **icon thường**
/// (17pt, cỡ ảnh vừa), không dùng nút này.
///
/// ```swift
/// HeaderBackButton { dismiss() }
/// HeaderBackButton(tint: .white) { onBack() }   // header trên nền tối cố định / nền đọc: mũi theo màu chữ
/// ```
struct HeaderBackButton: View {
    var accessibilityLabel: String = "Quay lại"
    /// `nil` ⇒ màu nhấn (`.appAccentTint()` gắn cả `.accentColor`), như nút back hệ thống.
    var tint: Color? = nil
    let action: () -> Void

    /// Tiêu đề đặt ngay sau nút lùi chừng này vào khung 38pt (mũi ~13pt canh trái) ⇒ mũi cách chữ ~8pt như nút back hệ
    /// thống. Tiêu đề đè lên phải `.allowsHitTesting(false)` để chạm vào vẫn tới nút. Dùng ở `PageTitleModifier` (trang con
    /// trong sheet) và trang con của sheet hub.
    static let titleOverlap: CGFloat = 17

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.backward")
                .font(.system(size: HeaderMetrics.iconFontSize, weight: .semibold))
                .imageScale(.large)
                .foregroundStyle(tint ?? Color.accentColor)
                .frame(width: HeaderMetrics.backFrameWidth, height: HeaderMetrics.backFrameHeight, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}
