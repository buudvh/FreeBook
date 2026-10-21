import SwiftData
import SwiftUI
import UIKit

/// Mở một mục của hub và toàn bộ luồng sheet màn Thông báo.
///
/// Phần sheet chuyển **nguyên văn** từ container của widget thông báo nổi cũ (đã xoá ở 1.3.524),
/// chỉ đổi chủ của khoá/`modelContainer`/`setSheetPresented` sang `FloatingHubWindowManager`. Năm điểm không
/// được bỏ: nhánh `presentedViewController` trong `FloatingHubUIWindow.hitTest` (luật 25), móc `.onDisappear`
/// + `presentationControllerDidDismiss` (luật 26), `.modelContainer` (thiếu là crash), gán delegate trong
/// completion, và cửa sổ sống suốt lúc sheet mở (`FloatingHubWindowManager.setSheetPresented`).
extension FloatingHubContainerViewController: UIAdaptivePresentationControllerDelegate {
    /// Mở một mục: menu đóng, hub thu về nép mép ngay (việc đã xong), rồi giao cho chủ của mục đó. Riêng AI
    /// (1.3.558): menu **giữ mở** và chuyển sang trang "AI đang chạy" để chọn truyện (`openAITask`).
    ///
    /// Dòng xám đã `disabled` trong menu; guard ở đây chặn thêm đường VoiceOver và lượt chạm lọt vào đúng lúc
    /// trạng thái vừa đổi.
    ///
    /// AI tự tìm view controller trên cùng **chỉ trong window `.normal`** (`AIRuntimeCoordinator.presentFullScreen`),
    /// Video giao cho closure do phiên phát gắn (`VideoMiniPlayerState.onReopen`), nên cả hai không phụ thuộc
    /// cửa sổ của hub. Chỉ màn Thông báo được trình bày từ chính cửa sổ này.
    func open(_ kind: FloatingHubItem.Kind) {
        guard isItemEnabled(kind) else { return }
        if kind == .ai {
            showMenuPage(.aiTasks)
            return
        }
        closeMenu(animated: false)
        viewModel.hide()
        updateLayout(animated: true)

        switch kind {
        case .ai:
            break
        case .notifications:
            presentInbox()
        case .video:
            guard let reopen = VideoMiniPlayerState.shared.onReopen else {
                AppLogger.shared.log("❌ [FloatingHub] Mục Video đang hoạt động nhưng chưa gắn onReopen")
                return
            }
            reopen()
        }
    }

    /// Chạm một truyện ở trang "AI đang chạy": đóng menu, hub nép mép, mở màn AI của **đúng** truyện đó.
    func openAITask(bookId: String) {
        guard isItemEnabled(.ai),
              presentationReader.snapshot.aiTasks.contains(where: { $0.bookId == bookId }) else { return }
        closeMenu(animated: false)
        viewModel.hide()
        updateLayout(animated: true)
        AIRuntimeCoordinator.shared.presentFullScreen(bookId: bookId)
    }

    // MARK: - Nút của dòng Video

    /// Phát/dừng video nền. Menu **giữ nguyên** để người dùng thấy glyph đổi ngay trên dòng.
    func toggleVideoPlayback() {
        guard isItemEnabled(.video) else { return }
        guard let toggle = VideoMiniPlayerState.shared.onTogglePlay else {
            AppLogger.shared.log("❌ [FloatingHub] Mục Video đang hoạt động nhưng chưa gắn onTogglePlay")
            return
        }
        toggle()
    }

    /// Dừng hẳn video nền. Menu giữ nguyên: phiên phát `reset()` cầu nối ⇒ dòng Video tự chuyển xám.
    func stopVideo() {
        guard isItemEnabled(.video) else { return }
        guard let stop = VideoMiniPlayerState.shared.onStop else {
            AppLogger.shared.log("❌ [FloatingHub] Mục Video đang hoạt động nhưng chưa gắn onStop")
            return
        }
        stop()
    }

    private func isItemEnabled(_ kind: FloatingHubItem.Kind) -> Bool {
        presentationReader.snapshot.items.first(where: { $0.kind == kind })?.isEnabled == true
    }

    // MARK: - Màn Thông báo

    private func presentInbox() {
        guard presentedViewController == nil else { return }
        viewModel.cancelTasks()

        let inbox = NotificationInboxView(onOpenBook: { [weak self] book in
            guard let self else { return }
            self.openReader(for: book)
        })
        // Móc bắt **mọi** đường đóng sheet. `presentationControllerDidDismiss` chỉ chạy khi người dùng **vuốt
        // xuống**, còn nút "Đóng" trong màn Thông báo gọi `@Environment(\.dismiss)` — đường lập trình, không
        // có callback nào của UIKit. Thiếu móc này thì `isSheetPresented` kẹt ở `true`, nút nổi **biến mất
        // vĩnh viễn** sau lần đầu đóng sheet bằng nút. Hai cơ chế cố ý chồng nhau: `setSheetPresented` idempotent,
        // và hậu quả của việc kẹt cờ đủ nặng để đáng trả giá một lời gọi thừa.
        let content = inbox.onDisappear {
            FloatingHubWindowManager.shared.setSheetPresented(false)
        }
        let root: AnyView
        if let container = FloatingHubWindowManager.shared.modelContainer {
            // Bắt buộc: cửa sổ phụ **không** có `modelContainer` trong environment, mà `NotificationInboxView`
            // `@Query` bảng `Book` — thiếu dòng này là crash ngay khi mở.
            root = AnyView(content.modelContainer(container))
        } else {
            root = AnyView(content)
        }

        let hosting = UIHostingController(rootView: root)
        hosting.view.backgroundColor = .clear

        FloatingHubWindowManager.shared.setSheetPresented(true)
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
            FloatingHubWindowManager.bookIdUserInfoKey: book.bookId,
            FloatingHubWindowManager.extensionPackageIdUserInfoKey: book.extensionPackageId,
            FloatingHubWindowManager.chapterIndexUserInfoKey: book.currentChapterIndex,
            FloatingHubWindowManager.detailUrlUserInfoKey: book.detailUrl,
            FloatingHubWindowManager.sourceNameUserInfoKey: book.sourceName
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
        FloatingHubWindowManager.shared.setSheetPresented(false)
    }
}
