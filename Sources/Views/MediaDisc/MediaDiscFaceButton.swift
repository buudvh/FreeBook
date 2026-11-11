import SwiftUI

/// Mặt đĩa nghe — **nửa viên thuốc** dính mép trong cửa sổ riêng (`MediaDiscContainerViewController`). Mặt đĩa theo nguồn
/// đang chạy (`MediaDiscMusicFace` / `MediaDiscTTSFace`). Kiểu `.tabBar` của ô đĩa giữa thanh tab (1.3.812–864) đã bỏ ở
/// 1.3.865 cùng ô đó.
///
/// - Nửa viên (anh Bửu duyệt mockup 2026-11-11): 68 × 52 dính mép trái / phải (`EdgePillShape`), nền
///   kính `FloatingGlassBackground` theo **Độ trong suốt** và **Độ đục** của nút nổi y như nút "+"; bìa 32 pt đồng tâm đầu
///   bo (thẳng cột với icon "+") và **mờ đúng số** theo Độ trong suốt (`1 − độ trong suốt`, không sàn). Mờ gắn lên lớp bìa,
///   **không** lên lớp cha của kính (alpha < 1 tắt nhoè). Đang kéo ⇒ thành hình tròn 52 pt (`isDiscDragging`).
///   View **chỉ vẽ**: chạm và kéo do container (UIKit, khuôn nút hub) xử lý — không có cử chỉ SwiftUI nào ở đây, nếu không
///   bộ nhận của UIKit không chạy (bài học 1.3.812). VoiceOver mở sheet qua `accessibilityAction`.
struct MediaDiscFaceButton: View {
    @ObservedObject private var manager = MediaDiscWindowManager.shared
    @AppStorage(GlassChromeSettings.floatingTransparencyKey)
    private var transparency = GlassChromeSettings.defaultFloatingTransparency

    var body: some View {
        let edge: EdgeDirection? = manager.isDiscDragging ? nil : manager.discEdge
        let inset = EdgePillShape.contentInset(
            for: CGSize(width: MediaDiscPlacement.discSize, height: MediaDiscPlacement.discSize),
            content: MediaDiscPlacement.coverSize
        )
        return ZStack(alignment: EdgePillShape.contentAlignment(for: edge)) {
            FloatingGlassBackground(shape: AnyShape(EdgePillShape(edge: edge)))
            face(size: MediaDiscPlacement.coverSize, isOnScreen: manager.isDiscOnScreen)
                .opacity(cornerCoverOpacity)
                .padding(edge == .right ? Edge.Set.leading : Edge.Set.trailing, edge == nil ? 0 : inset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(accessibilityHint)
        .accessibilityAction {
            manager.presentQuickControls()
        }
    }

    /// Bìa nửa viên theo đúng lớp màu của nút nổi: trong suốt 0% ⇒ rõ hẳn, 100% ⇒ trong hẳn (1.3.815, không sàn).
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
