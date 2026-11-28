import Foundation

/// Một **lần lọc** trong "Lịch sử lọc" của Lọc name local (anh Bửu duyệt mockup + plan "Lịch sử lọc — H1–H5",
/// https://claude.ai/artifact/JwiiU3XFYTk7Rz1hAMS7G2; bản 8 "ghi cả"): ghi **ngay lúc bấm "Bắt đầu lọc"** ở trạng thái
/// `running`, kết thúc thì cập nhật (`outcome`): ra màn duyệt, không ra name nào, lỗi, đã huỷ (thoát giữa chừng); Lưu xong
/// ghi số đã lưu. Lưu ở `LocalNameFilterHistoryStore` (mỗi truyện một file, **không giới hạn** số mục).
///
/// `id` **trùng** `LocalNameFilterDraft.id` của màn duyệt lượt đó (`LocalNameFilterSession.ReviewContext.draftId`): một lượt
/// = một màn duyệt = một gói tạm = một mục ⇒ gắn gói vào mục, đánh dấu đã lưu, tạo mục cho gói cũ đều tra theo `id`.
/// Trạng thái gói ("Chưa lưu" mở được / "Gói tạm đã bị xoá") và "Bị ngắt" **không** ghi ở đây mà suy ra lúc hiện
/// (`LocalNameFilterHistorySnapshot.status`): gói bị đẩy ra (quá 5), bị bộ cập nhật bỏ hết name, đổi nguồn gộp… đều đúng;
/// mục còn `running` mà `launchId` khác lần chạy app này ⇒ app đã thoát / chết lúc đang lọc.
struct LocalNameFilterHistoryEntry: Codable, Sendable, Identifiable, Equatable {
    /// Lần lọc kết thúc thế nào.
    enum Outcome: String, Codable, Sendable {
        /// Đang lọc (ghi lúc bấm). Còn nguyên ở lần chạy app sau ⇒ "Bị ngắt".
        case running
        /// Ra màn duyệt (có name) — đã lưu / chưa lưu theo `savedCount` + gói tạm.
        case reviewed
        /// Lọc xong (hoặc "Dừng") mà không ra name nào.
        case noNames
        /// Lỗi (`failureMessage`): tải / đọc model, không có chương đã tải trong phạm vi, chưa nạp từ điển…
        case failed
        /// Thoát giữa chừng (đóng sheet lúc đang lọc) — khác "Dừng".
        case cancelled
    }

    /// Mốc của **lần chạy app này** — mục `running` ghi kèm; mục `running` mang mốc khác ⇒ của tiến trình trước, bị ngắt.
    static let currentLaunchId = UUID()

    /// = id gói tạm của lượt lọc.
    let id: UUID
    /// Lúc bấm "Bắt đầu lọc" (gói tạm cũ được tạo mục ⇒ giờ lọc xong của gói).
    let startedAt: Date
    /// Phạm vi (`LocalNameFilterDraft.scopeLabel(chapterNumbers:)`): đang lọc / lỗi / bị ngắt = phạm vi định lọc; ra màn
    /// duyệt / không ra name / huỷ = các chương đã đọc tới. Rỗng = chưa kịp lấy danh sách chương.
    var scopeLabel: String
    /// Bấm "Dừng" trước khi đọc hết phạm vi ⇒ hiện thêm "(dừng)" (`scopeText`).
    var wasStopped: Bool
    /// Số chương (định lọc, rồi đã đọc).
    var chapterCount: Int
    /// Số name lọc được (Y của "Đã lưu X / Y", "lọc được Y").
    var filteredCount: Int
    /// Số name thực lưu (`AIHarnessService.ExtractedEntriesSaveResult.saved` — "Chỉ thêm key mới" chỉ đếm mục mới, có thể
    /// là 0); `nil` = chưa lưu.
    var savedCount: Int?
    var savedAt: Date?
    /// Vắng trong file (bản trước, chỉ ghi lần ra màn duyệt) ⇒ `.reviewed`.
    var outcome: Outcome
    /// Lời lỗi đầy đủ của lần `failed` (hàng hiện bản rút gọn).
    var failureMessage: String?
    /// `currentLaunchId` của lần chạy app ghi mục `running`.
    var launchId: UUID?

    private enum CodingKeys: String, CodingKey {
        case id, startedAt, scopeLabel, wasStopped, chapterCount, filteredCount, savedCount, savedAt
        case outcome, failureMessage, launchId
    }

    var isSaved: Bool { savedCount != nil }

    /// "chương 1–87 (dừng)", "chương 1–45 (huỷ)".
    var scopeText: String {
        let label = scopeLabel.isEmpty ? "chưa rõ phạm vi" : scopeLabel
        if outcome == .cancelled { return "\(label) (huỷ)" }
        return wasStopped ? "\(label) (dừng)" : label
    }

    init(
        id: UUID,
        startedAt: Date,
        scopeLabel: String,
        wasStopped: Bool,
        chapterCount: Int,
        filteredCount: Int,
        savedCount: Int? = nil,
        savedAt: Date? = nil,
        outcome: Outcome = .reviewed,
        failureMessage: String? = nil,
        launchId: UUID? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.scopeLabel = scopeLabel
        self.wasStopped = wasStopped
        self.chapterCount = chapterCount
        self.filteredCount = filteredCount
        self.savedCount = savedCount
        self.savedAt = savedAt
        self.outcome = outcome
        self.failureMessage = failureMessage
        self.launchId = launchId
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

    /// Trường mới (`outcome`, `failureMessage`, `launchId`) đọc kiểu "có thì lấy" ⇒ file của bản trước vẫn đọc được.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        scopeLabel = try container.decode(String.self, forKey: .scopeLabel)
        wasStopped = try container.decode(Bool.self, forKey: .wasStopped)
        chapterCount = try container.decode(Int.self, forKey: .chapterCount)
        filteredCount = try container.decode(Int.self, forKey: .filteredCount)
        savedCount = try container.decodeIfPresent(Int.self, forKey: .savedCount)
        savedAt = try container.decodeIfPresent(Date.self, forKey: .savedAt)
        outcome = try container.decodeIfPresent(Outcome.self, forKey: .outcome) ?? .reviewed
        failureMessage = try container.decodeIfPresent(String.self, forKey: .failureMessage)
        launchId = try container.decodeIfPresent(UUID.self, forKey: .launchId)
    }
}
