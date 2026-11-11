import SwiftUI

/// Mặt đĩa nghe — **nửa viên thuốc** dính mép trong cửa sổ riêng (`MediaDiscContainerViewController`). Mặt đĩa theo nguồn
/// đang chạy (`MediaDiscMusicFace` / `MediaDiscTTSFace`). Kiểu `.tabBar` của ô đĩa giữa thanh tab (1.3.812–864) đã bỏ ở
/// 1.3.865 cùng ô đó.
///
/// - Nửa viên (anh Bửu duyệt mockup 2026-11-11): cao 52, dính mép trái / phải (`EdgePillShape`), độ nhô + nền kính
///   (`FloatingGlassBackground(pill: .disc)`) theo cài đặt **riêng của đĩa** ở Giao diện › Viên thuốc nổi
///   (`EdgePillSettings`, mặc định 68 pt, 90% trong suốt, không nhoè); bìa 32 pt đồng tâm đầu bo và **mờ đúng số** theo độ
///   trong suốt của đĩa (`1 − trong suốt`, không sàn). Bìa gắn bằng `overlay` nên đĩa hẹp (tới bán nguyệt) thì bìa lọt ra
///   ngoài mép, không đẩy khung kính. Mờ gắn lên lớp bìa, **không** lên lớp cha của kính (alpha < 1 tắt nhoè). Đang kéo
///   ⇒ thành hình tròn 52 pt (`isDiscDragging`).
///   View **chỉ vẽ**: chạm và kéo do container (UIKit, khuôn nút hub) xử lý — không có cử chỉ SwiftUI nào ở đây, nếu không
///   bộ nhận của UIKit không chạy (bài học 1.3.812). VoiceOver mở sheet qua `accessibilityAction`.
struct MediaDiscFaceButton: View {
    @ObservedObject private var manager = MediaDiscWindowManager.shared

    var body: some View {
        let edge: EdgeDirection? = manager.isDiscDragging ? nil : manager.discEdge
        let inset = EdgePillShape.contentInset(height: MediaDiscPlacement.discSize, content: MediaDiscPlacement.coverSize)
        return FloatingGlassBackground(shape: AnyShape(EdgePillShape(edge: edge)), pill: .disc)
            .overlay(alignment: EdgePillShape.contentAlignment(for: edge)) {
                face(size: MediaDiscPlacement.coverSize, isOnScreen: manager.isDiscOnScreen)
                    .floatingIconTransparency(pill: .disc)
                    .padding(EdgePillShape.contentPadding(for: edge), edge == nil ? 0 : inset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(accessibilityHint)
            .accessibilityAction {
                manager.presentQuickControls()
            }
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
