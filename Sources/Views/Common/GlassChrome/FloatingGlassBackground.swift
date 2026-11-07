import SwiftUI

/// Nền tròn "kính" của nút nổi — nút tai nghe Reader và nút "+" của các màn danh sách (1.3.636). Đọc thẳng cài đặt ở
/// Cài đặt › Giao diện (`GlassChromeSettings`) nên kéo thanh trượt ở đó là mọi nút đổi theo ngay, kể cả ô xem trước.
/// `shape` mặc định hình tròn; pill của menu xổ nút nổi (`FloatingActionMenu`) truyền `Capsule`.
///
/// Lớp nhoè là kính của iOS theo **nấc** "Độ đục" (`GlassFrostLevel`, 1.3.645), luôn vẽ ở độ hiện 100% — **không** gắn
/// `.opacity` lên material hay lớp cha của nó (alpha < 1 làm iOS tắt hẳn phần nhoè, lỗi của 1.3.640).
struct FloatingGlassBackground: View {
    /// Nền phía sau tối (Reader chủ đề Tối, mọi màn ngoài Reader) ⇒ nhoè tông tối; nền sáng ⇒ nhoè tông sáng.
    var isDark = true
    /// Màu viền mảnh — thường trùng màu icon để vẫn thấy hình nút khi lớp màu gần như trong suốt.
    var outline: Color = .white
    var shape = AnyShape(Circle())

    @AppStorage(GlassChromeSettings.floatingTransparencyKey)
    private var transparency = GlassChromeSettings.defaultFloatingTransparency
    @AppStorage(GlassChromeSettings.floatingFrostKey)
    private var frost = GlassChromeSettings.defaultFloatingFrost

    var body: some View {
        ZStack {
            if let material = GlassFrostLevel(frost: frost).material {
                shape
                    .fill(material)
                    .environment(\.colorScheme, isDark ? .dark : .light)
            }
            shape.fill(Color(white: isDark ? 0.16 : 0.3).opacity(1 - transparency))
            shape.stroke(outline.opacity(0.28), lineWidth: 0.75)
        }
        .accessibilityHidden(true)
    }
}
