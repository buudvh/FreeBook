import SwiftData
import SwiftUI

extension MainTabView {
    /// Lượt đổi nguồn dở (1.3.689): app chết giữa chừng, hoặc bị ngắt vì hết thời gian chạy nền. Gọi lúc mở app (sau
    /// `DownloadManager.initialize`, vì bước xoá truyện huỷ tác vụ tải) và mỗi lần app hoạt động lại. Không có nhật ký
    /// hay đang có lượt chạy ⇒ không làm gì. Toast ở đây vì service không được gọi `ToastManager`.
    func recoverInterruptedSourceChange(container: ModelContainer) async {
        switch await BookSourceChangeCoordinator.shared.recoverIfNeeded(container: container) {
        case .none:
            break
        case .rolledBack(let journal):
            let title = TranslateUtils.translateBookTitleIfNeeded(journal.bookTitle, bookId: journal.oldBookId)
            ToastManager.shared.show(message: "Đổi nguồn '\(title)' bị gián đoạn, đã giữ nguyên truyện cũ", type: .info)
        case .completed(let journal):
            let title = TranslateUtils.translateBookTitleIfNeeded(journal.bookTitle, bookId: journal.oldBookId)
            ToastManager.shared.show(message: "Đã hoàn tất đổi nguồn '\(title)' của lần trước", type: .success)
        }
    }
}
