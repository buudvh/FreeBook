import UIKit

/// Chạm + kéo nửa viên đĩa nghe (anh Bửu duyệt mockup 2026-11-11), khuôn `FloatingHubContainerViewController.handlePan`:
/// bộ nhận UIKit gắn trên `discView`, mặt đĩa SwiftUI không có cử chỉ nào.
///
/// - Chạm ⇒ sheet điều khiển nhanh (`MediaDiscWindowManager.presentQuickControls`).
/// - Bắt đầu kéo ⇒ co thành **hình tròn 52 pt** đặt đúng tâm bìa (không giật dưới tay), phóng nhẹ 1,06.
/// - Đang kéo ⇒ đi theo tay trong màn (không chui vào vùng an toàn trên / dưới).
/// - Thả ⇒ bám mép gần hơn (theo tâm X), độ cao kẹp trong dải của `MediaDiscPlacement.topRange`; đè nút hub / nút trình
///   duyệt cùng mép ⇒ nửa viên **nhường** (dời sát trên / dưới nó, `FloatingWidgetLayoutCoordinator.resolve`), rồi lưu chỗ
///   (`MediaDiscPositionStore`). Đè nút "+" / thanh dưới thì `MediaDiscPlacement` tự đẩy lên lúc vẽ, không lưu.
extension MediaDiscContainerViewController {
    private static let grabScale: CGFloat = 1.06

    func setupDiscGestures() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleDiscPan(_:)))
        pan.cancelsTouchesInView = true
        discView.addGestureRecognizer(pan)
        panGesture = pan

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleDiscTap(_:)))
        tap.cancelsTouchesInView = true
        discView.addGestureRecognizer(tap)
    }

    /// Đĩa bị ẩn / chặn giữa lúc kéo ⇒ thôi kéo, không lưu chỗ.
    func cancelDrag() {
        guard isDragging else { return }
        isDragging = false
        panGesture?.isEnabled = false
        panGesture?.isEnabled = true
        discView.transform = .identity
        MediaDiscWindowManager.shared.noteDiscDragging(false)
    }

    @objc private func handleDiscTap(_ gesture: UITapGestureRecognizer) {
        guard isDiscInteractive, !isDragging else { return }
        MediaDiscWindowManager.shared.presentQuickControls()
    }

    @objc private func handleDiscPan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            beginDrag()
        case .changed:
            guard isDragging else { return }
            moveDrag(by: gesture.translation(in: view))
        case .ended, .cancelled, .failed:
            endDrag()
        default:
            break
        }
    }

    private func beginDrag() {
        guard isDiscInteractive else { return }
        isDragging = true
        // Tâm bìa = tâm đầu bo, cách đầu bo một bán kính ⇒ hình tròn mới đặt đúng chỗ bìa đang nằm.
        let frame = discView.frame
        let radius = EdgePillShape.cornerRadius(for: discView.bounds.size)
        let coverCenterX = MediaDiscWindowManager.shared.discEdge == .left ? frame.maxX - radius : frame.minX + radius
        let center = CGPoint(x: coverCenterX, y: frame.midY)
        dragStartCenter = center
        MediaDiscWindowManager.shared.noteDiscDragging(true)
        let size = MediaDiscPlacement.discSize
        animate(true, motion: .grab) {
            self.discView.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            self.discView.center = center
            self.discView.transform = CGAffineTransform(scaleX: Self.grabScale, y: Self.grabScale)
        }
    }

    private func moveDrag(by translation: CGPoint) {
        let bounds = view.bounds
        let insets = view.safeAreaInsets
        let half = MediaDiscPlacement.discSize / 2
        let x = min(max(dragStartCenter.x + translation.x, half), bounds.width - half)
        let minY = insets.top + half
        let y = min(max(dragStartCenter.y + translation.y, minY), max(minY, bounds.height - insets.bottom - half))
        discView.center = CGPoint(x: x, y: y)
    }

    private func endDrag() {
        guard isDragging else { return }
        isDragging = false
        let bounds = view.bounds
        let center = discView.center
        let edge: EdgeDirection = center.x < bounds.midX ? .left : .right
        let range = MediaDiscPlacement.topRange(bounds: bounds, safeInsets: view.safeAreaInsets)
        let height = MediaDiscPlacement.pillSize.height
        let minCenterY = range.lowerBound + height / 2
        let maxCenterY = range.upperBound + height / 2
        let proposed = min(max(center.y, minCenterY), maxCenterY)
        // Vừa thả ⇒ nhường widget nổi khác cùng mép (như hub vừa thả); `resolve` cũng mở / giữ chỗ luôn.
        let placement = FloatingWidgetLayoutCoordinator.shared.resolve(
            id: .mediaDisc,
            edge: edge,
            proposedCenterY: proposed,
            height: height,
            minY: minCenterY,
            maxY: maxCenterY
        )
        needsSlotClaim = false
        MediaDiscPositionStore.save(edge: placement.edge, centerY: placement.centerY, screenHeight: bounds.height)
        AppLogger.shared.log(
            "💿 [MediaDisc] Thả đĩa ⇒ mép \(placement.edge.rawValue), tâm \(Int(placement.centerY))/\(Int(bounds.height))"
        )
        MediaDiscWindowManager.shared.noteDiscEdge(placement.edge)
        MediaDiscWindowManager.shared.noteDiscDragging(false)
        updateDisc(animated: true)
    }
}
