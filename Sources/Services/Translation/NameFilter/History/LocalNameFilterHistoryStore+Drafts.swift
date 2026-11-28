import Foundation

/// Phần của "Lịch sử lọc" chạm cả gói tạm (`LocalNameFilterDraftStore`): một lần lọc và gói tạm của nó cùng `id`.
extension LocalNameFilterHistoryStore {
    /// Lịch sử + gói tạm của truyện. Gói chưa có mục nào trỏ tới ⇒ tạo mục "chưa lưu" (`ensureEntries`): gói có từ trước
    /// khi có Lịch sử lọc được tạo mục ở lần mở sheet đầu tiên của truyện đó (file gói đặt tên theo băm `bookId` nên không
    /// làm một lượt chung cho mọi truyện được); tra theo `id` nên chạy mỗi lần mở cũng không tạo trùng, và file lịch sử
    /// hỏng thì gói còn lại có mục lại. Đọc file ⇒ gọi ngoài main.
    static func snapshot(bookId: String) -> LocalNameFilterHistorySnapshot {
        guard !bookId.isEmpty else { return .empty }
        let drafts = LocalNameFilterDraftStore.load(bookId: bookId)
        let entries = ensureEntries(for: drafts, bookId: bookId)
        return LocalNameFilterHistorySnapshot(entries: entries, drafts: drafts)
    }

    /// Xoá các lần lọc kèm gói tạm chưa lưu của chúng — gói trước, rồi mới tới mục (xoá dở thì không còn gói mồ côi bị tạo
    /// mục lại thành lần lọc "mới"). Name đã lưu vào Name / VP riêng không bị đụng.
    static func removeEntries(ids: Set<UUID>, bookId: String) {
        guard !bookId.isEmpty, !ids.isEmpty else { return }
        LocalNameFilterDraftStore.delete(ids: ids, bookId: bookId)
        delete(ids: ids, bookId: bookId)
        AppLogger.shared.log("🔎 [LọcName] Lịch sử lọc: xoá \(ids.count) lần lọc (kèm gói tạm)")
    }
}
