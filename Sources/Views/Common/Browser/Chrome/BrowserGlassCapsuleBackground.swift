import SwiftUI

/// Nền kính **hình viên** cho phần nổi của trình duyệt người dùng (mockup 2026-10-30): thanh kính dưới, viên Import, dải
/// báo tự dịch. Cùng cách vẽ với `FloatingGlassBackground` (nút "+" nổi, nút tai nghe Reader) và đọc khoá của
/// `GlassChromeSettings` ⇒ kéo "Độ trong suốt" / "Độ đục" ở Cài đặt › Giao diện là thanh và viên đổi theo ngay.
///
/// Hai kiểu kính:
/// - `usesBarGlass == true` (thanh dưới, dải báo): đọc khoá **ngăn kéo** (`drawer*`, mặc định lớp tối 55% + nhoè) — mockup
///   là kính tối đậm, icon trắng phải đọc được trên trang web nền trắng. Khoá nút nổi mặc định chỉ có lớp màu 10%, không
///   nhoè ⇒ trên trang trắng icon gần như biến mất.
/// - `false` (viên Import): đọc khoá **nút nổi** (`floating*`) — viên trong suốt như nút "+" nổi.
///
/// Lớp nhoè là kính của iOS theo nấc (`GlassFrostLevel`), luôn vẽ ở độ hiện 100% — **không** gắn `.opacity` lên view này
/// hay lớp cha của nó (alpha < 1 làm iOS tắt hẳn phần nhoè). Hiệu ứng thu/mở viên Import chỉ làm mờ chữ, không làm mờ nền.
struct BrowserGlassCapsuleBackground: View {
    /// Độ đậm viền mảnh — mockup: thanh dưới 16%, viên Import 24%, dải báo 14%.
    var outlineOpacity: Double = 0.16
    /// Trạng thái "đang bật" kiểu chip (viên Import khi bảng chọn nguồn đang mở): phủ trắng 18%, viền trắng 60%.
    var isHighlighted = false
    /// Kính tối đậm của thanh (khoá ngăn kéo) thay vì kính trong của nút nổi — xem doc của type.
    var usesBarGlass = false

    @AppStorage(GlassChromeSettings.floatingTransparencyKey)
    private var floatingTransparency = GlassChromeSettings.defaultFloatingTransparency
    @AppStorage(GlassChromeSettings.floatingFrostKey)
    private var floatingFrost = GlassChromeSettings.defaultFloatingFrost
    @AppStorage(GlassChromeSettings.drawerTransparencyKey)
    private var drawerTransparency = GlassChromeSettings.defaultDrawerTransparency
    @AppStorage(GlassChromeSettings.drawerFrostKey)
    private var drawerFrost = GlassChromeSettings.defaultDrawerFrost

    private var transparency: Double { usesBarGlass ? drawerTransparency : floatingTransparency }
    private var frost: Double { usesBarGlass ? drawerFrost : floatingFrost }

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
            if isHighlighted {
                Capsule().fill(Color.white.opacity(0.18))
            }
            Capsule().strokeBorder(Color.white.opacity(isHighlighted ? 0.6 : outlineOpacity), lineWidth: 0.75)
        }
        .accessibilityHidden(true)
    }
}
