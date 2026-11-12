import Combine
import UIKit

/// Trạng thái kéo/thả và mép của widget trình duyệt thu nhỏ (dựng lại ở 1.3.533 sau khi tách khỏi hub nổi).
///
/// **Giữ nguyên hai key UserDefaults cũ** (`visibleBrowserReopenVerticalRatio`, `visibleBrowserReopenEdge`) nên
/// vị trí người dùng đã chọn trước khi widget gộp vào hub (1.3.524) vẫn còn.
///
/// **Cố ý là lớp riêng**, không tái dùng `FloatingHubViewModel`: mỗi lớp hard-code key vị trí của nó, dùng chung là hai
/// widget **ghi đè vị trí của nhau**. Phần hình học vẫn dùng chung `FloatingWidgetGeometry`.
///
/// Nút là nửa viên **luôn dính mép** (anh Bửu duyệt mockup 2026-11-11): không còn nép mép nửa ẩn / bung / tự thu 3 s.
@MainActor
final class VisibleBrowserReopenViewModel: ObservableObject {
    @Published var verticalRatio: CGFloat
    @Published var edgeDirection: EdgeDirection
    @Published var isDragging = false

    static let storedRatioKey = "visibleBrowserReopenVerticalRatio"
    static let storedEdgeKey = "visibleBrowserReopenEdge"
    /// Mặc định 1,0 = sát đáy màn (kẹp theo vùng an toàn), giữ đúng hành vi của widget cũ.
    private static let defaultRatio: CGFloat = 1.0

    init() {
        let defaults = UserDefaults.standard
        let storedRatio = defaults.double(forKey: Self.storedRatioKey)
        let storedEdge = defaults.string(forKey: Self.storedEdgeKey)
        self.verticalRatio = storedRatio > 0 ? CGFloat(storedRatio) : Self.defaultRatio
        self.edgeDirection = (storedEdge == "left") ? .left : .right
    }

    /// Đưa widget về trạng thái xuất hiện chuẩn (không kéo dở). Gọi mỗi lần widget hiện lại.
    func prepareForAppearance() {
        isDragging = false
    }

    func handleDragStart() {
        isDragging = true
    }

    /// Chốt vị trí sau khi nhả tay: bám cạnh gần nhất, kẹp Y trong vùng hợp lệ, lưu tỉ lệ/cạnh để không reset khi view
    /// dựng lại.
    func handleDragEnd(
        finalPosition: CGPoint,
        widgetHeight: CGFloat,
        screenWidth: CGFloat,
        screenHeight: CGFloat,
        topMargin: CGFloat,
        bottomMargin: CGFloat
    ) {
        guard screenWidth > 0, screenHeight > 0 else {
            isDragging = false
            return
        }

        let targetEdge = FloatingWidgetGeometry.nearestEdge(
            centerX: finalPosition.x,
            screenWidth: screenWidth
        )
        let targetY = FloatingWidgetGeometry.clampedCenterY(
            finalPosition.y,
            widgetHeight: widgetHeight,
            screenHeight: screenHeight,
            topMargin: topMargin,
            bottomMargin: bottomMargin
        )

        verticalRatio = targetY / screenHeight
        edgeDirection = targetEdge
        isDragging = false
        persistPosition()
    }

    /// Ghi chỗ đặt do `FloatingWidgetLayoutCoordinator` chọn (né widget nổi khác) — lưu y như khi kéo tay.
    func applyResolvedPlacement(edge: EdgeDirection, centerY: CGFloat, screenHeight: CGFloat) {
        guard screenHeight > 0 else { return }
        verticalRatio = centerY / screenHeight
        edgeDirection = edge
        persistPosition()
    }

    private func persistPosition() {
        UserDefaults.standard.set(Double(verticalRatio), forKey: Self.storedRatioKey)
        UserDefaults.standard.set(edgeDirection == .left ? "left" : "right", forKey: Self.storedEdgeKey)
    }
}
