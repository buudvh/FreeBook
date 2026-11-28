import Foundation

/// Một **lần lọc** trong "Lịch sử lọc" của Lọc name local (anh Bửu duyệt mockup + plan "Lịch sử lọc — H1–H5",
/// https://claude.ai/artifact/JwiiU3XFYTk7Rz1hAMS7G2): ghi khi lượt lọc ra màn duyệt (có name), cập nhật khi Lưu. Lưu ở
/// `LocalNameFilterHistoryStore` (mỗi truyện một file, **không giới hạn** số mục).
///
/// `id` **trùng** `LocalNameFilterDraft.id` của màn duyệt lượt đó (`LocalNameFilterSession.ReviewContext.draftId`): một lượt
/// = một màn duyệt = một gói tạm = một mục ⇒ gắn gói vào mục, đánh dấu đã lưu, tạo mục cho gói cũ đều tra theo `id`.
/// Trạng thái gói ("Chưa lưu" mở được / "Gói tạm đã bị xoá") **không** ghi ở đây mà suy ra lúc hiện
/// (`LocalNameFilterHistorySnapshot.status`): gói bị đẩy ra (quá 5), bị bộ cập nhật bỏ hết name, đổi nguồn gộp… đều đúng.
struct LocalNameFilterHistoryEntry: Codable, Sendable, Identifiable, Equatable {
    /// = id gói tạm của lượt lọc.
    let id: UUID
    /// Lúc bấm "Bắt đầu lọc" (gói tạm cũ được tạo mục ⇒ giờ lọc xong của gói).
    let startedAt: Date
    /// Phạm vi đã đọc (`LocalNameFilterDraft.scopeLabel(chapterNumbers:)`): lần "Dừng" là các chương đã đọc tới.
    let scopeLabel: String
    /// Bấm "Dừng" trước khi đọc hết phạm vi ⇒ hiện thêm "(dừng)" (`scopeText`).
    let wasStopped: Bool
    /// Số chương đã đọc.
    let chapterCount: Int
    /// Số name lọc được (Y của "Đã lưu X / Y", "lọc được Y").
    let filteredCount: Int
    /// Số name thực lưu (`AIHarnessService.ExtractedEntriesSaveResult.saved` — "Chỉ thêm key mới" chỉ đếm mục mới, có thể
    /// là 0); `nil` = chưa lưu.
    var savedCount: Int?
    var savedAt: Date?

    var isSaved: Bool { savedCount != nil }

    /// "chương 1–87 (dừng)".
    var scopeText: String {
        wasStopped ? "\(scopeLabel) (dừng)" : scopeLabel
    }

    init(
        id: UUID,
        startedAt: Date,
        scopeLabel: String,
        wasStopped: Bool,
        chapterCount: Int,
        filteredCount: Int,
        savedCount: Int? = nil,
        savedAt: Date? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.scopeLabel = scopeLabel
        self.wasStopped = wasStopped
        self.chapterCount = chapterCount
        self.filteredCount = filteredCount
        self.savedCount = savedCount
        self.savedAt = savedAt
    }

    /// Mục "chưa lưu" dựng từ một gói tạm không có mục nào trỏ tới (gói có từ trước khi có Lịch sử lọc, hoặc ghi mục lỗi):
    /// giờ = giờ lọc xong của gói, số lọc được = số name gói đang có.
    init(draft: LocalNameFilterDraft) {
        self.init(
            id: draft.id,
            startedAt: draft.filteredAt,
            scopeLabel: draft.scopeLabel,
            wasStopped: false,
            chapterCount: draft.chapterCount,
            filteredCount: draft.names.count
        )
    }
}
