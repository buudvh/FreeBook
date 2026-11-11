import SwiftUI
import UIKit

/// Trình bày **sheet nằm trên mọi viên thuốc** (anh Bửu 2026-11-11: "mọi sheet mở ra từ viên thuốc đều không ẩn các viên
/// thuốc mà chỉ hiển thị cao hơn viên thuốc" — tránh mở sheet rồi lại bấm viên thuốc khác mở chồng sheet nữa).
///
/// Sheet của cửa sổ chính nằm **dưới** các cửa sổ viên thuốc (đĩa nghe `alert − 1.75`, hub `alert − 2` / `− 1.7`, trình duyệt
/// thu nhỏ `alert − 3`). Sheet mở qua đây nằm ở cửa sổ riêng `OverlaySheetWindow` level `alert − 1.6`: trên mọi viên thuốc,
/// dưới ngăn kéo `…` (`alert − 1.5`) và toast — viên thuốc không bị ẩn, chỉ nằm dưới lớp mờ của sheet, không bấm được.
/// Dùng cho: sheet "đang đọc chương này" của Reader, sheet nút "+" của Chi tiết và của Kệ sách. Sheet của chính đĩa / hub
/// tự trình bày ở cửa sổ của chúng (đã nằm trên các viên khác).
///
/// - Nội dung tự gắn kiểu sheet (`presentationDetents`, nền kính…) như mọi sheet SwiftUI; host gắn màu nhấn ở gốc.
/// - `dismiss(then:)` đóng sheet **xong** mới chạy việc kèm theo (trình bày từ sheet đang đóng thì UIKit đóng luôn màn mới).
/// - Không có ô nhập chữ trong sheet ở đây: cửa sổ phủ không bao giờ key. Bước cần bàn phím (Kệ › "Từ URL") đóng sheet rồi mở
///   sheet thường ở cửa sổ chính.
/// - Cửa sổ chỉ hiện trong lúc có sheet; rảnh thì ẩn.
@MainActor
final class OverlaySheetPresenter: ObservableObject {
    static let shared = OverlaySheetPresenter()

    struct Request: Identifiable {
        let id = UUID()
        let content: AnyView
    }

    @Published var request: Request?

    /// Trên đĩa nghe (`alert − 1.75`) và hub lúc trình bày sheet (`alert − 1.7`), dưới ngăn kéo `…` (`alert − 1.5`).
    static let windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue - 1.6)

    private var window: OverlaySheetWindow?
    /// Đã nhận một lượt trình bày (kể cả lúc `request` chưa gán — gán ở nhịp sau) ⇒ từ chối lượt khác.
    private var isBusy = false
    private var afterDismiss: (() -> Void)?

    private init() {}

    /// Trình bày `content`; `false` ⇒ đang có sheet khác hoặc chưa có scene (chỗ gọi tự lùi về sheet thường).
    @discardableResult
    func present<Content: View>(@ViewBuilder _ content: () -> Content) -> Bool {
        guard !isBusy, let window = ensureWindow() else { return false }
        isBusy = true
        afterDismiss = nil
        window.isHidden = false
        let view = AnyView(content())
        // Chờ một nhịp: cửa sổ vừa hiện, host chưa kịp vào cây hiển thị ⇒ trình bày ngay có thể bị UIKit bỏ qua.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.request = Request(content: view)
            }
        }
        return true
    }

    /// Đóng sheet rồi mới chạy `action`; không có sheet ⇒ chạy luôn. Sheet **đang đóng** (chạm dòng thứ hai trong lúc
    /// sheet trượt xuống) ⇒ bỏ qua, kẻo việc chạy hai lần.
    func dismiss(then action: (() -> Void)? = nil) {
        guard isBusy else {
            action?()
            return
        }
        guard request != nil else { return }
        afterDismiss = action
        request = nil
    }

    /// `onDismiss` của `.sheet` (`OverlaySheetHost`) — mọi đường đóng (vuốt, code) đều qua đây (luật 26).
    func didDismiss() {
        isBusy = false
        window?.isHidden = true
        let action = afterDismiss
        afterDismiss = nil
        action?()
    }

    private func ensureWindow() -> OverlaySheetWindow? {
        guard let scene = AppMainWindowScene.current() else { return nil }
        if let window {
            if window.windowScene !== scene { window.windowScene = scene }
            return window
        }
        let controller = UIViewController()
        controller.view.backgroundColor = .clear
        let host = UIHostingController(rootView: AnyView(OverlaySheetHost().appAccentTint()))
        host.view.backgroundColor = .clear
        host.safeAreaRegions = []
        host.view.isUserInteractionEnabled = false
        host.view.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        controller.addChild(host)
        controller.view.addSubview(host.view)
        host.didMove(toParent: controller)

        let win = OverlaySheetWindow(windowScene: scene)
        win.windowLevel = Self.windowLevel
        win.backgroundColor = .clear
        win.rootViewController = controller
        // Không bao giờ `makeKeyAndVisible()`: lớp phủ không giành key của cửa sổ chính.
        win.isHidden = true
        window = win
        return win
    }
}
