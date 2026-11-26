import SwiftUI
import UIKit

/// View controller vô hình gắn vào nội dung sheet để tìm `presentationController` của **chính** sheet đó và đặt
/// `SheetDismissDelegateProxy` lên nó. Lúc `isDirty`, proxy từ chối mọi lượt đóng do người dùng (vuốt xuống, chạm ra
/// ngoài sheet) ⇒ `onAttempt`.
///
/// Tìm theo chuỗi `parent` từ chính probe lên gốc (view controller được trình bày), **không** lấy "view controller
/// đang trình bày trên cùng": màn có sheet con (vd bảng chọn script của Script editor) sẽ ra nhầm presentation controller.
/// Cài lại ở mỗi `updateUIViewController` vì SwiftUI có thể gán lại delegate của nó giữa chừng.
struct SheetDismissAttemptProbe: UIViewControllerRepresentable {
    /// Có nội dung chưa lưu ⇒ proxy chặn đóng. Đọc lúc UIKit hỏi (`presentationControllerShouldDismiss`), nên luôn là giá
    /// trị của lượt cập nhật view gần nhất.
    let isDirty: Bool
    let onAttempt: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> ProbeViewController {
        let controller = ProbeViewController()
        let coordinator = context.coordinator
        controller.onDidAppear = { [weak coordinator] probe in
            coordinator?.install(from: probe, logsFailure: true)
        }
        return controller
    }

    func updateUIViewController(_ controller: ProbeViewController, context: Context) {
        context.coordinator.onAttempt = onAttempt
        context.coordinator.isDirty = isDirty
        // Lượt update đầu có thể chạy trước khi probe vào cây view controller ⇒ chưa tìm được, không log.
        context.coordinator.install(from: controller, logsFailure: false)
    }

    static func dismantleUIViewController(_ controller: ProbeViewController, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator {
        var onAttempt: () -> Void = {}
        var isDirty = false
        private weak var proxy: SheetDismissDelegateProxy?
        private var didLogMissing = false

        func install(from controller: UIViewController, logsFailure: Bool) {
            guard let presentationController = Self.presentationController(of: controller) else {
                if logsFailure && !didLogMissing {
                    didLogMissing = true
                    AppLogger.shared.log("❌ [SheetDismissGuard] Không tìm thấy presentationController của sheet — vuốt xuống sẽ đóng thẳng, không hỏi \"Bỏ thay đổi?\"")
                }
                return
            }
            let proxy = SheetDismissDelegateProxy.install(on: presentationController)
            proxy.setHandlers(
                owner: self,
                shouldBlock: { [weak self] in self?.isDirty ?? false },
                onAttempt: { [weak self] in self?.onAttempt() }
            )
            self.proxy = proxy
        }

        /// Probe bị gỡ (sheet đóng, hoặc nội dung sheet bị dựng lại): trả delegate gốc cho presentation controller nếu
        /// chưa có probe mới nhận proxy — probe mới (nếu có) sẽ cài lại ở lượt update của nó.
        func detach() {
            proxy?.uninstall(owner: self)
            proxy = nil
        }

        /// Gốc của chuỗi `parent` phải là view controller **được trình bày** (có `presentingViewController`).
        /// Probe chưa được gắn làm view controller con ⇒ đi theo responder chain của view lên view controller gần nhất.
        private static func presentationController(of controller: UIViewController) -> UIPresentationController? {
            var root = controller
            if root.parent == nil, let enclosing = enclosingViewController(of: controller.view) {
                root = enclosing
            }
            while let parent = root.parent {
                root = parent
            }
            guard root.presentingViewController != nil else { return nil }
            return root.presentationController
        }

        private static func enclosingViewController(of view: UIView) -> UIViewController? {
            var responder: UIResponder? = view.superview
            while let current = responder {
                if let viewController = current as? UIViewController { return viewController }
                responder = current.next
            }
            return nil
        }
    }

    final class ProbeViewController: UIViewController {
        var onDidAppear: ((UIViewController) -> Void)?

        override func viewDidLoad() {
            super.viewDidLoad()
            view.isUserInteractionEnabled = false
            view.backgroundColor = .clear
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            onDidAppear?(self)
        }
    }
}
