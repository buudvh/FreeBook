import SwiftUI

/// Nút đĩa nghe **dùng chung** (1.3.812) cho hai chỗ đặt đĩa: đĩa góc dưới phải (cửa sổ riêng, `MediaDiscContainerViewController`)
/// và ô giữa của thanh tab (`MediaDiscTabBarSlot`). Mặt đĩa theo nguồn đang chạy (`MediaDiscMusicFace` / `MediaDiscTTSFace`).
///
/// Chạm ⇒ `MediaDiscWindowManager.presentQuickControls()`: sheet điều khiển nhanh luôn trình bày từ **cửa sổ của đĩa**
/// (`MediaDiscSheetHost`) — một chỗ giữ sheet cho cả hai lối, và sheet không dính vào màn đang trình bày của cửa sổ chính.
///
/// - `.corner`: nút 52 pt, vòng kính `FloatingGlassBackground` + bìa 44 pt. Giống hệt nút "+" / Home (1.3.813, anh Bửu): vòng
///   kính theo **Độ trong suốt** và **Độ đục** của nút nổi (Cài đặt › Chung › Giao diện), bìa luôn rõ như icon của các nút đó.
/// - `.tabBar`: bìa 32 pt gọn trong chiều cao thanh tab, không vòng kính, không mờ.
struct MediaDiscFaceButton: View {
    enum Style {
        case corner
        case tabBar
    }

    let style: Style

    @ObservedObject private var manager = MediaDiscWindowManager.shared

    static let tabBarDiscSize: CGFloat = 32
    private static let cornerCoverSize: CGFloat = 44

    var body: some View {
        Button {
            manager.presentQuickControls()
        } label: {
            discLabel
        }
        .buttonStyle(.plain)
        .accessibilityHint(manager.faceKind == .music ? "Mở điều khiển nhạc" : "Mở điều khiển nhanh của giọng đọc")
    }

    @ViewBuilder
    private var discLabel: some View {
        switch style {
        case .corner:
            ZStack {
                FloatingGlassBackground()
                face(size: Self.cornerCoverSize, isOnScreen: manager.isDiscOnScreen)
            }
            .frame(width: MediaDiscPlacement.discSize, height: MediaDiscPlacement.discSize)
            .contentShape(Circle())
        case .tabBar:
            face(size: Self.tabBarDiscSize, isOnScreen: manager.isAppActive)
                .overlay {
                    Circle().stroke(Color.primary.opacity(0.18), lineWidth: 0.75)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
    }

    @ViewBuilder
    private func face(size: CGFloat, isOnScreen: Bool) -> some View {
        switch manager.faceKind {
        case .music:
            MediaDiscMusicFace(size: size, isOnScreen: isOnScreen)
        case .tts:
            MediaDiscTTSFace(size: size, isOnScreen: isOnScreen)
        }
    }
}
