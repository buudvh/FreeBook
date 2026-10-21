import SwiftData
import SwiftUI
import UIKit

/// **Presenter duy nhất** của `LegadoPresentationEventCenter` (spec §10.8, §11.5): subscriber UI của engine nguồn Legado,
/// gắn một lần ở `AppLaunchRootView` (`legadoPresentationHandler`). Không subscriber nào khác được lặp `stream`
/// (`AsyncStream` một người đọc) — sự kiện cho màn khác được chuyển tiếp (vd `LegadoExploreRefreshSignal`).
///
/// - Trình duyệt / ô mã xác minh trình bày bằng UIKit từ **view controller trên cùng** (cửa sổ mức thường): sheet SwiftUI
///   ở root không hiện được khi đang có sheet/fullScreenCover khác (màn chi tiết nguồn, trình đọc…).
/// - Không trình bày được ⇒ trả ngay kết quả "không có người dùng" để thread engine không chờ tới hết giờ.
/// - Chỉ Huỷ / Xong / Xác nhận đóng được (chặn vuốt đóng); mọi lối đóng đều trả kết quả cho engine đúng một lần.
/// - Engine hết giờ/huỷ (`.dismiss`) ⇒ đóng màn tương ứng, không trả kết quả lần nữa.
@MainActor
final class LegadoPresentationPresenter {
    static let shared = LegadoPresentationPresenter()

    /// Số lần thử trình bày lại (mỗi 0,25 s) khi màn trên cùng đang mở/đóng dở.
    private static let presentAttempts = 20

    private var isRunning = false
    var modelContainer: ModelContainer?
    /// Yêu cầu trình duyệt / mã xác minh đang hiện.
    private var active: (id: UUID, controller: UIViewController)?
    /// Yêu cầu engine đã huỷ (`.dismiss`) khi màn của nó còn đang chờ trình bày lại ⇒ bỏ, không trình bày nữa.
    private var withdrawnIds: Set<UUID> = []

    private init() {}

    /// Vòng nghe sự kiện — gọi từ `.task` của view gốc (chạy tới khi task bị huỷ). Gọi lần hai khi đang chạy ⇒ bỏ qua.
    func run(container: ModelContainer) async {
        modelContainer = container
        guard !isRunning else { return }
        isRunning = true
        let center = LegadoPresentationEventCenter.shared
        center.attachPresenter()
        defer {
            center.detachPresenter()
            isRunning = false
        }
        for await event in center.stream {
            handle(event)
        }
    }

    private func handle(_ event: LegadoPresentationEvent) {
        switch event {
        case .browser(let request):
            presentBrowser(request)
        case .verificationCode(let request):
            presentVerification(request)
        case .dismiss(let requestId):
            dismissActive(requestId)
        case .refreshExplore(let sourceKey):
            LegadoExploreRefreshSignal.shared.notify(sourceKey: sourceKey)
        case .toast(let message, let sourceName, _):
            let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            ToastManager.shared.show(message: sourceName.isEmpty ? text : "\(sourceName): \(text)", type: .info)
        case .searchBook(let keyword, let sourceKey):
            presentSearch(keyword: keyword, sourceKey: sourceKey)
        case .openURL(let url, let sourceKey):
            openURL(url, sourceKey: sourceKey)
        case .refreshContent(let sourceKey):
            // Trình đọc đang mở của sách thuộc nguồn này nạp lại chương hiện tại (`legadoContentRefresh`).
            LegadoContentRefreshSignal.shared.notify(sourceKey: sourceKey)
        }
    }

    // MARK: - Trình duyệt / mã xác minh

    private func presentBrowser(_ request: LegadoBrowserRequest) {
        let id = request.id
        let sheet = LegadoBrowserSheet(request: request) { [weak self] snapshot, cancelled in
            let result = LegadoBrowserResult(html: snapshot.html, finalURL: snapshot.finalURL,
                                             httpCookies: snapshot.cookies, cancelled: cancelled)
            LegadoPresentationEventCenter.shared.completeBrowser(id: id, result: result)
            self?.dismissActive(id)
        }
        let host = UIHostingController(rootView: sheet)
        host.modalPresentationStyle = .overFullScreen
        host.isModalInPresentation = true
        present(host, id: id) {
            LegadoPresentationEventCenter.shared.completeBrowser(id: id, result: .unavailable)
        }
    }

    private func presentVerification(_ request: LegadoVerificationRequest) {
        let id = request.id
        let sheet = LegadoVerificationCodeSheet(request: request) { [weak self] code in
            LegadoPresentationEventCenter.shared.completeVerification(id: id, code: code)
            self?.dismissActive(id)
        }
        let host = UIHostingController(rootView: sheet)
        host.modalPresentationStyle = .pageSheet
        host.isModalInPresentation = true
        if let sheetController = host.sheetPresentationController {
            sheetController.detents = [.medium(), .large()]
        }
        present(host, id: id) {
            LegadoPresentationEventCenter.shared.completeVerification(id: id, code: nil)
        }
    }

    /// Trình bày `controller` từ màn trên cùng; màn đó đang mở/đóng dở ⇒ thử lại. Hết lượt ⇒ `onFailure`.
    private func present(_ controller: UIViewController, id: UUID, attempt: Int = 0, onFailure: @escaping () -> Void) {
        if withdrawnIds.remove(id) != nil { return }
        if let top = Self.topViewController() {
            active = (id: id, controller: controller)
            top.present(controller, animated: true)
            return
        }
        guard attempt < Self.presentAttempts else {
            AppLogger.shared.log("❌ [LegadoPresenter] Không trình bày được yêu cầu của nguồn (không có màn trên cùng)")
            onFailure()
            return
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            self?.present(controller, id: id, attempt: attempt + 1, onFailure: onFailure)
        }
    }

    /// Đóng màn của yêu cầu `id` nếu đang hiện (đóng luôn mọi thứ trình bày bên trên nó).
    func dismissActive(_ id: UUID) {
        guard let current = active, current.id == id else {
            // Chưa kịp trình bày (đang thử lại) ⇒ đánh dấu để vòng thử lại bỏ qua. Giữ tập nhỏ.
            if withdrawnIds.count > 32 { withdrawnIds.removeAll() }
            withdrawnIds.insert(id)
            return
        }
        active = nil
        current.controller.presentingViewController?.dismiss(animated: true)
    }

    /// Trình bày một màn phụ (tìm kiếm, trình duyệt `openUrl`, hộp xác nhận) từ màn trên cùng; không có ⇒ bỏ qua + log.
    func presentAuxiliary(_ controller: UIViewController) {
        guard let top = Self.topViewController() else {
            AppLogger.shared.log("❌ [LegadoPresenter] Không có màn để trình bày yêu cầu phụ của nguồn")
            return
        }
        top.present(controller, animated: true)
    }

    /// View controller trên cùng của cửa sổ mức thường đang hiện (bỏ cửa sổ nổi của hub/TTS/toast); `nil` khi màn đó đang
    /// mở hoặc đóng dở.
    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else {
            return nil
        }
        let windows = scene.windows.filter { $0.windowLevel == .normal && !$0.isHidden }
        guard let window = windows.first(where: { $0.isKeyWindow }) ?? windows.first,
              let root = window.rootViewController else { return nil }
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        if top.isBeingPresented || top.isBeingDismissed { return nil }
        return top
    }
}
