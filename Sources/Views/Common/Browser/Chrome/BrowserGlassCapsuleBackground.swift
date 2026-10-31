import SwiftUI

/// Nền kính **hình viên** cho dải báo tự dịch của trình duyệt người dùng (mockup 2026-10-30). Cùng cách vẽ với
/// `FloatingGlassBackground` (nút "+" nổi, nút tai nghe Reader) và đọc khoá **ngăn kéo** (`drawer*`, mặc định lớp tối
/// 55% + nhoè) của `GlassChromeSettings` ⇒ kéo "Độ trong suốt" / "Độ đục" ở Cài đặt › Giao diện là dải đổi theo ngay.
/// Kính tối đậm để chữ trắng đọc được trên trang web nền trắng.
///
/// Thanh dưới và nút Import không còn nổi trên trang (thanh gắn sát đáy, nền đặc — 2026-10-31) nên không dùng view này.
///
/// Lớp nhoè là kính của iOS theo nấc (`GlassFrostLevel`), luôn vẽ ở độ hiện 100% — **không** gắn `.opacity` lên view này
/// hay lớp cha của nó (alpha < 1 làm iOS tắt hẳn phần nhoè).
struct BrowserGlassCapsuleBackground: View {
    /// Độ đậm viền mảnh (mockup: dải báo 14%).
    var outlineOpacity: Double = 0.14

    @AppStorage(GlassChromeSettings.drawerTransparencyKey)
    private var transparency = GlassChromeSettings.defaultDrawerTransparency
    @AppStorage(GlassChromeSettings.drawerFrostKey)
    private var frost = GlassChromeSettings.defaultDrawerFrost

    /// Màu nền tối của mockup (`rgba(36,36,40,…)`); độ đậm lấy từ cài đặt "Độ trong suốt".
    private static let tintColor = Color(red: 36 / 255, green: 36 / 255, blue: 40 / 255)

    var body: some View {
        ZStack {
            if let material = GlassFrostLevel(frost: frost).material {
                Capsule()
                    .fill(material)
                    .environment(\.colorScheme, .dark)
            }
            Capsule().fill(Self.tintColor.opacity(1 - transparency))
            Capsule().strokeBorder(Color.white.opacity(outlineOpacity), lineWidth: 0.75)
        }
        .accessibilityHidden(true)
    }
}
