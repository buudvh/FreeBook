import Foundation

/// **Lịch sử lọc** (anh Bửu duyệt mockup + plan "Lịch sử lọc — H1–H5", https://claude.ai/artifact/JwiiU3XFYTk7Rz1hAMS7G2;
/// bản 8: ghi **cả** lần lọc không thành). Mỗi lần bấm "Bắt đầu lọc" / "Thử lại" ghi ngay một `LocalNameFilterHistoryEntry`
/// trạng thái "đang lọc" (kèm mốc lần chạy app — app thoát / chết giữa chừng thì lần mở sau hiện "Bị ngắt"); lấy xong danh
/// sách chương ⇒ ghi phạm vi định lọc; kết thúc ⇒ cập nhật đúng **một** lần (`endHistory`):
/// - ra màn duyệt ⇒ `reviewed` + số name lọc được; mục cùng `id` với gói tạm của màn duyệt (`ReviewContext.draftId` =
///   `HistoryRun.id`) ⇒ đóng chưa Lưu thì gói tự gắn vào mục, Lưu xong `LocalNameFilterSheet.save` đánh dấu đã lưu;
/// - lọc xong / "Dừng" mà không ra name (kể cả "Dừng" lúc đang lấy chương / chuẩn bị model) ⇒ `noNames`;
/// - lỗi (bộ lọc báo lỗi, phạm vi không có chương đã tải) ⇒ `failed` + lời lỗi, giữ phạm vi định lọc;
/// - đóng sheet lúc đang lọc ⇒ `cancelled`, phạm vi = các chương đã đọc tới ("(huỷ)").
/// Phạm vi của lần ra màn duyệt / không ra name / huỷ là các chương đã đọc tới; "Dừng" trước khi đọc hết ⇒ "(dừng)".
///
/// Ghi đồng bộ trên main như gói tạm (file nhỏ) — mở lại sheet ngay sau đó luôn thấy mục.
extension LocalNameFilterSession {
    /// Lượt lọc đang ghi lịch sử.
    struct HistoryRun {
        /// = id mục lịch sử = id gói tạm nếu lượt ra màn duyệt.
        let id: UUID
        let bookId: String
        /// Chỉ số chương (0-based) ⇒ số chương hiển thị (`StartRequest.chapterNumbers`).
        let chapterNumbers: [Int: Int]
    }

    /// Lượt lọc kết thúc thế nào.
    enum HistoryEnd {
        case reviewed(filteredCount: Int)
        case noNames
        case failed(String)
        case cancelled
    }

    /// Bấm "Bắt đầu lọc" / "Thử lại": ghi mục "đang lọc" (chưa biết phạm vi — chờ danh sách chương).
    func beginHistory(_ request: StartRequest) {
        let run = HistoryRun(id: UUID(), bookId: request.bookId, chapterNumbers: request.chapterNumbers)
        historyRun = run
        LocalNameFilterHistoryStore.record(
            LocalNameFilterHistoryEntry(
                id: run.id,
                startedAt: Date(),
                scopeLabel: "",
                wasStopped: false,
                chapterCount: 0,
                filteredCount: 0,
                outcome: .running,
                launchId: LocalNameFilterHistoryEntry.currentLaunchId
            ),
            bookId: run.bookId
        )
    }

    /// Lấy xong danh sách chương của lượt: ghi phạm vi định lọc (lần lỗi / bị ngắt hiện phạm vi này).
    func setHistoryPlannedScope(chapterIndices: [Int]) {
        guard let run = historyRun else { return }
        let label = Self.historyScopeLabel(chapterIndices, run: run)
        LocalNameFilterHistoryStore.update(id: run.id, bookId: run.bookId) { entry in
            entry.scopeLabel = label
            entry.chapterCount = chapterIndices.count
        }
    }

    /// Lượt kết thúc: cập nhật mục một lần rồi thôi ghi (gọi lần nữa — vd `stop()` rồi `cancel()` — vô hại). `chaptersRead`
    /// = số chương đã đọc (theo thứ tự `runChapterIndices`); phải gọi **trước** `resetProgress()`.
    func endHistory(_ end: HistoryEnd, chaptersRead: Int, wasStopped: Bool = false) {
        guard let run = historyRun else { return }
        historyRun = nil
        let readIndices = Array(runChapterIndices.prefix(max(chaptersRead, 0)))
        let readLabel = Self.historyScopeLabel(readIndices, run: run)
        LocalNameFilterHistoryStore.update(id: run.id, bookId: run.bookId) { entry in
            switch end {
            case .reviewed(let filteredCount):
                entry.outcome = .reviewed
                entry.filteredCount = filteredCount
            case .noNames:
                entry.outcome = .noNames
            case .failed(let message):
                entry.outcome = .failed
                entry.failureMessage = message
            case .cancelled:
                entry.outcome = .cancelled
            }
            entry.launchId = nil
            switch end {
            case .failed:
                // Giữ phạm vi định lọc; chưa kịp có (phạm vi không có chương đã tải) ⇒ "0 chương".
                if entry.scopeLabel.isEmpty { entry.scopeLabel = readLabel }
            case .reviewed, .noNames, .cancelled:
                entry.scopeLabel = readLabel
                entry.chapterCount = readIndices.count
                entry.wasStopped = wasStopped
            }
        }
        AppLogger.shared.log("🔎 [LọcName] Lịch sử lọc: kết thúc lần lọc \(readLabel) — \(end)")
    }

    /// "chương 1–87" theo số chương hiển thị của lượt (`LocalNameFilterDraft.scopeLabel`), rỗng ⇒ "0 chương".
    private static func historyScopeLabel(_ indices: [Int], run: HistoryRun) -> String {
        LocalNameFilterDraft.scopeLabel(chapterNumbers: indices.map { run.chapterNumbers[$0] ?? $0 + 1 })
    }
}
