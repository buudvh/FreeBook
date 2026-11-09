import SwiftUI

/// Nút đĩa nghe **dùng chung** (1.3.812) cho hai chỗ đặt đĩa: đĩa góc dưới phải (cửa sổ riêng, `MediaDiscContainerViewController`)
/// và ô giữa của thanh tab (`MediaDiscTabBarSlot`). Mặt đĩa theo nguồn đang chạy (`MediaDiscMusicFace` / `MediaDiscTTSFace`).
///
/// Chạm ⇒ `MediaDiscWindowManager.presentQuickControls()`: sheet điều khiển nhanh luôn trình bày từ **cửa sổ của đĩa**
/// (`MediaDiscSheetHost`) — một chỗ giữ sheet cho cả hai lối, và sheet không dính vào màn đang trình bày của cửa sổ chính.
///
/// - `.corner`: nút 52 pt, vòng kính `FloatingGlassBackground` + bìa 44 pt. Cả vòng kính lẫn bìa theo **Độ trong suốt** của
///   nút nổi (Cài đặt › Chung › Giao diện): bìa hiện `1 − độ trong suốt`, đúng như lớp màu của vòng kính; **Độ đục** là nhoè
///   của vòng kính. Mờ gắn lên lớp bìa, **không** lên lớp cha của kính (alpha < 1 tắt nhoè).
/// - `.tabBar`: bìa 32 pt gọn trong chiều cao thanh tab, không vòng kính, không mờ.
struct MediaDiscFaceButton: View {
    enum Style {
        case corner
        case tabBar
    }

    let style: Style

    @ObservedObject private var manager = MediaDiscWindowManager.shared
    @AppStorage(GlassChromeSettings.floatingTransparencyKey)
    private var transparency = GlassChromeSettings.defaultFloatingTransparency

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
                    .opacity(coverOpacity)
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

    /// Bìa đĩa góc hiện theo đúng lớp màu của vòng kính: trong suốt 0 ⇒ rõ hẳn, 1 ⇒ trong hẳn.
    private var coverOpacity: Double {
        min(1, max(0, 1 - transparency))
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
