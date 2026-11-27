import Foundation

/// Gói name tạm của màn duyệt (plan 2026-11-27 mục E2, mockup LAC khung 5): danh sách đang duyệt (trạng thái chọn, nghĩa
/// đã sửa, cờ NE / VP) được giữ thành một `LocalNameFilterDraft` khi
/// - sheet đóng lúc đang duyệt mà chưa bấm Lưu (kể cả lượt đã "Dừng") — `keepDraftOnClose`, sheet hiện toast;
/// - app vào nền lúc đang duyệt — `persistDraftForBackground` (bị tắt app thì không mất), không toast.
/// Một màn duyệt chỉ có **một** gói (`ReviewContext.draftId`): ghi lần nữa là ghi đè gói đó, không tạo gói mới. Bấm Lưu
/// ⇒ `beginSave` đánh dấu để lần đóng ngay sau đó không giữ gói; lưu xong mới xoá gói (`LocalNameFilterSheet.save`).
///
/// Ghi đồng bộ trên main: file một truyện tối đa 5 gói (vài trăm KB với truyện dài) — tránh việc mở lại sheet ngay sau khi
/// đóng mà gói chưa kịp ghi.
extension LocalNameFilterSession {
    /// Màn duyệt đang mở thuộc truyện / gói nào, kèm thông tin hiện ở hàng gói của sheet thiết lập.
    struct ReviewContext {
        let bookId: String
        let draftId: UUID
        let filteredAt: Date
        let scopeLabel: String
        let chapterCount: Int
        /// Nghĩa máy ghép của từng name (`LocalNameFilterDraft.autoMeanings`) — đi theo gói để gói tự cập nhật theo danh
        /// sách đuôi (`LocalNameFilterDraftRefresher`). `nil` = mở từ gói của bản trước.
        let autoMeanings: [String: LocalNameFilterDraft.AutoMeaning]?
    }

    /// Nghĩa máy ghép lúc lọc xong: chữ Hán ⇒ nghĩa + loại (trùng chữ ⇒ giữ hàng đầu).
    static func autoMeanings(of names: [LocalNameFilter.Name]) -> [String: LocalNameFilterDraft.AutoMeaning] {
        var result: [String: LocalNameFilterDraft.AutoMeaning] = [:]
        for name in names where result[name.term] == nil {
            result[name.term] = LocalNameFilterDraft.AutoMeaning(meaning: name.meaning, kind: name.kind)
        }
        return result
    }

    /// Màn duyệt báo danh sách đang duyệt mỗi lần đổi (chọn / bỏ chọn, sửa, bỏ mục, cờ NE / VP tra lại).
    func updateReviewNames(_ names: [AIExtractedName]) {
        guard phase == .review else { return }
        latestReviewNames = names
    }

    /// App vào nền lúc đang duyệt mà chưa bấm Lưu ⇒ ghi gói ngay.
    func persistDraftForBackground() {
        guard !savePending, let context = reviewContext, let draft = currentDraft(), !draft.names.isEmpty else { return }
        LocalNameFilterDraftStore.upsert(draft, bookId: context.bookId)
        AppLogger.shared.log("🔎 [LọcName] App vào nền lúc đang duyệt ⇒ giữ gói tạm \(draft.names.count) name")
    }

    /// Sheet đóng: đang duyệt mà chưa bấm Lưu ⇒ ghi gói, trả số name đã giữ (sheet hiện toast). Danh sách đã bỏ hết ⇒
    /// xoá gói của màn này (nếu từng ghi), trả `nil`.
    func keepDraftOnClose() -> Int? {
        guard !savePending, let context = reviewContext, let draft = currentDraft() else { return nil }
        guard !draft.names.isEmpty else {
            LocalNameFilterDraftStore.delete(id: context.draftId, bookId: context.bookId)
            return nil
        }
        LocalNameFilterDraftStore.upsert(draft, bookId: context.bookId)
        AppLogger.shared.log("🔎 [LọcName] Đóng màn duyệt chưa lưu ⇒ giữ gói tạm \(draft.names.count) name")
        return draft.names.count
    }

    /// Bấm Lưu ở màn duyệt (gọi **trước** khi màn duyệt đóng sheet): lần đóng ngay sau đó không giữ gói. Trả truyện + gói
    /// hiện tại để nơi lưu xoá gói khi lưu xong, hoặc ghi lại gói khi lưu lỗi (danh sách không mất).
    func beginSave() -> (bookId: String, draft: LocalNameFilterDraft)? {
        savePending = true
        guard let context = reviewContext, let draft = currentDraft() else { return nil }
        return (context.bookId, draft)
    }

    /// Gói của màn duyệt đang mở, `savedAt` = bây giờ; `nil` khi không ở màn duyệt.
    private func currentDraft() -> LocalNameFilterDraft? {
        guard phase == .review, let context = reviewContext else { return nil }
        return LocalNameFilterDraft(
            id: context.draftId,
            filteredAt: context.filteredAt,
            savedAt: Date(),
            scopeLabel: context.scopeLabel,
            chapterCount: context.chapterCount,
            names: latestReviewNames,
            autoMeanings: context.autoMeanings
        )
    }
}
