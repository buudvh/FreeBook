import UIKit

/// Một hộp thoại `alert()` / `confirm()` / `prompt()` của trang trong trình duyệt nhỏ nguồn Legado
/// (`LegadoBrowserController`, dùng chung cho đăng nhập trên web và `java.startBrowser*`).
///
/// WebKit giữ JS của trang đứng chờ tới khi completion handler của hộp thoại được gọi, và completion bị bỏ không gọi là
/// lỗi lập trình (trang treo, WebKit báo ngoại lệ). Vì vậy `reply` là **một lần**: nút bấm, không trình bày được, hay
/// trình duyệt đóng giữa chừng (`cancel()` từ `tearDown`) — đường nào tới trước thì trả, các đường sau bị bỏ. Đóng trình
/// duyệt từ ngoài (presenter đóng cả chuỗi màn khi engine hết giờ) gỡ luôn `UIAlertController` mà không chạy action nào,
/// nên `cancel()` là lưới an toàn bắt buộc.
@MainActor
final class LegadoBrowserJSPanel {
    enum Kind {
        case alert
        case confirm
        case prompt(defaultText: String?)
    }

    /// Số lần thử trình bày lại (mỗi 0,25 s) khi màn trên cùng đang mở/đóng dở — trang hay gọi `alert()` ngay lúc nạp,
    /// đúng lúc trình duyệt còn đang trượt lên.
    private static let presentAttempts = 12

    /// `confirmed` = bấm OK; `text` = chữ trong ô của `prompt`.
    private var reply: ((_ confirmed: Bool, _ text: String?) -> Void)?

    init(reply: @escaping (_ confirmed: Bool, _ text: String?) -> Void) {
        self.reply = reply
    }

    /// Trình bày hộp thoại trên màn trên cùng của cửa sổ chứa `webView`. Màn đó đang mở/đóng dở ⇒ thử lại; hết lượt
    /// (hoặc `webView` đã mất) ⇒ trả kết quả mặc định — không để trang treo. Đã trả rồi (trình duyệt đóng lúc chờ) ⇒ thôi.
    func present(_ kind: Kind, title: String, message: String, over webView: UIView, attempt: Int = 0) {
        guard reply != nil else { return }
        guard let presenter = Self.topController(startingAt: webView.window?.rootViewController)
                ?? LegadoPresentationPresenter.topViewController() else {
            guard attempt < Self.presentAttempts else {
                AppLogger.shared.log("❌ [LegadoBrowser] Không trình bày được hộp thoại của trang — trả mặc định")
                cancel()
                return
            }
            // Giữ `self` (mạnh) trong lượt chờ ngắn: hộp thoại bị giải phóng khi chưa trả là completion bị bỏ.
            Task { @MainActor [weak webView] in
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard let webView else {
                    self.cancel()
                    return
                }
                self.present(kind, title: title, message: message, over: webView, attempt: attempt + 1)
            }
            return
        }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        switch kind {
        case .alert:
            alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
                self?.finish(confirmed: true, text: nil)
            })
        case .confirm:
            alert.addAction(UIAlertAction(title: "Huỷ", style: .cancel) { [weak self] _ in
                self?.finish(confirmed: false, text: nil)
            })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
                self?.finish(confirmed: true, text: nil)
            })
        case .prompt(let defaultText):
            alert.addTextField { field in
                field.text = defaultText
            }
            alert.addAction(UIAlertAction(title: "Huỷ", style: .cancel) { [weak self] _ in
                self?.finish(confirmed: false, text: nil)
            })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self, weak alert] _ in
                self?.finish(confirmed: true, text: alert?.textFields?.first?.text ?? "")
            })
        }
        presenter.present(alert, animated: true)
    }

    /// Trả kết quả mặc định (alert: đóng; confirm: `false`; prompt: `nil`) nếu chưa trả.
    func cancel() {
        finish(confirmed: false, text: nil)
    }

    private func finish(confirmed: Bool, text: String?) {
        guard let reply else { return }
        self.reply = nil
        reply(confirmed, text)
    }

    /// Màn trên cùng của chuỗi trình bày bắt đầu từ `root`; `nil` khi không có hoặc màn đó đang mở/đóng dở.
    private static func topController(startingAt root: UIViewController?) -> UIViewController? {
        guard var top = root else { return nil }
        while let presented = top.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        if top.isBeingPresented || top.isBeingDismissed { return nil }
        return top
    }
}
