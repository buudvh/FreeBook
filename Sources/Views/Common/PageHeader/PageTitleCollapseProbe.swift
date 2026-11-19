import SwiftUI
import UIKit

/// Đầu dò UIKit cho tiêu đề kiểu `.centered` (1.3.984): báo SwiftUI khi **tiêu đề lớn ở hàng 2** của thanh điều hướng đã
/// thu lại (người dùng cuộn lên) để `PageTitleModifier` hiện tiêu đề nhỏ cạnh nút back.
///
/// iOS 17 không có API SwiftUI nào cho biết tiêu đề lớn đang hiện hay đã thu, nên đầu dò (một `UIView` 0×0, không nhận
/// chạm, gắn làm `.background` của trang) tự đọc cây UIKit:
/// - Tìm `UINavigationBar` của trang qua chuỗi responder (VC gần nhất ⇒ `navigationController`).
/// - Theo dõi (KVO) `frame` / `bounds` của thanh **và** `contentOffset` của scroll view lớn nhất trong trang (List / Form /
///   ScrollView) — `contentOffset` đổi theo từng nhịp cuộn nên là tín hiệu chắc nhất.
/// - "Đã thu" = nhãn tiêu đề lớn (UILabel trong thanh có chữ đúng tiêu đề, cỡ ≥ 20pt — nhãn tiêu đề nhỏ hệ thống 17pt và
///   đang bị ô `principal` thay nên không lẫn) bị ẩn, mờ < 50% hoặc bị thanh cắt quá nửa.
/// - Không tìm thấy nhãn ⇒ coi như **đang hiện** (không hiện tiêu đề nhỏ) — dò hỏng thì tiêu đề chỉ cuộn đi, không hiện
///   hai tiêu đề chồng nhau.
///
/// Chỉ báo khi kết quả đổi. Rời cửa sổ (trang khác đè lên) ⇒ bỏ theo dõi; gắn lại ⇒ dò lại.
struct PageTitleCollapseProbe: UIViewRepresentable {
    let title: String
    let onChange: (Bool) -> Void

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.configure(title: title, onChange: onChange)
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        uiView.configure(title: title, onChange: onChange)
    }

    static func dismantleUIView(_ uiView: ProbeView, coordinator: ()) {
        uiView.stopObserving()
    }

    final class ProbeView: UIView {
        /// Cỡ chữ tối thiểu để nhận là nhãn tiêu đề **lớn** (tiêu đề lớn của app 22pt; tiêu đề nhỏ hệ thống 17pt).
        private static let largeTitleMinPointSize: CGFloat = 20

        private var title = ""
        private var onChange: ((Bool) -> Void)?
        private weak var observedBar: UINavigationBar?
        private weak var observedScrollView: UIScrollView?
        private var observations: [NSKeyValueObservation] = []
        private var lastCollapsed: Bool?
        private var evaluationScheduled = false

        func configure(title: String, onChange: @escaping (Bool) -> Void) {
            let titleChanged = self.title != title
            self.title = title
            self.onChange = onChange
            if titleChanged { lastCollapsed = nil }
        }

        func stopObserving() {
            observations.forEach { $0.invalidate() }
            observations.removeAll()
            observedBar = nil
            observedScrollView = nil
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else {
                stopObserving()
                return
            }
            // Nhịp sau: cây VC / scroll view của trang vừa đẩy vào có thể chưa xong.
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.attach() }
            }
        }

        override func safeAreaInsetsDidChange() {
            super.safeAreaInsetsDidChange()
            scheduleEvaluation()
        }

        // MARK: - Theo dõi

        private func attach() {
            guard window != nil, let controller = Self.owningViewController(of: self),
                  let bar = controller.navigationController?.navigationBar else { return }
            let scrollView = Self.primaryScrollView(in: controller.view)
            if bar !== observedBar || scrollView !== observedScrollView {
                stopObserving()
                observedBar = bar
                observedScrollView = scrollView
                let onBarChange: (UINavigationBar) -> Void = { [weak self] _ in self?.scheduleEvaluation() }
                observations.append(bar.observe(\.frame) { bar, _ in onBarChange(bar) })
                observations.append(bar.observe(\.bounds) { bar, _ in onBarChange(bar) })
                if let scrollView {
                    observations.append(scrollView.observe(\.contentOffset) { [weak self] _, _ in
                        self?.scheduleEvaluation()
                    })
                }
            }
            evaluate()
        }

        /// KVO có thể bắn nhiều lần mỗi nhịp (và gọi từ ngữ cảnh không cô lập) ⇒ gộp về một lần đánh giá ở nhịp main kế.
        private nonisolated func scheduleEvaluation() {
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.requestEvaluation() }
            }
        }

        private func requestEvaluation() {
            guard !evaluationScheduled else { return }
            evaluationScheduled = true
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    self?.evaluationScheduled = false
                    self?.evaluate()
                }
            }
        }

        private func evaluate() {
            guard window != nil, let bar = observedBar else { return }
            // Scroll view của trang đổi (List dựng lại) ⇒ gắn lại theo dõi.
            if let scrollView = observedScrollView, scrollView.window == nil {
                attach()
                return
            }
            let collapsed = !Self.isLargeTitleVisible(in: bar, title: title)
            guard collapsed != lastCollapsed else { return }
            lastCollapsed = collapsed
            onChange?(collapsed)
        }

        // MARK: - Đọc cây UIKit

        private static func owningViewController(of view: UIView) -> UIViewController? {
            var responder: UIResponder? = view.next
            while let current = responder {
                if let controller = current as? UIViewController { return controller }
                responder = current.next
            }
            return nil
        }

        /// Scroll view có diện tích lớn nhất trong trang (bỏ scroll view ngang nhỏ như dải chip).
        private static func primaryScrollView(in root: UIView?) -> UIScrollView? {
            guard let root else { return nil }
            var best: UIScrollView?
            var bestArea: CGFloat = 0
            var queue: [UIView] = [root]
            while !queue.isEmpty {
                let view = queue.removeFirst()
                if let scrollView = view as? UIScrollView, !(view is UITextView) {
                    let area = scrollView.bounds.width * scrollView.bounds.height
                    if area > bestArea {
                        best = scrollView
                        bestArea = area
                    }
                    continue
                }
                queue.append(contentsOf: view.subviews)
            }
            return best
        }

        private static func isLargeTitleVisible(in bar: UINavigationBar, title: String) -> Bool {
            guard !title.isEmpty, let label = largeTitleLabel(in: bar, title: title) else { return true }
            var alpha: CGFloat = 1
            var current: UIView? = label
            while let view = current, view !== bar {
                if view.isHidden { return false }
                alpha *= view.alpha
                current = view.superview
            }
            if alpha < 0.5 { return false }
            let frame = label.convert(label.bounds, to: bar)
            guard frame.height > 0 else { return false }
            return frame.intersection(bar.bounds).height >= frame.height * 0.5
        }

        private static func largeTitleLabel(in root: UIView, title: String) -> UILabel? {
            for view in root.subviews {
                if let label = view as? UILabel, label.text == title, label.font.pointSize >= largeTitleMinPointSize {
                    return label
                }
                if let found = largeTitleLabel(in: view, title: title) { return found }
            }
            return nil
        }
    }
}
