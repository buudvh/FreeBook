import SwiftUI

/// Nền "kính" của ngăn kéo menu ba chấm: nhoè **một phần** (`SideDrawerPartialBlurView`) + lớp tối + viền mảnh.
///
/// Mức nhoè và lớp tối lấy từ Cài đặt › Giao diện (`GlassChromeSettings`, 1.3.636); mặc định đúng "kính đục vừa" đã
/// duyệt ở 1.3.633 (nhoè 60% + lớp tối 55%). Lịch sử: material đầy đủ + lớp tối (84% → 55% → 38%, 1.3.622–626) nhoè nền
/// Kệ đen thành mảng xám đều nên "chẳng trong suốt tí nào"; rồi bỏ nhoè, chỉ lớp tối 62% → 80% (1.3.631–632). Dùng chung
/// cho ngăn kéo thật (`SideDrawerMenuPanel`) và ô xem trước ở màn Giao diện.
struct SideDrawerGlassBackground: View {
    @AppStorage(GlassChromeSettings.drawerTransparencyKey)
    private var transparency = GlassChromeSettings.defaultDrawerTransparency
    @AppStorage(GlassChromeSettings.drawerFrostKey)
    private var frost = GlassChromeSettings.defaultDrawerFrost

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 16, style: .continuous)
    }

    var body: some View {
        ZStack {
            SideDrawerPartialBlurView(style: .systemUltraThinMaterialDark, intensity: frost)
                .clipShape(shape)
            shape.fill(Color(white: 0.16).opacity(1 - transparency))
            shape.stroke(Color.white.opacity(0.14), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }
}
