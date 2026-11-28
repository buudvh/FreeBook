import Foundation

/// **Lịch sử lọc** (anh Bửu duyệt mockup + plan "Lịch sử lọc — H1–H5", https://claude.ai/artifact/JwiiU3XFYTk7Rz1hAMS7G2):
/// mỗi lượt lọc ra màn duyệt ghi một `LocalNameFilterHistoryEntry` cùng `id` với gói tạm của màn duyệt đó
/// (`ReviewContext.draftId`) ⇒ đóng màn duyệt chưa Lưu thì gói (`+Drafts`) tự gắn vào đúng mục; Lưu xong
/// `LocalNameFilterSheet.save` đánh dấu mục (`LocalNameFilterHistoryStore.markSaved`).
///
/// Lượt không ra name, lỗi, hay bị huỷ (đóng sheet lúc đang lọc) **không** ghi mục: không có gì để mở lại, và ghi lúc bấm
/// "Bắt đầu lọc" thì app chết giữa chừng để lại mục treo. Giờ của mục vẫn là lúc bấm (`runStartedAt`). Ghi đồng bộ trên main
/// như gói tạm (file nhỏ) — mở lại sheet ngay sau đó luôn thấy mục.
extension LocalNameFilterSession {
    /// Gọi ở `finish` sau khi đã dựng `reviewContext` của lượt vừa lọc xong, trước khi sang màn duyệt.
    func recordHistory(startedAt: Date, filteredCount: Int, wasStopped: Bool) {
        guard let context = reviewContext else { return }
        let entry = LocalNameFilterHistoryEntry(
            id: context.draftId,
            startedAt: startedAt,
            scopeLabel: context.scopeLabel,
            wasStopped: wasStopped,
            chapterCount: context.chapterCount,
            filteredCount: filteredCount
        )
        LocalNameFilterHistoryStore.record(entry, bookId: context.bookId)
        AppLogger.shared.log("🔎 [LọcName] Lịch sử lọc: ghi lần lọc \(entry.scopeText), \(filteredCount) name")
    }
}
