import SwiftUI
import UIKit

/// Container UIViewControllerRepresentable bọc InteractiveOverlaySheetViewController
/// để điều khiển overlay sheet kéo vuốt cho ReaderChapterListView mà không mutate SwiftUI @State ở mỗi pan frame
/// và không re-assign rootView khi không có thay đổi nội dung mục lục.
/// File này tuân thủ quy tắc 1 primary type per file (InteractiveOverlaySheetContainer là primary type duy nhất).
struct InteractiveOverlaySheetContainer<Content: View>: UIViewControllerRepresentable {
    /// Equatable configuration key dùng để gate việc cập nhật rootView của UIHostingController,
    /// tránh re-assign rootView không cần thiết khi ReaderView re-render ở tần suất cao.
    struct ConfigKey: Equatable {
        let bookId: String
        let bookTitle: String?
        let bookAuthor: String?
        let bookCoverUrl: String?
        let bookDetailUrl: String?
        let currentChapterIndex: Int
        let isTranslationEnabled: Bool
        let theme: ReaderTheme
        let onlineChaptersCount: Int
        let isLocalTXTBook: Bool
        let localBookId: String?
        let extPackageId: String?
        let storeIdentity: ObjectIdentifier
    }

    let isPresented: Bool
    let topMargin: CGFloat
    let configKey: ConfigKey
    let onDismissed: () -> Void
    let content: (_ requestDismiss: @escaping (@escaping () -> Void) -> Void) -> Content

    final class Coordinator {
        var currentConfigKey: ConfigKey?
        var dismissHandler: ((@escaping () -> Void) -> Void)?
        var onDismissed: (() -> Void)?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> ViewController {
        let vc = ViewController()
        vc.topMargin = topMargin
        vc.onDismissed = { [weak coordinator = context.coordinator] in
            coordinator?.onDismissed?()
        }

        let dismissAction: (@escaping () -> Void) -> Void = { [weak vc] completion in
            vc?.makeDismissHandler()(completion)
        }
        context.coordinator.dismissHandler = dismissAction
        context.coordinator.onDismissed = onDismissed
        context.coordinator.currentConfigKey = configKey

        vc.setupContent(rootView: content(dismissAction))
        return vc
    }

    func updateUIViewController(_ uiViewController: ViewController, context: Context) {
        uiViewController.topMargin = topMargin
        uiViewController.onDismissed = { [weak coordinator = context.coordinator] in
            coordinator?.onDismissed?()
        }
        context.coordinator.onDismissed = onDismissed

        // Gated update: Chỉ cập nhật rootView khi configKey thực sự thay đổi
        if context.coordinator.currentConfigKey != configKey {
            context.coordinator.currentConfigKey = configKey
            if let dismissAction = context.coordinator.dismissHandler {
                uiViewController.updateContent(rootView: content(dismissAction))
            }
        }

        uiViewController.updatePresentation(isPresented: isPresented)
    }

    static func dismantleUIViewController(_ uiViewController: ViewController, coordinator: Coordinator) {
        coordinator.dismissHandler = nil
        coordinator.onDismissed = nil
        uiViewController.cleanUp()
    }

    // MARK: - Internal Nested ViewController Type
    final class ViewController: UIViewController, UIGestureRecognizerDelegate {
        var topMargin: CGFloat = 60
        var onDismissed: (() -> Void)?
        var dragRegionHeight: CGFloat = 132

        private let backdropView = UIView()
        private let containerView = UIView()
        private var hostingController: UIHostingController<AnyView>?

        private enum PresentationState {
            case hidden
            case presenting
            case presented
            case dragging
            case dismissing
        }

        private var state: PresentationState = .hidden
        private var pendingCompletion: (() -> Void)?
        private var panGesture: UIPanGestureRecognizer!
        private var backdropTapGesture: UITapGestureRecognizer!
        private var isSettingUp = true
        private var hasPendingPresentation = false

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
            view.isHidden = true
            view.isUserInteractionEnabled = false

            backdropView.backgroundColor = UIColor.black.withAlphaComponent(0.4)
            backdropView.alpha = 0
            backdropView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(backdropView)

            containerView.backgroundColor = .clear
            containerView.clipsToBounds = true
            containerView.layer.cornerRadius = 16
            containerView.layer.maskedCorners = [.layerMinXMinCorner, .layerMaxXMinCorner]
            view.addSubview(containerView)

            NSLayoutConstraint.activate([
                backdropView.topAnchor.constraint(equalTo: view.topAnchor),
                backdropView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                backdropView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                backdropView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
            ])

            setupGestures()
            isSettingUp = false
        }

        private func setupGestures() {
            panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            panGesture.delegate = self
            panGesture.cancelsTouchesInView = true
            containerView.addGestureRecognizer(panGesture)

            backdropTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleBackdropTap(_:)))
            backdropView.addGestureRecognizer(backdropTapGesture)
        }

        func setupContent<V: View>(rootView: V) {
            let hosting = UIHostingController(rootView: AnyView(rootView))
            hosting.view.backgroundColor = .clear
            hosting.view.clipsToBounds = true

            addChild(hosting)
            containerView.addSubview(hosting.view)
            hosting.view.frame = containerView.bounds
            hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            hosting.didMove(toParent: self)
            self.hostingController = hosting
        }

        func updateContent<V: View>(rootView: V) {
            hostingController?.rootView = AnyView(rootView)
        }

        func makeDismissHandler() -> (@escaping () -> Void) -> Void {
            return { [weak self] completion in
                DispatchQueue.main.async {
                    self?.requestDismiss(completion: completion)
                }
            }
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            let totalHeight = view.bounds.height
            let totalWidth = view.bounds.width
            guard totalHeight > 0, totalWidth > 0 else { return }

            let panelHeight = max(0, totalHeight - topMargin)
            containerView.frame = CGRect(x: 0, y: topMargin, width: totalWidth, height: panelHeight)

            if state == .hidden {
                containerView.transform = CGAffineTransform(translationX: 0, y: panelHeight)
                backdropView.alpha = 0

                if hasPendingPresentation {
                    hasPendingPresentation = false
                    presentOverlay()
                }
            } else if state == .presented {
                containerView.transform = .identity
                backdropView.alpha = 0.4
            }
        }

        func updatePresentation(isPresented: Bool) {
            guard !isSettingUp else { return }

            if isPresented {
                if state == .hidden {
                    let totalHeight = view.bounds.height
                    let totalWidth = view.bounds.width
                    if totalHeight > 0 && totalWidth > 0 {
                        hasPendingPresentation = false
                        presentOverlay()
                    } else {
                        hasPendingPresentation = true
                    }
                }
            } else {
                hasPendingPresentation = false
                if state == .presented || state == .dragging || state == .presenting {
                    dismissOverlay(completion: nil)
                }
            }
        }

        private func presentOverlay() {
            containerView.layer.removeAllAnimations()
            backdropView.layer.removeAllAnimations()
            state = .presenting
            view.isHidden = false
            view.isUserInteractionEnabled = true
            view.layoutIfNeeded()

            let panelHeight = containerView.bounds.height
            containerView.transform = CGAffineTransform(translationX: 0, y: panelHeight)
            backdropView.alpha = 0

            if UIAccessibility.isReduceMotionEnabled {
                containerView.transform = .identity
                backdropView.alpha = 0.4
                state = .presented
            } else {
                UIView.animate(
                    withDuration: 0.3,
                    delay: 0,
                    options: [.curveEaseOut, .beginFromCurrentState],
                    animations: {
                        self.containerView.transform = .identity
                        self.backdropView.alpha = 0.4
                    },
                    completion: { finished in
                        if finished && self.state == .presenting {
                            self.state = .presented
                        }
                    }
                )
            }
        }

        func requestDismiss(completion: @escaping () -> Void) {
            if state == .dismissing {
                if self.pendingCompletion == nil {
                    self.pendingCompletion = completion
                }
                return
            }
            guard state == .presented || state == .dragging || state == .presenting else {
                return
            }
            dismissOverlay(completion: completion)
        }

        private func dismissOverlay(completion: (() -> Void)?) {
            guard state != .dismissing else { return }
            if let completion = completion {
                self.pendingCompletion = completion
            }
            containerView.layer.removeAllAnimations()
            backdropView.layer.removeAllAnimations()
            state = .dismissing

            let panelHeight = containerView.bounds.height > 0 ? containerView.bounds.height : (view.bounds.height - topMargin)

            let finishDismiss = { [weak self] in
                guard let self = self, self.state == .dismissing else { return }
                self.state = .hidden
                self.view.isHidden = true
                self.view.isUserInteractionEnabled = false
                self.containerView.transform = CGAffineTransform(translationX: 0, y: panelHeight)
                self.backdropView.alpha = 0

                let comp = self.pendingCompletion
                self.pendingCompletion = nil
                let onDismissedCallback = self.onDismissed
                onDismissedCallback?()

                if let comp = comp {
                    DispatchQueue.main.async {
                        comp()
                    }
                }
            }

            if UIAccessibility.isReduceMotionEnabled {
                finishDismiss()
            } else {
                UIView.animate(
                    withDuration: 0.25,
                    delay: 0,
                    options: [.curveEaseOut, .beginFromCurrentState],
                    animations: {
                        self.containerView.transform = CGAffineTransform(translationX: 0, y: panelHeight)
                        self.backdropView.alpha = 0
                    },
                    completion: { finished in
                        if finished {
                            finishDismiss()
                        }
                    }
                )
            }
        }

        @objc private func handleBackdropTap(_ gesture: UITapGestureRecognizer) {
            requestDismiss {}
        }

        @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard state == .presented || state == .dragging else { return }

            let translation = gesture.translation(in: containerView)
            let velocity = gesture.velocity(in: containerView)
            let panelHeight = containerView.bounds.height

            switch gesture.state {
            case .began:
                state = .dragging
            case .changed:
                let rawY = translation.y
                let clampedY: CGFloat
                if rawY < 0 {
                    clampedY = rawY * 0.2
                } else {
                    clampedY = rawY
                }
                containerView.transform = CGAffineTransform(translationX: 0, y: clampedY)
                if panelHeight > 0 {
                    let progress = max(0, min(1, 1 - (clampedY / panelHeight)))
                    backdropView.alpha = progress * 0.4
                }
            case .ended:
                let rawY = translation.y
                let shouldDismiss = rawY > 120 || (rawY > 40 && velocity.y > 500)
                if shouldDismiss {
                    dismissOverlay(completion: nil)
                } else {
                    snapBack()
                }
            case .cancelled, .failed:
                if state == .dragging {
                    snapBack()
                }
            default:
                break
            }
        }

        private func snapBack() {
            guard state == .dragging || state == .presented else { return }
            containerView.layer.removeAllAnimations()
            backdropView.layer.removeAllAnimations()

            if UIAccessibility.isReduceMotionEnabled {
                containerView.transform = .identity
                backdropView.alpha = 0.4
                state = .presented
            } else {
                UIView.animate(
                    withDuration: 0.35,
                    delay: 0,
                    usingSpringWithDamping: 0.82,
                    initialSpringVelocity: 0,
                    options: [.allowUserInteraction, .beginFromCurrentState],
                    animations: {
                        self.containerView.transform = .identity
                        self.backdropView.alpha = 0.4
                    },
                    completion: { finished in
                        if finished && self.state == .dragging {
                            self.state = .presented
                        }
                    }
                )
            }
        }

        // MARK: - UIGestureRecognizerDelegate
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            if gestureRecognizer === panGesture {
                let location = touch.location(in: containerView)
                return location.y <= dragRegionHeight
            }
            return true
        }

        override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            if gestureRecognizer === panGesture {
                let velocity = panGesture.velocity(in: containerView)
                return velocity.y > 0 && abs(velocity.y) > abs(velocity.x)
            }
            return true
        }

        func cleanUp() {
            state = .hidden
            pendingCompletion = nil
            onDismissed = nil

            containerView.layer.removeAllAnimations()
            backdropView.layer.removeAllAnimations()

            view.isHidden = true
            view.isUserInteractionEnabled = false

            if let pan = panGesture {
                containerView.removeGestureRecognizer(pan)
            }
            if let tap = backdropTapGesture {
                backdropView.removeGestureRecognizer(tap)
            }

            if let hosting = hostingController {
                hosting.willMove(toParent: nil)
                hosting.view.removeFromSuperview()
                hosting.removeFromParent()
                hostingController = nil
            }
        }
    }
}
