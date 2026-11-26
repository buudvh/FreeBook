import ObjectiveC
import UIKit

/// Delegate **trung gian** đặt lên `presentationController` của một sheet SwiftUI để **chặn** lượt đóng do người dùng khi
/// sheet có nội dung chưa lưu và báo lượt bị chặn — SwiftUI không có API nào báo sự kiện này. Chặn bằng
/// `presentationControllerShouldDismiss` (1.3.1066) chứ không bằng `isModalInPresentation`: UIKit hỏi hàm này cho **cả**
/// vuốt xuống lẫn chạm ra ngoài sheet, còn `isModalInPresentation` bỏ qua hẳn chạm ngoài.
///
/// Bất biến quan trọng nhất: **mọi** callback của delegate gốc (của SwiftUI) phải tới được nó. SwiftUI đưa binding
/// `isPresented`/`item` của `.sheet` về `false` trong `presentationControllerDidDismiss`; nuốt mất callback đó là sheet
/// kẹt "đang mở" và không mở lại được nữa. Vì vậy:
/// - bốn callback vòng đời được cài tường minh và luôn gọi tiếp bản gốc;
/// - mọi selector khác (vd `sheetPresentationControllerDidChangeSelectedDetentIdentifier` của sheet có nấc) đi qua
///   `responds(to:)` + `forwardingTarget(for:)` sang bản gốc; **không** tự cài `adaptivePresentationStyle` vì giá trị
///   trả về sẽ đè mặc định của UIKit.
///
/// Vòng đời: `delegate` của UIKit là tham chiếu yếu nên proxy được giữ bằng associated object **trên chính presentation
/// controller** — sống đúng bằng sheet, không phụ thuộc view probe (probe có thể bị dựng lại giữa chừng, vd Reader đổi
/// chương làm SwiftUI dựng lại nội dung sheet). Mỗi presentation controller có tối đa một proxy.
///
/// `original` giữ **mạnh**: `responds(to:)` trả lời theo `original`, nếu nó bị giải phóng giữa chừng mà UIKit vẫn gửi
/// selector đã hỏi thì `forwardingTarget` trả `nil` ⇒ crash "unrecognized selector". Vòng giữ tham chiếu
/// (presentation controller → proxy → delegate gốc) được cắt ở `uninstall(owner:)` khi probe cuối cùng bị gỡ.
///
/// `@MainActor` tường minh (giao thức delegate của UIKit vốn đã là main actor); riêng `responds(to:)`/`forwardingTarget(for:)`
/// là override của `NSObject` không cô lập nên khai `nonisolated` và đọc `original` qua `nonisolated(unsafe)`.
@MainActor
final class SheetDismissDelegateProxy: NSObject, UISheetPresentationControllerDelegate {
    /// Khoá associated object — con trỏ cố định suốt vòng đời app.
    private static let associationKey = UnsafeRawPointer(UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1))

    /// Delegate gốc (thường là của SwiftUI). UIKit chỉ gọi delegate trên main thread.
    nonisolated(unsafe) var original: UIAdaptivePresentationControllerDelegate?

    /// Presentation controller đang mang proxy — để `uninstall` trả lại delegate gốc.
    private weak var host: UIPresentationController?
    private var attemptHandler: (() -> Void)?
    /// `true` ⇒ từ chối lượt đóng do người dùng (vuốt / chạm ngoài) và gọi `attemptHandler`.
    private var shouldBlockHandler: (() -> Bool)?
    /// Chủ của `attemptHandler` hiện tại: probe cũ bị gỡ **sau** khi probe mới đã gắn thì không được xoá handler mới.
    private var handlerOwner: ObjectIdentifier?

    /// Lấy (hoặc tạo) proxy của `presentationController` và bảo đảm nó đang là delegate. Gọi lại nhiều lần an toàn:
    /// nếu SwiftUI đã gán lại delegate của nó thì proxy bọc delegate mới đó.
    static func install(on presentationController: UIPresentationController) -> SheetDismissDelegateProxy {
        let proxy: SheetDismissDelegateProxy
        if let existing = objc_getAssociatedObject(presentationController, associationKey) as? SheetDismissDelegateProxy {
            proxy = existing
        } else {
            proxy = SheetDismissDelegateProxy()
            objc_setAssociatedObject(presentationController, associationKey, proxy, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        if presentationController.delegate !== proxy {
            proxy.original = presentationController.delegate
            presentationController.delegate = proxy
        }
        proxy.host = presentationController
        return proxy
    }

    func setHandlers(owner: AnyObject, shouldBlock: @escaping () -> Bool, onAttempt: @escaping () -> Void) {
        handlerOwner = ObjectIdentifier(owner)
        shouldBlockHandler = shouldBlock
        attemptHandler = onAttempt
    }

    /// Probe chủ hiện tại bị gỡ ⇒ trả delegate gốc cho presentation controller, bỏ associated object và nhả `original`
    /// (cắt vòng giữ tham chiếu). Probe cũ bị gỡ sau khi probe mới đã nhận proxy ⇒ không làm gì.
    func uninstall(owner: AnyObject) {
        guard handlerOwner == ObjectIdentifier(owner) else { return }
        handlerOwner = nil
        attemptHandler = nil
        shouldBlockHandler = nil
        if let host {
            if host.delegate === self {
                host.delegate = original
            }
            objc_setAssociatedObject(host, Self.associationKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        host = nil
        original = nil
    }

    // MARK: - Callback vòng đời (luôn gọi tiếp bản gốc)

    /// Có nội dung chưa lưu ⇒ không cho đóng và báo ngay: chạm ra ngoài sheet chưa chắc được UIKit báo tiếp qua
    /// `presentationControllerDidAttemptToDismiss`. Nếu UIKit vẫn báo thì handler chạy lần hai — vô hại (chỉ bật cờ hiện
    /// hộp hỏi).
    func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
        if shouldBlockHandler?() == true {
            attemptHandler?()
            return false
        }
        return original?.presentationControllerShouldDismiss?(presentationController) ?? true
    }

    func presentationControllerWillDismiss(_ presentationController: UIPresentationController) {
        original?.presentationControllerWillDismiss?(presentationController)
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        original?.presentationControllerDidDismiss?(presentationController)
    }

    func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
        original?.presentationControllerDidAttemptToDismiss?(presentationController)
        attemptHandler?()
    }

    // MARK: - Chuyển tiếp mọi selector còn lại

    nonisolated override func responds(to aSelector: Selector!) -> Bool {
        if super.responds(to: aSelector) { return true }
        return original?.responds(to: aSelector) ?? false
    }

    nonisolated override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if let original, original.responds(to: aSelector) { return original }
        return super.forwardingTarget(for: aSelector)
    }
}
