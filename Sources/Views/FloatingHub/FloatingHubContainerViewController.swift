import Combine
import SwiftUI
import UIKit

/// View controller của **nút hub nổi** (1.3.524): sở hữu cử chỉ kéo/chạm và cập nhật frame trực tiếp trên
/// `UIView`. Chạm nút ⇒ **sheet hub** (`FloatingHubSheet`, thay thẻ menu nổi từ 2026-11-11) giữ ở `FloatingHubSheetHost`
/// (view 1×1 trong cửa sổ hub); hành động mở mục, nút của dòng Video và sheet Thông báo ở `+Actions.swift`; giữ chỗ với
/// widget nổi khác ở `+Placement.swift`.
///
/// Kéo/thả bằng UIKit (không phải cử chỉ SwiftUI): ngón tay không bị trễ theo vòng cập nhật state.
///
/// ## Nửa viên thuốc dính mép (anh Bửu duyệt mockup 2026-11-11)
/// Nút là nửa viên cao 36 **luôn dính mép** trái / phải (`EdgePillShape`), không còn nép mép nửa ẩn / bung / tự thu.
/// Bắt đầu kéo ⇒ co thành hình tròn 36 đặt đúng tâm icon, theo tay; thả ⇒ bám mép gần hơn, né widget nổi khác
/// (`+Placement.swift`), lưu chỗ.
///
/// ## Cây view
/// `sheetHostingController` (1×1, không nhận chạm — chỗ giữ sheet) và `widgetContainerView` (nút hub). Không còn lớp nền
/// toàn màn hay thẻ menu: cửa sổ hub chỉ nhận chạm ở nút, hoặc cả cửa sổ khi đang trình bày sheet (luật 25).
///
/// ## Bảng chạm (cài đặt "Khi chạm hub", `FloatingHubTapBehavior`)
/// Do `activateByRunningTasks` (`+Actions.swift`) quyết. **Luôn hiện tất cả mục** (mặc định, 2026-11-06): sheet ở trang
/// chính. **Mở thẳng khi chỉ có 1 tác vụ** (bảng chốt 2026-10-22) rẽ theo **số tiến trình** của snapshot lúc chạm: 0 ⇒
/// màn Thông báo; 1 ⇒ mở thẳng mục đó (AI ⇒ sheet ở trang "Tác vụ AI"); từ 2 ⇒ sheet ở trang chính.
@MainActor
final class FloatingHubContainerViewController: UIViewController, UIGestureRecognizerDelegate {
    /// `internal` (không `private`): file `+Actions` cần dùng, mà `private` của Swift chỉ có hiệu lực
    /// trong một file — lỗi kiểu này đã làm CI 1.3.445 đỏ.
    let viewModel = FloatingHubViewModel()
    let presentationReader: FloatingHubPresentationReader
    /// Trạng thái sheet hub — `internal` vì `+Actions.swift` mở / đóng.
    let sheetState = FloatingHubSheetState()

    let widgetContainerView = UIView()

    private var sheetHostingController: UIHostingController<AnyView>?
    private var buttonHostingController: UIHostingController<FloatingHubButton>?
    private var panStartCenter: CGPoint = .zero
    private var cancellables = Set<AnyCancellable>()

    private var panGesture: UIPanGestureRecognizer!
    private var tapGesture: UITapGestureRecognizer!
    /// Lượt layout hợp lệ kế tiếp phải xếp lại để né widget nổi khác (`+Placement.swift`). Bật sẵn cho lần tạo cửa
    /// sổ đầu; `prepareForAppearance()` bật lại mỗi lần hub hiện lại. `internal` vì `+Placement.swift` hạ cờ.
    var needsPlacementResolve = true

    enum Layout {
        /// Nửa viên lúc dính mép — độ nhô đọc lúc chạy (Giao diện › Viên thuốc nổi).
        static var size: CGSize { EdgePillSettings.size(of: .hub) }
        static let height: CGFloat = EdgePillSettings.Kind.hub.height
        /// Hình tròn lúc đang kéo.
        static let dragDiameter: CGFloat = FloatingHubButton.dragDiameter
    }

    init(presentationReader: FloatingHubPresentationReader) {
        self.presentationReader = presentationReader
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        installSheetHost()

        widgetContainerView.backgroundColor = .clear
        widgetContainerView.clipsToBounds = false
        widgetContainerView.layer.masksToBounds = false
        view.addSubview(widgetContainerView)

        let hosting = UIHostingController(rootView: makeButton())
        hosting.view.backgroundColor = .clear
        hosting.view.clipsToBounds = false
        hosting.view.layer.masksToBounds = false

        addChild(hosting)
        widgetContainerView.addSubview(hosting.view)
        hosting.didMove(toParent: self)
        self.buttonHostingController = hosting

        setupGestures()
        bindState()
        updateLayout(animated: false)
    }

    private func makeButton() -> FloatingHubButton {
        FloatingHubButton(
            state: presentationReader.snapshot.button,
            edge: viewModel.isDragging ? nil : viewModel.edgeDirection,
            onActivate: { [weak self] in
                self?.handlePrimaryAction()
            }
        )
    }

    /// Chỗ giữ sheet hub: 1×1, luôn hiện, không nhận chạm (sheet là VC trình bày riêng nên vẫn nhận chạm). Cửa sổ hub
    /// không thừa hưởng `.tint` của `MainTabView` ⇒ gắn màu nhấn ở gốc.
    private func installSheetHost() {
        sheetState.onPresentedChange = { presented in
            FloatingHubWindowManager.shared.setSheetPresented(presented)
        }
        let host = FloatingHubSheetHost(state: sheetState, reader: presentationReader, actions: makeSheetActions())
        let hosting = UIHostingController(rootView: AnyView(host.appAccentTint()))
        hosting.view.backgroundColor = .clear
        hosting.safeAreaRegions = []
        hosting.view.isUserInteractionEnabled = false
        hosting.view.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        addChild(hosting)
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)
        sheetHostingController = hosting
    }

    private func makeSheetActions() -> FloatingHubSheet.Actions {
        FloatingHubSheet.Actions(
            onSelect: { [weak self] kind in self?.open(kind) },
            onTogglePlayback: { [weak self] kind in self?.togglePlayback(kind) },
            onStopPlayback: { [weak self] kind in self?.stopPlayback(kind) },
            onSelectAITask: { [weak self] bookId in self?.openAITask(bookId: bookId) },
            onSelectSourceCheck: { [weak self] kind in self?.openSourceCheck(kind) },
            onOpenInboxBook: { [weak self] book in self?.openInboxBook(book) },
            onLeaveSourceCheck: { [weak self] kind in self?.leaveSourceCheck(kind) }
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
        // Nút chỉ vẽ lại khi tập tiến trình hoặc số chưa đọc đổi — tiêu đề AI đổi theo batch không chạm tới đây.
        // Hình nút (nửa viên theo mép / tròn lúc kéo) vẽ lại ở sink `edgeDirection` + `isDragging` bên dưới.
        presentationReader.$snapshot
            .map(\.button)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshButton()
            }
            .store(in: &cancellables)

        // Sheet hub tự đọc `presentationReader` (chỉ sống khi mở) ⇒ không cần sink cho dòng / danh sách ở đây.

        // Mép đổi / bắt đầu – thôi kéo ⇒ nút vẽ lại hình (nửa viên đúng mép hoặc hình tròn).
        Publishers.CombineLatest(viewModel.$edgeDirection.removeDuplicates(), viewModel.$isDragging.removeDuplicates())
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshButton()
            }
            .store(in: &cancellables)

        // Kéo thanh "Độ nhô" của hub ở Giao diện ⇒ đổi khung ngay (đang kéo hub thì để lượt thả tay tự đặt).
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .map { _ in EdgePillSettings.width(of: .hub) }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, !self.viewModel.isDragging else { return }
                self.updateLayout(animated: false)
            }
            .store(in: &cancellables)
    }

    private func refreshButton() {
        buttonHostingController?.rootView = makeButton()
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

    // MARK: - Layout nút

    /// Kẹp tâm Y trong vùng đứng cố định `EdgePillZone` (1.3.867): dưới vùng header, trên vùng nút "+" / thanh tab — kể cả
    /// màn không có chúng, để nút không nhảy khi đổi màn. `internal` vì `+Placement.swift` dùng.
    func clampedY(_ value: CGFloat, height: CGFloat, screenHeight: CGFloat) -> CGFloat {
        FloatingWidgetGeometry.clampedCenterY(
            value,
            widgetHeight: height,
            screenHeight: screenHeight,
            topMargin: view.safeAreaInsets.top + EdgePillZone.topClearance,
            bottomMargin: view.safeAreaInsets.bottom + EdgePillZone.bottomClearance
        )
    }

    /// Tâm nửa viên dính mép đã nhớ (cạnh phẳng áp sát mép màn).
    private func restingCenter(in bounds: CGRect) -> CGPoint {
        guard bounds.width > 0, bounds.height > 0 else { return .zero }
        let y = clampedY(viewModel.verticalRatio * bounds.height, height: Layout.height, screenHeight: bounds.height)
        let halfWidth = Layout.size.width / 2
        let x = viewModel.edgeDirection == .left ? halfWidth : bounds.width - halfWidth
        return CGPoint(x: x, y: y)
    }

    /// Vẽ lại vị trí dính mép. `internal` để window manager và file `+Actions` gọi được.
    func updateLayout(animated: Bool) {
        guard view.bounds.width > 0, view.bounds.height > 0 else { return }
        // Chỉ xếp lại khi đã nằm trong cửa sổ (bounds thật) và không đang kéo — thả tay tự xếp ở `handlePan`.
        if needsPlacementResolve, view.window != nil, !viewModel.isDragging {
            resolvePlacement()
        }
        let targetCenter = restingCenter(in: view.bounds)
        let targetSize = Layout.size
        refreshPlacementSlot(centerY: targetCenter.y)

        let applyLayout = {
            self.widgetContainerView.bounds = CGRect(origin: .zero, size: targetSize)
            self.widgetContainerView.center = targetCenter
            self.buttonHostingController?.view.frame = self.widgetContainerView.bounds
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

    /// Đưa hub về trạng thái xuất hiện chuẩn (xếp lại chỗ). Window manager gọi mỗi lần hub hiện lại sau khi bị ẩn (cả
    /// cửa sổ hoặc chỉ nút).
    func prepareForAppearance() {
        needsPlacementResolve = true
        updateLayout(animated: false)
    }

    // MARK: - Cử chỉ

    /// Hành động chính của hub — đường chung cho chạm và VoiceOver (`FloatingHubButton.onActivate`).
    func handlePrimaryAction() {
        guard !viewModel.isDragging, !sheetState.isPresented else { return }
        activateByRunningTasks()
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        handlePrimaryAction()
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let container = self.view else { return }
        switch gesture.state {
        case .began:
            // Co thành hình tròn đặt đúng tâm icon (tâm đầu bo) ⇒ không giật dưới tay.
            let frame = widgetContainerView.frame
            let radius = Layout.height / 2
            let iconX = viewModel.edgeDirection == .left ? frame.maxX - radius : frame.minX + radius
            let start = CGPoint(x: iconX, y: frame.midY)
            panStartCenter = start
            viewModel.handleDragStart()
            let diameter = Layout.dragDiameter
            UIView.animate(withDuration: 0.15, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.widgetContainerView.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
                self.widgetContainerView.center = start
                self.buttonHostingController?.view.frame = self.widgetContainerView.bounds
            }
        case .changed:
            let translation = gesture.translation(in: container)
            let half = Layout.dragDiameter / 2
            let rawX = min(max(panStartCenter.x + translation.x, half), container.bounds.width - half)
            let rawY = panStartCenter.y + translation.y
            widgetContainerView.center = CGPoint(
                x: rawX,
                y: clampedY(rawY, height: Layout.dragDiameter, screenHeight: container.bounds.height)
            )
        case .ended, .cancelled, .failed:
            guard viewModel.isDragging else { return }
            let bounds = container.bounds
            viewModel.handleDragEnd(
                finalPosition: widgetContainerView.center,
                widgetHeight: Layout.height,
                screenWidth: bounds.width,
                screenHeight: bounds.height,
                topMargin: view.safeAreaInsets.top + EdgePillZone.topClearance,
                bottomMargin: view.safeAreaInsets.bottom + EdgePillZone.bottomClearance
            )
            resolvePlacement()
            updateLayout(animated: true)
        default:
            break
        }
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        return false
    }
}
