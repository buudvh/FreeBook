import SwiftUI
import UIKit

/// Cửa sổ nổi riêng trình bày ngăn kéo menu (`SideDrawerMenuModifier`).
///
/// ## Vì sao bỏ `fullScreenCover`
/// Khi cover còn trên màn, iOS không cho màn bên dưới trình bày sheet / hộp thoại mới, nên hàng nào mở sheet đều phải
/// chờ: trượt ra → gỡ cover (UIKit vẫn chạy hiệu ứng gỡ dù đã tắt animation) → `onDismiss` → một nhịp runloop → mới
/// chạy action ⇒ sheet hiện chậm thấy rõ. Cửa sổ riêng không chặn việc trình bày của cửa sổ chính, nên action chạy
/// ngay khi ngăn kéo bắt đầu trượt ra; sheet / hộp thoại của màn trượt lên phía dưới trong lúc ngăn kéo trượt đi.
///
/// ## Cửa sổ
/// - Level `alert - 1.5` (1.3.651): **dưới** widget TTS (`alert - 1`) và toast (`alert`), **trên** hub (`alert - 2`) và
///   trình duyệt thu nhỏ (`alert - 3`). Widget TTS luôn nổi trên ngăn kéo và lớp tối (điều khiển nghe được khi menu mở);
///   hub/trình duyệt nằm dưới, nếu không bấm hub mở Thông báo / menu của hub lúc ngăn kéo đang mở thì menu "…" bị che.
///   Lịch sử: `alert - 0.5` (1.3.628–647, trên mọi widget — từ khi nền nhoè thật thì widget bị che hẳn); `alert - 3.5`
///   (1.3.648–650, dưới mọi widget).
/// - **Không bao giờ** `makeKeyAndVisible()`: sheet, bàn phím, first responder vẫn ở cửa sổ chính; các chỗ tìm cửa sổ
///   chính theo `isKeyWindow` / level `.normal` không vớ nhầm cửa sổ này.
/// - Một host dùng chung: mỗi lúc chỉ một ngăn kéo. Mở ngăn kéo khác khi một cái đang mở ⇒ thay, và màn cũ được trả
///   `isPresented = false` (không thì nút "…" của nó không bật lại được).
/// - Bắt đầu đóng ⇒ cửa sổ thôi nhận chạm ngay; trượt xong ⇒ `isHidden = true` và gỡ nội dung (nhả các closure giữ state
///   của màn). Cửa sổ ẩn được giữ lại để lần mở sau không phải dựng lại.
///
/// ## Nhận diện chỗ gắn
/// Mỗi modifier có một `ownerID` riêng; mọi lệnh cập nhật / đóng chỉ có hiệu lực khi đúng chủ đang mở — hai ngăn kéo
/// gắn chồng trên một màn hay mỗi hàng của `List` một ngăn kéo không đè hay đóng nhầm của nhau. Mỗi lượt mở có `token`
/// riêng để callback trễ của lượt cũ (hoàn tất hiệu ứng, hẹn giờ dự phòng) không đụng lượt mới.
@MainActor
final class SideDrawerMenuWindowManager {
    static let shared = SideDrawerMenuWindowManager()

    /// Ngăn kéo đang hiện (hoặc đang trượt ra).
    private struct Session {
        let ownerID: UUID
        let token: UUID
        var title: String
        let openedAt: CFTimeInterval
        /// Trả `isPresented` của màn sở hữu về `false`.
        let resetPresented: () -> Void
        var isClosing = false
        /// Lúc bắt đầu đóng (chạm hàng / chạm ngoài / vuốt) — mốc tính ms cho log.
        var closeStartedAt: CFTimeInterval?
    }

    private var window: SideDrawerMenuOverlayWindow?
    private var hostingController: SideDrawerMenuHostingController?
    private var session: Session?

    private init() {}

    // MARK: - API cho `SideDrawerMenuModifier`

    /// Mở ngăn kéo của `ownerID`. Trả `false` khi không có scene để gắn cửa sổ (nơi gọi tự hạ `isPresented`).
    @discardableResult
    func present(
        ownerID: UUID,
        title: String,
        content: @escaping () -> AnyView,
        resetPresented: @escaping () -> Void
    ) -> Bool {
        if let current = session, current.ownerID == ownerID, !current.isClosing {
            update(ownerID: ownerID, title: title, content: content)
            return true
        }
        guard let scene = Self.activeWindowScene else {
            AppLogger.shared.log("❌ [Drawer] Không tìm thấy UIWindowScene để mở ngăn kéo \"\(title)\"")
            return false
        }

        let previous = session
        let token = UUID()
        let (window, host) = prepareWindow(in: scene)
        session = Session(
            ownerID: ownerID,
            token: token,
            title: title,
            openedAt: CACurrentMediaTime(),
            resetPresented: resetPresented
        )
        window.isUserInteractionEnabled = true
        host.rootView = makeRoot(token: token, title: title, content: content)
        window.isHidden = false
        host.setNeedsStatusBarAppearanceUpdate()
        host.setNeedsUpdateOfHomeIndicatorAutoHidden()
        log("Mở \"\(title)\"")

        // Ngăn kéo của chỗ gắn khác đang mở ⇒ bị thay; hạ `isPresented` của nó sau khi `session` đã là lượt mới, để
        // `onChange` bên đó gọi `dismiss` thì không trúng lượt này.
        if let previous, previous.ownerID != ownerID, !previous.isClosing {
            previous.resetPresented()
        }
        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .screenChanged, argument: host.view)
        }
        return true
    }

    /// Màn sở hữu vừa vẽ lại ⇒ thay nội dung bằng bản mới nhất (công tắc / dấu chọn theo state của màn). Bỏ qua khi
    /// không phải chủ đang mở hoặc ngăn kéo đã bắt đầu đóng (nội dung đứng yên trong lúc trượt ra).
    func update(ownerID: UUID, title: String, content: @escaping () -> AnyView) {
        guard var current = session, current.ownerID == ownerID, !current.isClosing else { return }
        current.title = title
        session = current
        hostingController?.rootView = makeRoot(token: current.token, title: title, content: content)
    }

    /// Gỡ ngay, không hiệu ứng: màn sở hữu rời cây view, hoặc nơi gọi tự hạ `isPresented` khi ngăn kéo còn mở. Đang
    /// trượt ra thì để hiệu ứng chạy nốt (cửa sổ đã thôi nhận chạm, hẹn giờ dự phòng bảo đảm sẽ ẩn).
    func dismiss(ownerID: UUID) {
        guard let current = session, current.ownerID == ownerID, !current.isClosing else { return }
        log("Gỡ ngay \"\(current.title)\" (màn rời đi hoặc tự tắt)")
        hideWindow()
    }

    // MARK: - Callback từ `SideDrawerMenuPanel`

    private func makeRoot(token: UUID, title: String, content: @escaping () -> AnyView) -> SideDrawerMenuWindowRoot {
        SideDrawerMenuWindowRoot(
            presentation: SideDrawerMenuWindowRoot.Presentation(
                token: token,
                title: title,
                content: content,
                onAppeared: { [weak self] in
                    self?.panelDidAppear(token: token)
                },
                onCloseBegan: { [weak self] followUp in
                    self?.beginClose(token: token, followUp: followUp)
                },
                onClosed: { [weak self] in
                    self?.finishClose(token: token)
                }
            )
        )
    }

    private func panelDidAppear(token: UUID) {
        guard let current = session, current.token == token else { return }
        log("Ngăn kéo bắt đầu trượt vào sau \(Self.milliseconds(since: current.openedAt)) ms kể từ lúc mở")
    }

    /// Ngăn kéo vừa bắt đầu trượt ra: thôi nhận chạm, trả `isPresented` về `false`, rồi chạy **ngay** action của hàng
    /// vừa chọn (nếu có) — màn bên dưới trình bày sheet / hộp thoại được luôn vì cửa sổ này không chặn.
    private func beginClose(token: UUID, followUp: (() -> Void)?) {
        guard var current = session, current.token == token, !current.isClosing else { return }
        let tappedAt = CACurrentMediaTime()
        current.isClosing = true
        current.closeStartedAt = tappedAt
        session = current
        window?.isUserInteractionEnabled = false

        if followUp == nil {
            log("Bắt đầu đóng \"\(current.title)\" (chạm ra ngoài / vuốt)")
        } else {
            log("Chạm hàng thao tác ở \"\(current.title)\"")
        }
        current.resetPresented()

        guard let followUp else { return }
        log("Action chạy sau \(Self.milliseconds(since: tappedAt)) ms kể từ lúc chạm")
        followUp()
        log("Action xong sau \(Self.milliseconds(since: tappedAt)) ms kể từ lúc chạm")
    }

    /// Ngăn kéo đã trượt ra hết (hoặc hẹn giờ dự phòng tới hạn).
    private func finishClose(token: UUID) {
        guard let current = session, current.token == token, current.isClosing else { return }
        hideWindow()
        if let closeStartedAt = current.closeStartedAt {
            log("Cửa sổ ẩn sau \(Self.milliseconds(since: closeStartedAt)) ms kể từ lúc chạm")
        }
    }

    // MARK: - Cửa sổ

    private func prepareWindow(in scene: UIWindowScene) -> (SideDrawerMenuOverlayWindow, SideDrawerMenuHostingController) {
        if let window, let hostingController {
            if window.windowScene !== scene {
                window.windowScene = scene
            }
            return (window, hostingController)
        }

        let host = SideDrawerMenuHostingController(rootView: SideDrawerMenuWindowRoot(presentation: nil))
        host.view.backgroundColor = .clear
        host.view.accessibilityViewIsModal = true

        let win = SideDrawerMenuOverlayWindow(windowScene: scene)
        win.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue - 1.5)
        win.backgroundColor = .clear
        win.rootViewController = host
        // Không bao giờ `makeKeyAndVisible()`: đây là lớp phủ, không phải cửa sổ chính.
        win.isHidden = true

        window = win
        hostingController = host
        return (win, host)
    }

    /// Ẩn cửa sổ và gỡ nội dung — không để lớp vô hình nào chặn chạm, không giữ closure của màn đã đóng.
    private func hideWindow() {
        session = nil
        window?.isUserInteractionEnabled = false
        window?.isHidden = true
        hostingController?.rootView = SideDrawerMenuWindowRoot(presentation: nil)
        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .screenChanged, argument: nil)
        }
    }

    private static var activeWindowScene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first(where: { $0.activationState == .foregroundActive })
            ?? scenes.first(where: { $0.activationState == .foregroundInactive })
            ?? scenes.first
    }

    // MARK: - Log

    /// Log đo thời gian cho người dùng tự đo trên máy; chỉ ghi khi bật log (không gắn ❌).
    private func log(_ message: @autoclosure () -> String) {
        guard AppLogger.shared.isLoggingEnabled else { return }
        AppLogger.shared.log("[Drawer] \(message())")
    }

    private static func milliseconds(since start: CFTimeInterval) -> String {
        String(format: "%.0f", (CACurrentMediaTime() - start) * 1000)
    }
}
