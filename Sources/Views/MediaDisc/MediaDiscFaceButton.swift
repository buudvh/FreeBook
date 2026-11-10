import SwiftUI

/// Nút đĩa nghe **dùng chung** (1.3.812) cho hai chỗ đặt đĩa: đĩa góc dưới phải (cửa sổ riêng, `MediaDiscContainerViewController`)
/// và ô giữa của thanh tab (`MediaDiscTabBarSlot`). Mặt đĩa theo nguồn đang chạy (`MediaDiscMusicFace` / `MediaDiscTTSFace`).
///
/// Chạm ⇒ `MediaDiscWindowManager.presentQuickControls()`: sheet điều khiển nhanh luôn trình bày từ **cửa sổ của đĩa**
/// (`MediaDiscSheetHost`) — một chỗ giữ sheet cho cả hai lối, và sheet không dính vào màn đang trình bày của cửa sổ chính.
///
/// - `.corner` (1.3.815, anh Bửu: "giống y như các nút +"): nút 52 pt nền kính `FloatingGlassBackground` theo **Độ trong
///   suốt** và **Độ đục** của nút nổi (Cài đặt › Chung › Giao diện) y như nút "+" / Home; bìa 32 pt nằm trong như icon và
///   **cũng mờ theo Độ trong suốt, đúng số** (`1 − độ trong suốt`, không sàn: 100% ⇒ trong hẳn). Mờ gắn lên lớp bìa,
///   **không** lên lớp cha của kính (alpha < 1 tắt nhoè). Đang nằm trong header (`isDiscElevated`) ⇒ kính tan, bìa rõ hẳn
///   như icon header.
///   **Nhấn giữ 0,4 s** ⇒ `onLongPress` (container đưa đĩa tạm vào header). Cử chỉ nằm ở đây, không phải
///   `UILongPressGestureRecognizer` gắn ở lớp UIKit bên ngoài: nút SwiftUI bắt chạm ngay lúc chạm xuống nên bộ nhận của
///   UIKit không bao giờ chạy (lỗi 1.3.812). Nhấn giữ và chạm là **một** cử chỉ ghép, nhấn giữ được ưu tiên ⇒ giữ lâu
///   không mở sheet.
/// - `.tabBar`: bìa 44 pt (1.3.814, bằng bìa của đĩa góc), không vòng kính, không mờ; vùng chạm 52 pt phủ cả gờ nền;
///   chỗ đứng + gờ nền do `MediaDiscTabBarSlot` lo.
struct MediaDiscFaceButton: View {
    enum Style {
        case corner
        case tabBar
    }

    /// Đường kính bìa ở ô giữa thanh tab.
    static let coverSize: CGFloat = 44
    private static let longPressDuration: TimeInterval = 0.4
    private static let elevationAnimation = Animation.easeInOut(duration: 0.3)

    let style: Style
    /// Chỉ đĩa góc: nhấn giữ ⇒ đưa đĩa tạm lên header.
    let onLongPress: (@MainActor () -> Void)?

    @ObservedObject private var manager = MediaDiscWindowManager.shared
    @AppStorage(GlassChromeSettings.floatingTransparencyKey)
    private var transparency = GlassChromeSettings.defaultFloatingTransparency

    init(style: Style, onLongPress: (@MainActor () -> Void)? = nil) {
        self.style = style
        self.onLongPress = onLongPress
    }

    var body: some View {
        switch style {
        case .corner:
            cornerDisc
        case .tabBar:
            tabBarDisc
        }
    }

    private var cornerDisc: some View {
        ZStack {
            FloatingGlassBackground()
                .opacity(manager.isDiscElevated ? 0 : 1)
            face(size: MediaDiscHeaderSlot.coverSize, isOnScreen: manager.isDiscOnScreen)
                .opacity(manager.isDiscElevated ? 1 : cornerCoverOpacity)
                .overlay {
                    // Trong header kính đã tan ⇒ viền mảnh như đĩa thanh tab để bìa tối vẫn rõ mép trên header tối.
                    Circle()
                        .stroke(Color.primary.opacity(0.18), lineWidth: 0.75)
                        .opacity(manager.isDiscElevated ? 1 : 0)
                }
        }
        .animation(Self.elevationAnimation, value: manager.isDiscElevated)
        .frame(width: MediaDiscPlacement.discSize, height: MediaDiscPlacement.discSize)
        .contentShape(Circle())
        // Một cử chỉ ghép, nhấn giữ **được ưu tiên**: giữ đủ 0,4 s ⇒ chỉ lên header, thả tay không mở sheet; thả sớm hơn ⇒
        // nhấn giữ hỏng, chạm mới được nhận. Đừng tách thành `.onTapGesture` + `.onLongPressGesture` (thứ tự ưu tiên ngầm).
        .gesture(
            LongPressGesture(minimumDuration: Self.longPressDuration)
                .onEnded { _ in onLongPress?() }
                .exclusively(before: TapGesture().onEnded { manager.presentQuickControls() })
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(accessibilityHint)
        .accessibilityAction {
            manager.presentQuickControls()
        }
        .accessibilityAction(named: "Đưa đĩa vào header") {
            onLongPress?()
        }
    }

    private var tabBarDisc: some View {
        Button {
            manager.presentQuickControls()
        } label: {
            face(size: Self.coverSize, isOnScreen: manager.isAppActive)
                .overlay {
                    Circle().stroke(Color.primary.opacity(0.18), lineWidth: 0.75)
                }
                // Vùng chạm phủ cả vòng nền 52 pt của `MediaDiscTabBarSlot` ⇒ chạm phần gờ nhô lên cũng mở sheet.
                .frame(width: MediaDiscPlacement.discSize, height: MediaDiscPlacement.discSize)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(accessibilityHint)
    }

    /// Bìa đĩa góc theo đúng lớp màu của nút nổi: trong suốt 0% ⇒ rõ hẳn, 100% ⇒ trong hẳn (1.3.815, không sàn).
    private var cornerCoverOpacity: Double {
        1 - min(1, max(0, transparency))
    }

    private var accessibilityHint: String {
        manager.faceKind == .music ? "Mở điều khiển nhạc" : "Mở điều khiển nhanh của giọng đọc"
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
