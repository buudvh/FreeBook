import SwiftData
import SwiftUI
import UIKit

/// Mở một mục của hub (từ sheet hub hoặc chạm thẳng nút) và toàn bộ luồng sheet màn Thông báo.
///
/// Phần sheet chuyển **nguyên văn** từ container của widget thông báo nổi cũ (đã xoá ở 1.3.524),
/// chỉ đổi chủ của khoá/`modelContainer`/`setSheetPresented` sang `FloatingHubWindowManager`. Năm điểm không
/// được bỏ: nhánh `presentedViewController` trong `FloatingHubUIWindow.hitTest` (luật 25), móc `.onDisappear`
/// + `presentationControllerDidDismiss` (luật 26), `.modelContainer` (thiếu là crash), gán delegate trong
/// completion, và cửa sổ sống suốt lúc sheet mở (`FloatingHubWindowManager.setSheetPresented`).
extension FloatingHubContainerViewController: UIAdaptivePresentationControllerDelegate {
    /// Mở một mục: sheet hub đóng **xong** rồi mới giao cho chủ của mục đó (`FloatingHubSheetState.dismiss(then:)` — trình
    /// bày từ sheet đang đóng thì UIKit đóng luôn màn mới). Sheet không mở (cài đặt "Mở thẳng") ⇒ mở ngay. Riêng AI
    /// (1.3.558) và Kiểm tra nguồn có hai lượt (1.3.697): sang trang con của sheet để chọn (`showSheetPage`).
    ///
    /// Dòng xám đã `disabled` trong sheet; guard ở đây chặn thêm đường VoiceOver và lượt chạm lọt vào đúng lúc
    /// trạng thái vừa đổi.
    ///
    /// AI tự tìm view controller trên cùng **chỉ trong window `.normal`** (`AIRuntimeCoordinator.presentFullScreen`),
    /// Video giao cho closure do phiên phát gắn (`VideoMiniPlayerState.onReopen`), nên không phụ thuộc cửa sổ của hub. Chỉ
    /// màn Thông báo được trình bày từ chính cửa sổ này.
    func open(_ kind: FloatingHubItem.Kind) {
        guard isItemEnabled(kind) else { return }
        switch kind {
        case .ai:
            showSheetPage(.aiTasks)
        case .sourceCheck:
            let entries = presentationReader.snapshot.sourceChecks
            if entries.count > 1 {
                showSheetPage(.sourceChecks)
            } else if let entry = entries.first {
                openSourceCheck(entry.kind)
            }
        case .notifications:
            sheetState.dismiss { [weak self] in
                self?.presentInbox()
            }
        case .video:
            sheetState.dismiss {
                guard let reopen = VideoMiniPlayerState.shared.onReopen else {
                    AppLogger.shared.log("❌ [FloatingHub] Mục Video đang hoạt động nhưng chưa gắn onReopen")
                    return
                }
                reopen()
            }
        }
    }

    /// Chạm một truyện ở trang "Tác vụ AI": đóng sheet, mở màn AI của **đúng** truyện đó.
    func openAITask(bookId: String) {
        guard isItemEnabled(.ai),
              presentationReader.snapshot.aiTasks.contains(where: { $0.bookId == bookId }) else { return }
        sheetState.dismiss {
            AIRuntimeCoordinator.shared.presentFullScreen(bookId: bookId)
        }
    }

    /// Mở lại màn kiểm tra của một lượt đang thu nhỏ: đóng sheet, `MinimizedSourceCheckCoordinator` trình bày
    /// màn từ cửa sổ mức thường (không phụ thuộc cửa sổ của hub).
    func openSourceCheck(_ kind: MinimizedSourceCheck.Kind) {
        guard isItemEnabled(.sourceCheck),
              presentationReader.snapshot.sourceChecks.contains(where: { $0.kind == kind }) else { return }
        sheetState.dismiss {
            MinimizedSourceCheckCoordinator.shared.reopen(kind)
        }
    }

    /// Sheet đang mở ⇒ chuyển trang; chưa mở ⇒ mở thẳng ở trang đó.
    private func showSheetPage(_ page: FloatingHubSheet.Page) {
        if sheetState.isPresented {
            sheetState.page = page
        } else {
            sheetState.present(page: page)
        }
    }

    // MARK: - Chạm nút hub

    /// Chạm nút hub (sheet đang đóng), theo cài đặt "Khi chạm hub" (`FloatingHubTapBehavior`, đọc lúc chạm):
    ///
    /// **Luôn hiện tất cả mục** (mặc định, người dùng chốt 2026-11-06): sheet ở trang chính, dù có 0, 1 hay nhiều tiến
    /// trình — kể cả khi tiến trình duy nhất là AI (chạm dòng Trợ lý AI mới sang trang "Tác vụ AI").
    ///
    /// **Mở thẳng khi chỉ có 1 tác vụ** (bảng chạm chốt 2026-10-22) — rẽ theo số tiến trình của snapshot **lúc
    /// chạm**:
    /// - 0 ⇒ màn Thông báo.
    /// - 1 ⇒ mở thẳng mục đó, đúng như chạm dòng của nó trong sheet (AI / Kiểm tra nguồn hai lượt ⇒ sheet ở trang con).
    /// - Từ 2 ⇒ sheet ở trang chính.
    ///
    /// Tập tiến trình đổi đúng lúc chạm (AI vừa xong) thì `open(_:)` đã guard `isItemEnabled`.
    func activateByRunningTasks() {
        if FloatingHubTapBehavior.current == .alwaysMenu {
            sheetState.present(page: .main)
            return
        }
        let button = presentationReader.snapshot.button
        switch button.runningCount {
        case 0:
            open(.notifications)
        case 1:
            open(button.runningKinds[0])
        default:
            sheetState.present(page: .main)
        }
    }

    // MARK: - Nút của dòng Video

    /// Phát/dừng video nền. Sheet **giữ nguyên** để người dùng thấy glyph đổi ngay trên dòng.
    func togglePlayback(_ kind: FloatingHubItem.Kind) {
        guard isItemEnabled(kind) else { return }
        let toggle: (() -> Void)?
        switch kind {
        case .video:
            toggle = VideoMiniPlayerState.shared.onTogglePlay
        case .ai, .notifications, .sourceCheck:
            return
        }
        guard let toggle else {
            AppLogger.shared.log("❌ [FloatingHub] Mục \(kind.title) đang hoạt động nhưng chưa gắn onTogglePlay")
            return
        }
        toggle()
    }

    /// Dừng hẳn video nền. Sheet giữ nguyên: phiên phát `reset()` cầu nối ⇒ dòng tự chuyển xám.
    func stopPlayback(_ kind: FloatingHubItem.Kind) {
        guard isItemEnabled(kind) else { return }
        let stop: (() -> Void)?
        switch kind {
        case .video:
            stop = VideoMiniPlayerState.shared.onStop
        case .ai, .notifications, .sourceCheck:
            return
        }
        guard let stop else {
            AppLogger.shared.log("❌ [FloatingHub] Mục \(kind.title) đang hoạt động nhưng chưa gắn onStop")
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

        let inbox = NotificationInboxView(onOpenBook: { [weak self] book in
            guard let self else { return }
            self.openReader(for: book)
        })
        // Móc bắt **mọi** đường đóng sheet. `presentationControllerDidDismiss` chỉ chạy khi người dùng **vuốt
        // xuống**, còn đường lập trình (chạm một truyện ⇒ `openReader`, `@Environment(\.dismiss)` của màn Thông báo)
        // không có callback nào của UIKit. Thiếu móc này thì `isSheetPresented` kẹt ở `true`, nút nổi **biến mất
        // vĩnh viễn** sau lần đầu đóng sheet bằng đường lập trình. Hai cơ chế cố ý chồng nhau: `setSheetPresented` idempotent,
        // và hậu quả của việc kẹt cờ đủ nặng để đáng trả giá một lời gọi thừa.
        let content = inbox.onDisappear {
            FloatingHubWindowManager.shared.setSheetPresented(false)
        }
        // Trình bày bằng UIKit từ cửa sổ hub ⇒ không thừa hưởng `.tint` của `MainTabView`, gắn lại màu nhấn.
        .appAccentTint()
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
        // Màn Thông báo không còn nút Đóng (1.3.641) ⇒ thanh kéo là gợi ý vuốt xuống. `.presentationDragIndicator`
        // của SwiftUI không tới được sheet trình bày bằng UIKit. `.pageSheet` tường minh (iPhone vốn ra đúng kiểu này)
        // để `sheetPresentationController` có sẵn trước khi trình bày.
        hosting.modalPresentationStyle = .pageSheet
        hosting.sheetPresentationController?.prefersGrabberVisible = true

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

    /// Vuốt xuống để đóng sheet cũng phải trả nút về đúng trạng thái — nếu chỉ xử lý ở đường đóng lập trình thì nút
    /// nổi sẽ biến mất vĩnh viễn sau một lần vuốt.
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        handleSheetDismissed()
    }

    private func handleSheetDismissed() {
        FloatingHubWindowManager.shared.setSheetPresented(false)
    }
}
