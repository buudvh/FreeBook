import Combine
import SwiftData
import SwiftUI
import UIKit

/// View controller của **widget thông báo nổi**: sở hữu `UIPanGestureRecognizer`/`UITapGestureRecognizer`,
/// cập nhật frame trực tiếp trên `UIView`, và mở màn Thông báo khi người dùng chạm.
///
/// Kéo/thả bằng UIKit (không phải cử chỉ SwiftUI) đúng như `FloatingWidgetContainerViewController` và
/// `BrowserFloatingWidgetContainerViewController`: ngón tay không bị trễ theo vòng cập nhật state.
///
/// ## Một cỡ, hai vị trí
/// Khác hai widget kia, nút ở đây **không** đổi kích thước giữa hai trạng thái (người dùng chốt
/// 2026-10-07): `.peeking` chỉ là nút **ngậm vào mép** (tâm nằm đúng trên mép nên một nửa ra ngoài), còn
/// `.revealed` là nút nằm trong màn với lề ngang nhỏ. Nhờ vậy animation thu/bung chỉ là dịch chuyển, không
/// phải đổi kích thước view.
///
/// ## Chạm là **mở màn Thông báo**, không phải bung
/// Nút này chỉ có **một** hành động (yêu cầu của người dùng: "bấm vào sẽ hiển thị ra màn hình thông báo"),
/// nên chạm ở **cả hai** trạng thái đều mở màn Thông báo. Bung khỏi mép bằng cách **kéo** ra (kéo bắt đầu
/// là bung ngay, như widget TTS) hoặc tự bung khi có thông báo mới.
@MainActor
final class NotificationFloatingWidgetContainerViewController: UIViewController,
                                                               UIGestureRecognizerDelegate,
                                                               UIAdaptivePresentationControllerDelegate {
    private let viewModel = NotificationFloatingWidgetViewModel()
    private let presentationReader = NotificationFloatingWidgetPresentationReader()

    let widgetContainerView = UIView()
    private var hostingController: UIHostingController<NotificationFloatingWidgetButton>?
    private var panStartCenter: CGPoint = .zero
    private var cancellables = Set<AnyCancellable>()
    private var unreadCount = 0

    private var panGesture: UIPanGestureRecognizer!
    private var tapGesture: UITapGestureRecognizer!

    enum Layout {
        static let size: CGFloat = NotificationFloatingWidgetButton.size
        /// Lề ngang khi nút ở dạng bung — nhỏ, vì nút vốn đã nhỏ.
        static let horizontalMargin: CGFloat = 8
        static let verticalMargin: CGFloat = 12
        /// Thả trong khoảng này tính là "dán mép" ⇒ thu gọn.
        static let edgeSnapDistance: CGFloat = 26
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        widgetContainerView.backgroundColor = .clear
        widgetContainerView.clipsToBounds = false
        widgetContainerView.layer.masksToBounds = false
        view.addSubview(widgetContainerView)

        unreadCount = presentationReader.snapshot.unreadCount
        let hosting = UIHostingController(rootView: makeButton())
        hosting.view.backgroundColor = .clear
        hosting.view.clipsToBounds = false
        hosting.view.layer.masksToBounds = false

        addChild(hosting)
        widgetContainerView.addSubview(hosting.view)
        hosting.didMove(toParent: self)
        self.hostingController = hosting

        setupGestures()
        bindState()
        updateLayout(animated: false)
    }

    private func makeButton() -> NotificationFloatingWidgetButton {
        NotificationFloatingWidgetButton(
            unreadCount: unreadCount,
            mode: viewModel.mode,
            edge: viewModel.edgeDirection
        )
    }

    private func setupGestures() {
        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.delegate = self
        panGesture.cancelsTouchesInView = true
        widgetContainerView.addGestureRecognizer(panGesture)

        tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tapGesture.delegate = self
        tapGesture.cancelsTouchesInView = true
        widgetContainerView.addGestureRecognizer(tapGesture)
    }

    private func bindState() {
        presentationReader.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in
                guard let self else { return }
                guard snapshot.unreadCount != self.unreadCount else { return }
                self.unreadCount = snapshot.unreadCount
                self.refreshContent()
            }
            .store(in: &cancellables)

        viewModel.$mode
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.refreshContent()
                if !self.viewModel.isDragging {
                    self.updateLayout(animated: true)
                }
            }
            .store(in: &cancellables)

        // Badge đổi phía theo mép ⇒ nội dung phải vẽ lại khi cạnh đổi (chỉ xảy ra lúc nhả tay).
        viewModel.$edgeDirection
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshContent()
            }
            .store(in: &cancellables)
    }

    private func refreshContent() {
        hostingController?.rootView = makeButton()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !viewModel.isDragging {
            updateLayout(animated: false)
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate { [weak self] _ in
            self?.updateLayout(animated: false)
        }
    }

    /// Kẹp tâm Y trong vùng an toàn — nút không bao giờ chui vào thanh trạng thái hay thanh tab.
    private func clampedY(_ value: CGFloat, screenHeight: CGFloat) -> CGFloat {
        FloatingWidgetGeometry.clampedCenterY(
            value,
            widgetHeight: Layout.size,
            screenHeight: screenHeight,
            topMargin: view.safeAreaInsets.top + Layout.verticalMargin,
            bottomMargin: view.safeAreaInsets.bottom + Layout.verticalMargin
        )
    }

    private func restingCenter(in bounds: CGRect) -> CGPoint {
        guard bounds.width > 0, bounds.height > 0 else { return .zero }
        let y = clampedY(viewModel.verticalRatio * bounds.height, screenHeight: bounds.height)

        if viewModel.mode == .peeking {
            // Tâm nằm **đúng trên mép** ⇒ một nửa nút ra ngoài, đúng dáng "cất vào mép" của widget TTS.
            let x = viewModel.edgeDirection == .left ? 0 : bounds.width
            return CGPoint(x: x, y: y)
        }

        let x = FloatingWidgetGeometry.restingCenterX(
            edge: viewModel.edgeDirection,
            widgetWidth: Layout.size,
            screenWidth: bounds.width,
            horizontalMargin: Layout.horizontalMargin
        )
        return CGPoint(x: x, y: y)
    }

    /// Vẽ lại vị trí theo `mode` hiện tại. `internal` để window manager gọi được từ file khác.
    func updateLayout(animated: Bool) {
        guard view.bounds.width > 0, view.bounds.height > 0 else { return }
        let targetCenter = restingCenter(in: view.bounds)
        let targetSize = CGSize(width: Layout.size, height: Layout.size)

        let applyLayout = {
            self.widgetContainerView.bounds = CGRect(origin: .zero, size: targetSize)
            self.widgetContainerView.center = targetCenter
            self.hostingController?.view.frame = self.widgetContainerView.bounds
            self.view.layoutIfNeeded()
        }

        if animated {
            UIView.animate(
                withDuration: 0.34,
                delay: 0,
                usingSpringWithDamping: 0.82,
                initialSpringVelocity: 0,
                options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut],
                animations: applyLayout,
                completion: nil
            )
        } else {
            applyLayout()
        }
    }

    /// Bung nút ra khỏi mép (gọi khi có thông báo mới, hoặc từ window manager).
    func reveal(animated: Bool) {
        viewModel.reveal()
        updateLayout(animated: animated)
    }

    // MARK: - Cử chỉ

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let container = self.view else { return }
        switch gesture.state {
        case .began:
            viewModel.handleDragStart()
            panStartCenter = widgetContainerView.center
            // Kéo từ trạng thái thu gọn là bung ra ngay: kéo một nửa nút đang ngậm mép là thao tác khó.
            if viewModel.mode == .peeking {
                viewModel.reveal()
                updateLayout(animated: true)
                panStartCenter = widgetContainerView.center
            }
        case .changed:
            let translation = gesture.translation(in: container)
            let rawX = panStartCenter.x + translation.x
            let rawY = panStartCenter.y + translation.y
            widgetContainerView.center = CGPoint(
                x: rawX,
                y: clampedY(rawY, screenHeight: container.bounds.height)
            )
        case .ended, .cancelled:
            let bounds = container.bounds
            viewModel.handleDragEnd(
                finalPosition: widgetContainerView.center,
                widgetSize: Layout.size,
                screenWidth: bounds.width,
                screenHeight: bounds.height,
                topMargin: view.safeAreaInsets.top + Layout.verticalMargin,
                bottomMargin: view.safeAreaInsets.bottom + Layout.verticalMargin,
                edgeSnapDistance: Layout.edgeSnapDistance
            )
            updateLayout(animated: true)
        default:
            break
        }
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard !viewModel.isDragging else { return }
        presentInbox()
    }

    // MARK: - Màn Thông báo

    private func presentInbox() {
        guard presentedViewController == nil else { return }
        viewModel.cancelTasks()

        let inbox = NotificationInboxView(onOpenBook: { [weak self] book in
            guard let self else { return }
            self.openReader(for: book)
        })
        let root: AnyView
        if let container = NotificationFloatingWidgetWindowManager.shared.modelContainer {
            // Bắt buộc: cửa sổ phụ **không** có `modelContainer` trong environment, mà `NotificationInboxView`
            // `@Query` bảng `Book` — thiếu dòng này là crash ngay khi mở.
            root = AnyView(inbox.modelContainer(container))
        } else {
            root = AnyView(inbox)
        }

        let hosting = UIHostingController(rootView: root)
        hosting.view.backgroundColor = .clear

        NotificationFloatingWidgetWindowManager.shared.setSheetPresented(true)
        present(hosting, animated: true) { [weak self] in
            // Gán **sau** khi trình bày: `presentationController` chỉ tồn tại từ lúc trình bày trở đi, gán
            // trước đó là gán vào `nil` và mất luôn đường bắt sự kiện vuốt-để-đóng.
            hosting.presentationController?.delegate = self
        }
    }

    /// Mở truyện vừa chạm trong màn Thông báo: đóng sheet rồi bàn giao cho `ShelfView` — nó là nơi duy nhất
    /// giữ `fullScreenCover` của Reader. Chờ đóng xong mới phát thông báo, cùng lý do đã ghi ở
    /// `ShelfView.swift:306-307`: hai lớp trình bày không được tranh nhau.
    private func openReader(for book: Book) {
        let payload: [String: Any] = [
            NotificationFloatingWidgetWindowManager.bookIdUserInfoKey: book.bookId,
            NotificationFloatingWidgetWindowManager.extensionPackageIdUserInfoKey: book.extensionPackageId,
            NotificationFloatingWidgetWindowManager.chapterIndexUserInfoKey: book.currentChapterIndex,
            NotificationFloatingWidgetWindowManager.detailUrlUserInfoKey: book.detailUrl,
            NotificationFloatingWidgetWindowManager.sourceNameUserInfoKey: book.sourceName
        ]

        let finish = { [weak self] in
            self?.handleSheetDismissed()
            NotificationCenter.default.post(
                name: .openReaderFromNotification,
                object: nil,
                userInfo: payload
            )
        }

        if let presented = presentedViewController {
            presented.dismiss(animated: true) { finish() }
        } else {
            finish()
        }
    }

    /// Vuốt xuống để đóng sheet cũng phải trả nút về đúng trạng thái — nếu chỉ xử lý ở nút "Đóng" thì nút
    /// nổi sẽ biến mất vĩnh viễn sau một lần vuốt.
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        handleSheetDismissed()
    }

    private func handleSheetDismissed() {
        NotificationFloatingWidgetWindowManager.shared.setSheetPresented(false)
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        return false
    }
}
