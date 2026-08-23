import Foundation
import UIKit

/// Mở share sheet cho bản xuất truyện — **chủ sở hữu duy nhất** của việc trình bày `UIActivityViewController`
/// cho file xuất.
///
/// Trước 1.3.253 việc này nằm trong `DownloadManager.presentShareSheet` ở tầng Services: nó `import UIKit`,
/// tự đi tìm `rootViewController` và tự `asyncAfter(0.5)` khi màn hình đang chuyển cảnh. Hệ quả là một tác
/// vụ xuất xong lúc app ở background thì share sheet **mất luôn**, người dùng phải vào trình theo dõi bấm
/// chia sẻ lại. Nay tầng Services chỉ phát `DownloadPresentationEvent.exportReady`, còn coordinator này:
///
/// * giữ **một** bàn giao đang chờ (`pendingFileURL`) nếu chưa trình bày được;
/// * thử lại vài nhịp ngắn khi view controller đang được present/dismiss;
/// * và được `MainTabView` gọi lại `flushPendingShare()` mỗi lần `scenePhase == .active`, nên bản xuất hoàn
///   thành trong background vẫn hiện share sheet ngay khi người dùng mở app lên.
@MainActor
final class ExportShareCoordinator {
    static let shared = ExportShareCoordinator()

    /// Số nhịp thử lại ngắn (0.5s/nhịp) trước khi nhường cho `flushPendingShare()` lúc app active.
    private static let maxImmediateRetries = 6

    private var pendingFileURL: URL?
    private var retryCount = 0
    private var isPresenting = false

    private init() {}

    /// Nhận yêu cầu chia sẻ từ event `exportReady`. File phải tồn tại thật, nếu không thì báo lỗi ngay.
    func requestShare(filePath: String, bookTitle: String) {
        guard FileManager.default.fileExists(atPath: filePath) else {
            ToastManager.shared.show(message: "Tệp xuất không tồn tại hoặc đã bị xóa.", type: .error)
            return
        }
        pendingFileURL = URL(fileURLWithPath: filePath)
        retryCount = 0
        AppLogger.shared.log("📤 [ExportShareCoordinator] Bản xuất '\(bookTitle)' đã sẵn sàng chia sẻ.")
        flushPendingShare()
    }

    /// Thử trình bày bàn giao đang chờ. Gọi được nhiều lần, không có bàn giao thì không làm gì.
    func flushPendingShare() {
        guard !isPresenting, let fileURL = pendingFileURL else { return }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            pendingFileURL = nil
            return
        }
        guard let host = presentableViewController() else {
            scheduleRetry()
            return
        }

        pendingFileURL = nil
        retryCount = 0
        present(fileURL: fileURL, from: host)
    }

    private func scheduleRetry() {
        guard retryCount < Self.maxImmediateRetries else { return }
        retryCount += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.flushPendingShare()
        }
    }

    /// View controller trên cùng của scene đang foreground, `nil` khi chưa trình bày được.
    private func presentableViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let windowScene = scenes.first(where: { $0.activationState == .foregroundActive }),
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first,
              let rootVC = window.rootViewController else {
            return nil
        }

        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        if topVC.isBeingPresented || topVC.isBeingDismissed {
            return nil
        }
        return topVC
    }

    private func present(fileURL: URL, from host: UIViewController) {
        let activityVC = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)

        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = host.view
            popover.sourceRect = CGRect(x: host.view.bounds.midX, y: host.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }

        isPresenting = true
        activityVC.completionWithItemsHandler = { [weak self] _, _, _, _ in
            self?.isPresenting = false
        }
        host.present(activityVC, animated: true, completion: nil)
    }
}
