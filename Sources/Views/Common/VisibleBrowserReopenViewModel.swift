import SwiftUI
import Combine

/// Trạng thái kéo/thả và vị trí nghỉ của widget trình duyệt thu nhỏ.
/// Cùng vai trò với `FloatingWidgetViewModel` của TTS widget và giữ nguyên hai key
/// UserDefaults cũ nên vị trí người dùng đã chọn trước đây không bị mất.
@MainActor
final class VisibleBrowserReopenViewModel: ObservableObject {
    @Published var verticalRatio: CGFloat
    @Published var edgeDirection: EdgeDirection
    @Published var isDragging = false

    private let storedRatioKey = "visibleBrowserReopenVerticalRatio"
    private let storedEdgeKey = "visibleBrowserReopenEdge"

    init() {
        let storedRatio = UserDefaults.standard.double(forKey: storedRatioKey)
        let storedEdge = UserDefaults.standard.string(forKey: storedEdgeKey)
        self.verticalRatio = storedRatio > 0 ? CGFloat(storedRatio) : 1.0
        self.edgeDirection = (storedEdge == "left") ? .left : .right
    }

    func handleDragStart() {
        isDragging = true
    }

    /// Chốt vị trí sau khi nhả tay: snap về cạnh gần nhất, kẹp Y trong vùng hợp lệ,
    /// rồi lưu tỉ lệ/cạnh để không bị reset khi view dựng lại.
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

        UserDefaults.standard.set(Double(verticalRatio), forKey: storedRatioKey)
        UserDefaults.standard.set(targetEdge == .left ? "left" : "right", forKey: storedEdgeKey)
    }
}
