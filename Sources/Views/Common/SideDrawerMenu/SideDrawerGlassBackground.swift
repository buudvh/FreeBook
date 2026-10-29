import SwiftUI

/// Nền "kính" của ngăn kéo menu ba chấm: lớp kính iOS theo nấc + lớp tối + viền mảnh.
///
/// Mức nhoè và lớp tối lấy từ Cài đặt › Giao diện (`GlassChromeSettings`, 1.3.636). Lịch sử: material đầy đủ + lớp tối
/// (1.3.622–626); bỏ nhoè (1.3.631–632); animator dừng giữa chừng (1.3.633, kẹt ở mức nhoè đầy đủ trên máy); material +
/// `.opacity(độ đục)` (1.3.640 — kính iOS chỉ nhoè khi hiện đủ 100%, nên 0–95% thực ra không nhoè); ảnh chụp nền làm
/// nhoè mịn (1.3.645, người dùng cho gỡ).
///
/// Từ 1.3.647 dùng chung 6 nấc kính với nút nổi (`GlassFrostLevel`): mỗi nấc là một độ dày kính iOS, luôn vẽ ở độ hiện
/// 100% — **không** gắn `.opacity`/mặt nạ lên lớp kính hay lớp cha của nó. Dùng cho ngăn kéo thật (`SideDrawerMenuPanel`)
/// và ô xem trước ở màn Giao diện.
struct SideDrawerGlassBackground: View {
    /// Bo góc phải — ngăn kéo thật bám mép màn nên 0; ô xem trước bo theo khung của nó.
    var trailingRadius: CGFloat = 0

    @AppStorage(GlassChromeSettings.drawerTransparencyKey)
    private var transparency = GlassChromeSettings.defaultDrawerTransparency
    @AppStorage(GlassChromeSettings.drawerFrostKey)
    private var frost = GlassChromeSettings.defaultDrawerFrost

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 16,
            bottomLeadingRadius: 16,
            bottomTrailingRadius: trailingRadius,
            topTrailingRadius: trailingRadius,
            style: .continuous
        )
    }

    var body: some View {
        ZStack {
            if let material = GlassFrostLevel(frost: frost).material {
                shape
                    .fill(material)
                    .environment(\.colorScheme, .dark)
            }
            shape.fill(Color(white: 0.16).opacity(1 - transparency))
            shape.stroke(Color.white.opacity(0.14), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }
}
