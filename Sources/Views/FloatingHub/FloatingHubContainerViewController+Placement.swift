import UIKit

/// Giữ chỗ của nút hub với các widget nổi khác (`FloatingWidgetLayoutCoordinator`) để chúng không đè lên nhau.
///
/// Hub chỉ **nhường** ở hai lúc: vừa thả tay sau khi kéo (`handlePan`) và vừa hiện ra (`needsPlacementResolve`,
/// tiêu thụ ở `updateLayout`). Giữ chỗ đúng cỡ nút 36pt; menu bung **chưa** được tính.
extension FloatingHubContainerViewController {
    /// Né widget nổi khác cùng mép. Dời thì lưu như khi kéo tay; khung mới do lượt `updateLayout` kế tiếp đặt (có
    /// hiệu ứng khi vừa thả tay). Lề trên/dưới phải trùng `clampedY`.
    func resolvePlacement() {
        needsPlacementResolve = false
        let screenHeight = view.bounds.height
        guard view.bounds.width > 0, screenHeight > 0 else { return }

        let range = FloatingWidgetGeometry.centerYRange(
            widgetHeight: Layout.size,
            screenHeight: screenHeight,
            topMargin: view.safeAreaInsets.top + Layout.verticalMargin,
            bottomMargin: view.safeAreaInsets.bottom + Layout.verticalMargin
        )
        let proposed = clampedY(viewModel.verticalRatio * screenHeight, height: Layout.size, screenHeight: screenHeight)
        let placement = FloatingWidgetLayoutCoordinator.shared.resolve(
            id: .hub,
            edge: viewModel.edgeDirection,
            proposedCenterY: proposed,
            height: Layout.size,
            minY: range.lowerBound,
            maxY: range.upperBound
        )
        guard placement.isMoved(from: viewModel.edgeDirection, centerY: proposed) else { return }
        viewModel.applyResolvedPlacement(edge: placement.edge, centerY: placement.centerY, screenHeight: screenHeight)
    }

    /// Báo lại khung nghỉ hiện tại (xoay màn, đổi vùng an toàn) — không xếp lại. Hub đang ẩn thì coordinator bỏ qua.
    func refreshPlacementSlot(centerY: CGFloat) {
        FloatingWidgetLayoutCoordinator.shared.refresh(
            id: .hub,
            edge: viewModel.edgeDirection,
            centerY: centerY,
            height: Layout.size
        )
    }
}
