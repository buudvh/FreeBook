import SwiftUI

/// Nền kính của **sheet điều khiển nhanh** mở từ đĩa nghe góc dưới phải (nhạc `AudioQuickControlSheet`, TTS
/// `TTSQuickControlSheet` — 1.3.806, đĩa chung 1.3.808): kính của ngăn kéo menu (`SideDrawerGlassBackground`) nhưng hình chữ nhật phủ hết sheet
/// (sheet tự bo góc): nấc kính iOS + lớp tối theo "Độ trong suốt" / "Độ đục" của **ngăn kéo** ở Cài đặt › Chung › Giao diện.
/// Không gắn `.opacity` lên lớp kính (kính chỉ nhoè khi hiện đủ 100%). Luôn tông tối ⇒ nội dung sheet vẽ ở `colorScheme` tối.
struct DrawerGlassSheetBackground: View {
    @AppStorage(GlassChromeSettings.drawerTransparencyKey)
    private var transparency = GlassChromeSettings.defaultDrawerTransparency
    @AppStorage(GlassChromeSettings.drawerFrostKey)
    private var frost = GlassChromeSettings.defaultDrawerFrost

    var body: some View {
        ZStack {
            if let material = GlassFrostLevel(frost: frost).material {
                Rectangle()
                    .fill(material)
                    .environment(\.colorScheme, .dark)
            }
            Rectangle()
                .fill(Color(white: 0.16).opacity(1 - transparency))
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
