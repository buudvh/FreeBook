import SwiftUI

/// Nền "kính" của ngăn kéo menu ba chấm: lớp nhoè + lớp tối + viền mảnh.
///
/// Mức nhoè và lớp tối lấy từ Cài đặt › Giao diện (`GlassChromeSettings`, 1.3.636). Lịch sử: material đầy đủ + lớp tối
/// (84% → 55% → 38%, 1.3.622–626) nhoè nền Kệ đen thành mảng xám đều nên "chẳng trong suốt tí nào"; rồi bỏ nhoè, chỉ lớp
/// tối 62% → 80% (1.3.631–632); rồi nhoè một phần bằng animator dừng giữa chừng (1.3.633) — trên máy animator kẹt ở mức
/// nhoè đầy đủ nên cài gì cũng như nhau. Từ 1.3.640 lớp nhoè là material chuẩn mờ dần theo "độ đục" (không có trạng
/// thái): 0% không nhoè, 100% nhoè hết cỡ, mức giữa là nền rõ trộn nền nhoè. Dùng chung cho ngăn kéo thật
/// (`SideDrawerMenuPanel`) và ô xem trước ở màn Giao diện.
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
            shape
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .opacity(frost)
            shape.fill(Color(white: 0.16).opacity(1 - transparency))
            shape.stroke(Color.white.opacity(0.14), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }
}
