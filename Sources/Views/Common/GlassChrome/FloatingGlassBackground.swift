import SwiftUI

/// Nền tròn "kính" của nút nổi — nút tai nghe Reader và nút "+" của các màn danh sách (1.3.636). Đọc thẳng cài đặt ở
/// Cài đặt › Giao diện (`GlassChromeSettings`) nên kéo thanh trượt ở đó là mọi nút đổi theo ngay, kể cả ô xem trước.
/// `shape` mặc định hình tròn; pill của menu xổ nút nổi (`FloatingActionMenu`) truyền `Capsule`.
///
/// Viên thuốc nổi (đĩa nghe, hub, nút trình duyệt) có độ trong suốt / độ đục **riêng** (`EdgePillSettings`, 2026-11-11):
/// truyền `pill:` ⇒ đọc cặp khoá của viên đó thay cho "Nút nổi".
///
/// Lớp nhoè là kính của iOS theo **nấc** "Độ đục" (`GlassFrostLevel`, 1.3.645), luôn vẽ ở độ hiện 100% — **không** gắn
/// `.opacity` lên material hay lớp cha của nó (alpha < 1 làm iOS tắt hẳn phần nhoè, lỗi của 1.3.640).
struct FloatingGlassBackground: View {
    /// Nền phía sau tối (Reader chủ đề Tối, mọi màn ngoài Reader) ⇒ nhoè tông tối; nền sáng ⇒ nhoè tông sáng.
    let isDark: Bool
    /// Màu viền mảnh — thường trùng màu icon để vẫn thấy hình nút khi lớp màu gần như trong suốt.
    let outline: Color
    let shape: AnyShape

    @AppStorage private var transparency: Double
    @AppStorage private var frost: Double

    /// `pill == nil` ⇒ cài đặt "Nút nổi" (nút "+", tai nghe Reader…); có ⇒ cài đặt riêng của viên thuốc đó.
    init(
        isDark: Bool = true,
        outline: Color = .white,
        shape: AnyShape = AnyShape(Circle()),
        pill: EdgePillSettings.Kind? = nil
    ) {
        self.isDark = isDark
        self.outline = outline
        self.shape = shape
        if let pill {
            _transparency = AppStorage(wrappedValue: EdgePillSettings.defaultTransparency, pill.transparencyKey)
            _frost = AppStorage(wrappedValue: EdgePillSettings.defaultFrost, pill.frostKey)
        } else {
            _transparency = AppStorage(
                wrappedValue: GlassChromeSettings.defaultFloatingTransparency,
                GlassChromeSettings.floatingTransparencyKey
            )
            _frost = AppStorage(wrappedValue: GlassChromeSettings.defaultFloatingFrost, GlassChromeSettings.floatingFrostKey)
        }
    }

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
