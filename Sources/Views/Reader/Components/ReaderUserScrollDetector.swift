import SwiftUI
import UIKit

/// Đầu dò "người dùng tự kéo trang": gắn một `UIPanGestureRecognizer` **không tiêu thụ touch** lên
/// `UIScrollView` bao ngoài rồi báo lên SwiftUI khi ngón tay kéo dọc quá `threshold`.
///
/// Vì sao không quan sát `contentOffset`: cú cuộn tự động của TTS cũng đi qua
/// `ScrollViewProxy.scrollTo`, tức cũng đổi `contentOffset`. Quan sát offset sẽ tự tắt chế độ
/// cuộn-theo-highlight ngay lần TTS cuộn đầu tiên — đúng thứ cần tránh. Pan recognizer chỉ nổ khi
/// có ngón tay thật, nên phân biệt được "máy cuộn" và "người cuộn".
///
/// Recognizer đặt `cancelsTouchesInView = false`, `delaysTouchesBegan = false` và nhận diện đồng
/// thời với mọi recognizer khác, đồng thời không bao giờ đòi recognizer khác phải fail — nên nó
/// không giành touch của `UITextView` (bôi đen chữ) hay của chính scroll view.
///
/// View trả về phải nằm **bên trong** content của `ScrollView` (ví dụ `.background` của
/// `LazyVStack`); đặt ở `.overlay` của `ScrollView` thì `parentScrollView` không tìm ra scroll view.
struct ReaderUserScrollDetector: UIViewRepresentable {
    /// Khoảng kéo dọc tối thiểu (pt) mới coi là "người dùng thật sự cuộn".
    let threshold: CGFloat
    let onUserScroll: () -> Void

    init(threshold: CGFloat = 24, onUserScroll: @escaping () -> Void) {
        self.threshold = threshold
        self.onUserScroll = onUserScroll
    }

    func makeUIView(context: Context) -> UIView {
        let view = ProbeView()
        view.coordinator = context.coordinator
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.threshold = threshold
        context.coordinator.onUserScroll = onUserScroll
        // `didMoveToWindow` là đường gắn chính; lần update này là lưới an toàn cho trường hợp
        // probe vào hierarchy trước khi tìm được scroll view. `attach` idempotent nên vô hại.
        if let scrollView = uiView.parentScrollView {
            context.coordinator.attach(to: scrollView)
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.detach()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(threshold: threshold, onUserScroll: onUserScroll)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var threshold: CGFloat
        var onUserScroll: () -> Void
        private weak var attachedScrollView: UIScrollView?
        private var recognizer: UIPanGestureRecognizer?
        /// Chỉ báo **một lần** cho mỗi cú kéo, không phải mỗi frame.
        private var didReportForCurrentDrag = false

        init(threshold: CGFloat, onUserScroll: @escaping () -> Void) {
            self.threshold = threshold
            self.onUserScroll = onUserScroll
        }

        deinit {
            if let pan = recognizer {
                attachedScrollView?.removeGestureRecognizer(pan)
            }
        }

        func attach(to scrollView: UIScrollView) {
            guard attachedScrollView !== scrollView else { return }
            detach()
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.delegate = self
            pan.cancelsTouchesInView = false
            pan.delaysTouchesBegan = false
            pan.delaysTouchesEnded = false
            scrollView.addGestureRecognizer(pan)
            recognizer = pan
            attachedScrollView = scrollView
        }

        func detach() {
            if let pan = recognizer {
                attachedScrollView?.removeGestureRecognizer(pan)
            }
            recognizer = nil
            attachedScrollView = nil
            didReportForCurrentDrag = false
        }

        @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
            switch gesture.state {
            case .began:
                didReportForCurrentDrag = false
            case .changed:
                guard !didReportForCurrentDrag, let view = gesture.view else { return }
                guard abs(gesture.translation(in: view).y) >= threshold else { return }
                didReportForCurrentDrag = true
                onUserScroll()
            case .ended, .cancelled, .failed:
                didReportForCurrentDrag = false
            default:
                break
            }
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
