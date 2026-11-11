import SwiftData
import SwiftUI
import UIKit

/// Mở một mục của hub (từ sheet hub hoặc chạm thẳng nút). Màn Thông báo và màn kiểm tra nguồn là **trang con ngay trong
/// sheet hub** từ 1.3.872 (`FloatingHubSheet.Page.notifications` / `.sourceCheck`) — không còn sheet UIKit riêng trình bày
/// từ cửa sổ hub (bỏ `presentInbox` và delegate vuốt-để-đóng của nó). Sheet hub vẫn giữ các điểm không được bỏ: nhánh
/// `presentedViewController` trong `FloatingHubUIWindow.hitTest` (luật 25), `onDismiss` hạ cờ (luật 26),
/// `.modelContainer` cho trang Thông báo (thiếu là crash), cửa sổ sống suốt lúc sheet mở.
extension FloatingHubContainerViewController {
    /// Mở một mục: sheet hub đóng **xong** rồi mới giao cho chủ của mục đó (`FloatingHubSheetState.dismiss(then:)` — trình
    /// bày từ sheet đang đóng thì UIKit đóng luôn màn mới). Sheet không mở (cài đặt "Mở thẳng") ⇒ mở ngay. Riêng AI
    /// (1.3.558) và Kiểm tra nguồn có hai lượt (1.3.697): sang trang con của sheet để chọn (`showSheetPage`).
    ///
    /// Dòng xám đã `disabled` trong sheet; guard ở đây chặn thêm đường VoiceOver và lượt chạm lọt vào đúng lúc
    /// trạng thái vừa đổi.
    ///
    /// AI tự tìm view controller trên cùng **chỉ trong window `.normal`** (`AIRuntimeCoordinator.presentFullScreen`),
    /// Video giao cho closure do phiên phát gắn (`VideoMiniPlayerState.onReopen`), nên không phụ thuộc cửa sổ của hub. Thông
    /// báo và Kiểm tra nguồn sang trang con của sheet (1.3.872).
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
            showSheetPage(.notifications)
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

    /// Mở lại màn kiểm tra của một lượt đang thu nhỏ **ngay trong sheet hub** (trang con, 1.3.872) thay cho sheet riêng.
    func openSourceCheck(_ kind: MinimizedSourceCheck.Kind) {
        guard isItemEnabled(.sourceCheck),
              presentationReader.snapshot.sourceChecks.contains(where: { $0.kind == kind }),
              let page = MinimizedSourceCheckCoordinator.shared.embeddedPage(kind) else { return }
        showSheetPage(.sourceCheck(page))
    }

    /// Nút ‹ của trang kiểm tra: giao lượt cho hub **trước** (như nút ⌄, không trông vào `onDisappear` — 1.3.702) rồi về
    /// trang chính. Lượt đã xong ⇒ coordinator bỏ bản ghi (đã xem kết quả).
    func leaveSourceCheck(_ kind: MinimizedSourceCheck.Kind) {
        MinimizedSourceCheckCoordinator.shared.screenDidClose(kind, screenId: nil)
        sheetState.page = .main
    }

    /// Chạm một truyện ở trang Thông báo: đóng sheet hub rồi bàn giao cho `ShelfView` (nơi duy nhất giữ `fullScreenCover`
    /// của Reader). Màn Thông báo tự gọi `dismiss` trước khi báo ⇒ sheet có thể đã đang đóng: việc chạy ngay — Reader ở cửa
    /// sổ chính, khác cửa sổ của sheet hub nên hai lớp trình bày không tranh nhau.
    func openInboxBook(_ book: Book) {
        let payload: [String: Any] = [
            FloatingHubWindowManager.bookIdUserInfoKey: book.bookId,
            FloatingHubWindowManager.extensionPackageIdUserInfoKey: book.extensionPackageId,
            FloatingHubWindowManager.chapterIndexUserInfoKey: book.currentChapterIndex,
            FloatingHubWindowManager.detailUrlUserInfoKey: book.detailUrl,
            FloatingHubWindowManager.sourceNameUserInfoKey: book.sourceName
        ]
        sheetState.dismiss {
            NotificationCenter.default.post(name: .openReaderFromNotification, object: nil, userInfo: payload)
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
}
