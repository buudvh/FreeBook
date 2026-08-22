import UIKit

/// Hình học dùng chung cho các widget nổi (TTS và trình duyệt): kẹp tâm theo trục dọc,
/// chọn cạnh gần nhất khi nhả tay và tính tâm X ở trạng thái nghỉ.
///
/// Tách ra để widget trình duyệt tái dùng đúng công thức của TTS widget thay vì
/// nhân bản; công thức giữ nguyên tuyệt đối so với bản trong TTS widget trước đây.
enum FloatingWidgetGeometry {
    /// Kẹp tâm Y sao cho widget không vượt ra ngoài vùng hiển thị hợp lệ.
    static func clampedCenterY(
        _ value: CGFloat,
        widgetHeight: CGFloat,
        screenHeight: CGFloat,
        topMargin: CGFloat,
        bottomMargin: CGFloat
    ) -> CGFloat {
        let minY = topMargin + widgetHeight / 2
        let maxY = max(minY, screenHeight - bottomMargin - widgetHeight / 2)
        return min(max(value, minY), maxY)
    }

    /// Cạnh gần nhất theo tâm X hiện tại (dùng khi nhả tay để snap về mép).
    static func nearestEdge(centerX: CGFloat, screenWidth: CGFloat) -> EdgeDirection {
        centerX < screenWidth - centerX ? .left : .right
    }

    /// Tâm X ở trạng thái nghỉ khi widget đã dán vào một cạnh.
    static func restingCenterX(
        edge: EdgeDirection,
        widgetWidth: CGFloat,
        screenWidth: CGFloat,
        horizontalMargin: CGFloat
    ) -> CGFloat {
        let halfWidth = widgetWidth / 2
        return edge == .left
            ? (horizontalMargin + halfWidth)
            : (screenWidth - horizontalMargin - halfWidth)
    }
}
