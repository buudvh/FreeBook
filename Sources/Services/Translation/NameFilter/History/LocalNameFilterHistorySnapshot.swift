import Foundation

/// Bản chụp "Lịch sử lọc" của một truyện cho màn hình: các lần lọc (mới nhất trước) + gói tạm đang còn của truyện, đọc
/// cùng lúc ở `LocalNameFilterHistoryStore.snapshot(bookId:)`. Trạng thái từng lần **suy ra** từ hai thứ đó (`status`) chứ
/// không ghi trong mục: chưa lưu mà gói không còn (bị đẩy ra vì quá `LocalNameFilterDraftStore.maxDraftsPerBook`, bị bộ cập
/// nhật bỏ hết name, đóng màn duyệt khi đã bỏ hết…) ⇒ "Gói tạm đã bị xoá"; còn "đang lọc" mà của lần chạy app trước ⇒
/// "Bị ngắt".
struct LocalNameFilterHistorySnapshot: Sendable, Equatable {
    enum Status: Equatable {
        /// Đã lưu X name (`savedCount`).
        case saved(count: Int)
        /// Chưa lưu, gói tạm còn ⇒ chạm mở lại màn duyệt.
        case unsaved(LocalNameFilterDraft)
        /// Chưa lưu, gói tạm không còn ⇒ chỉ còn dòng lịch sử (mờ, không mở được).
        case draftGone
        /// Đang lọc ở lần chạy app này (sheet đang lọc — trang lịch sử thường không thấy được).
        case running
        /// Mục "đang lọc" của lần chạy app trước: app thoát / chết lúc đang lọc.
        case interrupted
        /// Lọc xong / "Dừng" mà không ra name nào.
        case noNames
        /// Lỗi, kèm lời lỗi đầy đủ (`LocalNameFilterHistoryEntry.failureMessage`).
        case failed(String)
        /// Thoát giữa chừng (đóng sheet lúc đang lọc).
        case cancelled

        /// Lần không ra màn duyệt (không ra name, lỗi, huỷ, bị ngắt, đang lọc): nền sẫm, chạm không mở gì (mockup H2 bản 8).
        var isInactive: Bool {
            switch self {
            case .saved, .unsaved, .draftGone: return false
            case .running, .interrupted, .noNames, .failed, .cancelled: return true
            }
        }
    }

    static let empty = LocalNameFilterHistorySnapshot(entries: [], drafts: [])

    /// Mới nhất trước.
    private(set) var entries: [LocalNameFilterHistoryEntry]
    /// Gói tạm còn của truyện theo `id` (= `id` của lần lọc).
    private(set) var drafts: [UUID: LocalNameFilterDraft]

    init(entries: [LocalNameFilterHistoryEntry], drafts: [LocalNameFilterDraft]) {
        self.entries = entries
        self.drafts = Dictionary(drafts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    var isEmpty: Bool { entries.isEmpty }

    /// Lần lọc gần nhất ("Lần gần nhất dd/MM HH:mm" ở hàng Lịch sử lọc).
    var latest: LocalNameFilterHistoryEntry? { entries.first }

    func status(of entry: LocalNameFilterHistoryEntry) -> Status {
        switch entry.outcome {
        case .running:
            return entry.launchId == LocalNameFilterHistoryEntry.currentLaunchId ? .running : .interrupted
        case .noNames:
            return .noNames
        case .failed:
            return .failed(entry.failureMessage ?? "")
        case .cancelled:
            return .cancelled
        case .reviewed:
            break
        }
        if let count = entry.savedCount { return .saved(count: count) }
        if let draft = drafts[entry.id] { return .unsaved(draft) }
        return .draftGone
    }

    /// Số lần chưa lưu mà gói tạm còn ("M chưa lưu", "M gói tạm chưa lưu") — lần đã bị xoá gói không tính.
    var unsavedDraftCount: Int {
        entries.reduce(0) { $0 + (hasUnsavedDraft($1) ? 1 : 0) }
    }

    /// Như `unsavedDraftCount` nhưng chỉ trong các lần `ids` (chọn nhiều để xoá).
    func unsavedDraftCount(among ids: Set<UUID>) -> Int {
        entries.reduce(0) { $0 + (ids.contains($1.id) && hasUnsavedDraft($1) ? 1 : 0) }
    }

    /// Gói tạm đã qua bộ tự cập nhật (`LocalNameFilterDraftRefresher`) — lịch sử giữ nguyên.
    func replacingDrafts(_ drafts: [LocalNameFilterDraft]) -> LocalNameFilterHistorySnapshot {
        LocalNameFilterHistorySnapshot(entries: entries, drafts: drafts)
    }

    /// Bỏ các lần đã xoá (kèm gói tạm của chúng) khỏi bản chụp, khỏi phải đọc lại file.
    func removing(_ ids: Set<UUID>) -> LocalNameFilterHistorySnapshot {
        var copy = self
        copy.entries.removeAll { ids.contains($0.id) }
        for id in ids {
            copy.drafts[id] = nil
        }
        return copy
    }

    private func hasUnsavedDraft(_ entry: LocalNameFilterHistoryEntry) -> Bool {
        entry.outcome == .reviewed && !entry.isSaved && drafts[entry.id] != nil
    }
}
