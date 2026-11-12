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
            let title = recoveredTitle(journal, bookId: journal.oldBookId, container: container)
            ToastManager.shared.show(message: "Đổi nguồn '\(title)' bị gián đoạn, đã giữ nguyên truyện cũ", type: .info)
        case .completed(let journal):
            let title = recoveredTitle(journal, bookId: journal.newBookId, container: container)
            ToastManager.shared.show(message: "Đã hoàn tất đổi nguồn '\(title)' của lần trước", type: .success)
        }
    }

    /// Tên truyện trong toast: ba cấp của popup dịch + phồn → giản của truyện **còn lại** sau lượt khôi phục (lùi ⇒ truyện
    /// cũ, tiến ⇒ truyện mới; thiết lập theo truyện đã chép sang truyện mới). Không thấy `Book` ⇒ bỏ cấp nguồn.
    private func recoveredTitle(_ journal: BookSourceChangeJournal, bookId: String, container: ModelContainer) -> String {
        var descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.bookId == bookId })
        descriptor.fetchLimit = 1
        let packageId = (try? container.mainContext.fetch(descriptor).first)?.extensionPackageId
        return BookDisplayTranslation.text(journal.bookTitle, BookDisplayTranslation.options(bookId: bookId, packageId: packageId))
    }
}
