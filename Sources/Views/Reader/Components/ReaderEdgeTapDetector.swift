import SwiftUI
import UIKit

/// Chạm 1/3 trái/phải khung đọc để chuyển chương (1.3.643): trái ⇒ chương trước, phải ⇒ chương sau, 1/3 giữa không
/// làm gì. Gắn một `UITapGestureRecognizer` **không tiêu thụ touch** lên `UIScrollView` của chương, cùng mẫu với
/// `ReaderUserScrollDetector` — nên không giành touch của `UITextView` (bôi đen) hay của chính scroll view.
///
/// Chạm chỉ được tính khi **không** phải một thao tác khác:
/// - lúc đặt ngón có đoạn đang bôi đen / menu bôi đen đang hiện ⇒ chạm đó là để bỏ bôi đen;
/// - giữ quá `maxTapDuration` hoặc kéo (recognizer tự fail) ⇒ là bôi đen hoặc cuộn;
/// - trang đang trôi/đang kéo lúc đặt ngón ⇒ chạm để dừng cuộn;
/// - chạm đúp: chờ `confirmDelay` rồi mới báo; trong lúc chờ có chạm thứ hai hoặc chữ vừa được bôi đen ⇒ huỷ.
///
/// Khung nội dung chương chỉ chứa các đoạn chữ (nút Chương trước/sau nằm ở thanh điều khiển bên ngoài), nên không có
/// nút nào bị chạm trùng. View trả về phải nằm **bên trong** content của `ScrollView`.
struct ReaderEdgeTapDetector: UIViewRepresentable {
    enum Direction {
        case previous
        case next
    }

    /// Khoá `@AppStorage` của công tắc ở Cài đặt đọc (mặc định bật).
    static let preferenceKey = "readerEdgeTapChangesChapter"

    let isEnabled: Bool
    /// Trạng thái bôi đen phía SwiftUI (menu bôi đen đang hiện) — cộng với dò `selectedRange` của các ô chữ.
    let isSelectionActive: () -> Bool
    let onTap: (Direction) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = ProbeView()
        view.coordinator = context.coordinator
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.isSelectionActive = isSelectionActive
        context.coordinator.onTap = onTap
        if let scrollView = uiView.parentScrollView {
            context.coordinator.attach(to: scrollView)
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.detach()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isEnabled: isEnabled, isSelectionActive: isSelectionActive, onTap: onTap)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        /// Chạm lâu hơn mốc này không còn là "chạm" (bôi đen bằng nhấn giữ bắt đầu ~0,5 s).
        private static let maxTapDuration: TimeInterval = 0.35
        /// Thời gian chờ chạm thứ hai / chữ được bôi đen trước khi chuyển chương.
        private static let confirmDelay: TimeInterval = 0.25

        var isEnabled: Bool
        var isSelectionActive: () -> Bool
        var onTap: (Direction) -> Void
        private weak var attachedScrollView: UIScrollView?
        private var recognizer: UITapGestureRecognizer?

        /// Ghi lúc đặt ngón: chạm này có bị loại sẵn không (đang bôi đen / đang cuộn).
        private var touchStartedAt: TimeInterval = 0
        private var touchIsDisqualified = false
        private var pendingTap: DispatchWorkItem?

        init(isEnabled: Bool, isSelectionActive: @escaping () -> Bool, onTap: @escaping (Direction) -> Void) {
            self.isEnabled = isEnabled
            self.isSelectionActive = isSelectionActive
            self.onTap = onTap
        }

        deinit {
            pendingTap?.cancel()
            if let tap = recognizer {
                attachedScrollView?.removeGestureRecognizer(tap)
            }
        }

        func attach(to scrollView: UIScrollView) {
            guard attachedScrollView !== scrollView else { return }
            detach()
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            tap.delegate = self
            tap.numberOfTapsRequired = 1
            tap.cancelsTouchesInView = false
            tap.delaysTouchesBegan = false
            tap.delaysTouchesEnded = false
            scrollView.addGestureRecognizer(tap)
            recognizer = tap
            attachedScrollView = scrollView
        }

        func detach() {
            pendingTap?.cancel()
            pendingTap = nil
            if let tap = recognizer {
                attachedScrollView?.removeGestureRecognizer(tap)
            }
            recognizer = nil
            attachedScrollView = nil
        }

        @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, isEnabled, let scrollView = attachedScrollView else { return }
            // Chạm thứ hai trong lúc đang chờ ⇒ chạm đúp (chọn từ): huỷ cả hai.
            if let pending = pendingTap {
                pending.cancel()
                pendingTap = nil
                return
            }
            guard !touchIsDisqualified,
                  ProcessInfo.processInfo.systemUptime - touchStartedAt <= Self.maxTapDuration else { return }

            let width = scrollView.bounds.width
            guard width > 0 else { return }
            let x = gesture.location(in: scrollView).x - scrollView.contentOffset.x
            let direction: Direction
            if x < width / 3 {
                direction = .previous
            } else if x > width * 2 / 3 {
                direction = .next
            } else {
                return
            }

            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pendingTap = nil
                guard self.isEnabled, let scrollView = self.attachedScrollView,
                      !self.isSelectionActive(), !Self.hasTextSelection(in: scrollView) else { return }
                self.onTap(direction)
            }
            pendingTap = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.confirmDelay, execute: work)
        }

        /// Ghi trạng thái lúc đặt ngón — sau đó ô chữ có thể đã tự bỏ bôi đen, scroll view đã dừng trôi.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard isEnabled, let scrollView = attachedScrollView else { return false }
            touchStartedAt = touch.timestamp
            touchIsDisqualified = isSelectionActive()
                || Self.hasTextSelection(in: scrollView)
                || scrollView.isDecelerating
                || scrollView.isDragging
            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            return false
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            return false
        }

        /// Có ô chữ nào trong khung cuộn đang bôi đen không. `LazyVStack` chỉ dựng các đoạn đang gần màn hình nên duyệt
        /// cây view mỗi lần chạm là rẻ.
        private static func hasTextSelection(in view: UIView) -> Bool {
            if let textView = view as? UITextView, textView.selectedRange.length > 0 {
                return true
            }
            return view.subviews.contains { hasTextSelection(in: $0) }
        }
    }

    /// View 1×1 trong suốt, chỉ tồn tại để tìm `UIScrollView` bao ngoài lúc vào hierarchy.
    final class ProbeView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil, let scrollView = parentScrollView else { return }
            coordinator?.attach(to: scrollView)
        }
    }
}
