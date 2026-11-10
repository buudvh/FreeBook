import SwiftUI

/// Nút đĩa nghe **dùng chung** (1.3.812) cho hai chỗ đặt đĩa: đĩa góc dưới phải (cửa sổ riêng, `MediaDiscContainerViewController`)
/// và ô giữa của thanh tab (`MediaDiscTabBarSlot`). Mặt đĩa theo nguồn đang chạy (`MediaDiscMusicFace` / `MediaDiscTTSFace`).
///
/// Chạm ⇒ `MediaDiscWindowManager.presentQuickControls()`: sheet điều khiển nhanh luôn trình bày từ **cửa sổ của đĩa**
/// (`MediaDiscSheetHost`) — một chỗ giữ sheet cho cả hai lối, và sheet không dính vào màn đang trình bày của cửa sổ chính.
///
/// - `.corner`: nút 52 pt, vòng kính `FloatingGlassBackground` + bìa 44 pt. Vòng kính theo **Độ trong suốt** và **Độ đục**
///   của nút nổi (Cài đặt › Chung › Giao diện) như nút "+" / Home; **bìa** mờ theo Độ trong suốt nhưng luôn còn ≥ 45%
///   (1.3.814, kiểu anh Bửu chọn). Mờ gắn lên lớp bìa, **không** lên lớp cha của kính (alpha < 1 tắt nhoè).
///   **Nhấn giữ 0,4 s** ⇒ `onLongPress` (container đưa đĩa tạm lên header). Cử chỉ nằm ở đây, không phải
///   `UILongPressGestureRecognizer` gắn ở lớp UIKit bên ngoài: nút SwiftUI bắt chạm ngay lúc chạm xuống nên bộ nhận của
///   UIKit không bao giờ chạy (lỗi 1.3.812). Chạm nhanh và nhấn giữ do SwiftUI tự phân xử ⇒ giữ lâu không mở sheet.
/// - `.tabBar`: bìa 44 pt (1.3.814, bằng bìa của đĩa góc), không vòng kính, không mờ; chỗ đứng + gờ nền do
///   `MediaDiscTabBarSlot` lo.
struct MediaDiscFaceButton: View {
    enum Style {
        case corner
        case tabBar
    }

    /// Đường kính bìa ở cả hai chỗ đặt đĩa.
    static let coverSize: CGFloat = 44
    private static let longPressDuration: TimeInterval = 0.4
    /// Bìa đĩa góc không mờ quá mức này dù kéo Độ trong suốt tới 100%.
    private static let minCornerCoverOpacity = 0.45

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
            face(isOnScreen: manager.isDiscOnScreen)
                .opacity(cornerCoverOpacity)
        }
        .frame(width: MediaDiscPlacement.discSize, height: MediaDiscPlacement.discSize)
        .contentShape(Circle())
        .onTapGesture {
            manager.presentQuickControls()
        }
        .onLongPressGesture(minimumDuration: Self.longPressDuration) {
            onLongPress?()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(accessibilityHint)
        .accessibilityAction {
            manager.presentQuickControls()
        }
        .accessibilityAction(named: "Đưa đĩa lên trên") {
            onLongPress?()
        }
    }

    private var tabBarDisc: some View {
        Button {
            manager.presentQuickControls()
        } label: {
            face(isOnScreen: manager.isAppActive)
                .overlay {
                    Circle().stroke(Color.primary.opacity(0.18), lineWidth: 0.75)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(accessibilityHint)
    }

    /// Kéo Độ trong suốt 0 → 100% ⇒ bìa hiện 100% → 45%, đổi đều trên cả dải (mặc định 90% ⇒ ~50%).
    private var cornerCoverOpacity: Double {
        let clear = min(1, max(0, transparency))
        return Self.minCornerCoverOpacity + (1 - Self.minCornerCoverOpacity) * (1 - clear)
    }

    private var accessibilityHint: String {
        manager.faceKind == .music ? "Mở điều khiển nhạc" : "Mở điều khiển nhanh của giọng đọc"
    }

    @ViewBuilder
    private func face(isOnScreen: Bool) -> some View {
        switch manager.faceKind {
        case .music:
            MediaDiscMusicFace(size: Self.coverSize, isOnScreen: isOnScreen)
        case .tts:
            MediaDiscTTSFace(size: Self.coverSize, isOnScreen: isOnScreen)
        }
    }
}
