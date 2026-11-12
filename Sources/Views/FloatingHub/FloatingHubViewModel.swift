import Foundation
import UIKit

/// Trạng thái kéo/thả và mép của **nút hub nổi** (1.3.524). Menu nổi đã thành sheet (`FloatingHubSheetState`, 2026-11-11).
///
/// Chuyển từ view model của widget thông báo nổi cũ (xoá ở 1.3.524). Khoá vị trí riêng (`floatingHub*`) — không dùng
/// chung với widget nổi khác, kẻo kéo cái này là cái kia nhảy theo. Phần hình học dùng chung `FloatingWidgetGeometry`.
///
/// ## Nửa viên thuốc dính mép (anh Bửu duyệt mockup 2026-11-11)
/// Nút **luôn dính mép** trái / phải (`EdgePillShape`, cao 36, độ nhô theo `EdgePillSettings`): không còn hai trạng thái nép mép nửa ẩn (`.peeking`) /
/// bung vào trong màn (`.revealed`) và hẹn giờ tự thu 3 s của 1.3.524. Thả tay ⇒ bám mép gần hơn, lưu tỉ lệ dọc + mép.
@MainActor
final class FloatingHubViewModel: ObservableObject {
    @Published var verticalRatio: CGFloat
    @Published var edgeDirection: EdgeDirection
    @Published var isDragging = false

    static let storedRatioKey = "floatingHubVerticalRatio"
    static let storedEdgeKey = "floatingHubEdge"
    /// Key của widget thông báo nổi cũ — chỉ đọc **một lần** khi migration, không xoá (revert vẫn còn vị trí).
    private static let legacyRatioKey = "notificationWidgetVerticalRatio"
    private static let legacyEdgeKey = "notificationWidgetEdge"
    /// Mặc định hơi cao hơn giữa màn (0,42) để không đè lên thanh tab ở đáy.
    private static let defaultRatio: CGFloat = 0.42

    init() {
        let defaults = UserDefaults.standard
        FloatingHubViewModel.migrateLegacyPositionIfNeeded(defaults)

        let storedRatio = defaults.double(forKey: FloatingHubViewModel.storedRatioKey)
        let storedEdge = defaults.string(forKey: FloatingHubViewModel.storedEdgeKey)
        self.verticalRatio = storedRatio > 0 ? CGFloat(storedRatio) : FloatingHubViewModel.defaultRatio
        self.edgeDirection = (storedEdge == "left") ? .left : .right
    }

    /// Lần đầu chạy bản có hub: lấy vị trí từ widget thông báo cũ nếu người dùng từng kéo nó, không thì mặc
    /// định 0,42 mép phải. **Ghi ngay** hai key mới để lần sau không chạy lại.
    ///
    /// Phải dùng `object(forKey:)` để biết key có tồn tại hay không: `double(forKey:)` trả 0 cho key chưa có.
    private static func migrateLegacyPositionIfNeeded(_ defaults: UserDefaults) {
        guard defaults.object(forKey: storedRatioKey) == nil else { return }

        let legacyRatio = defaults.double(forKey: legacyRatioKey)
        let ratio = legacyRatio > 0 ? legacyRatio : Double(defaultRatio)
        let edge = defaults.string(forKey: legacyEdgeKey) == "left" ? "left" : "right"

        defaults.set(ratio, forKey: storedRatioKey)
        defaults.set(edge, forKey: storedEdgeKey)
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
