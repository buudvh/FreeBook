import Foundation
import Observation

/// Trạng thái một lượt "Lọc name local" của `LocalNameFilterSheet`: giữ `LocalNameFilterRun` (bộ lọc chạy nền) và vòng
/// nghe sự kiện của nó, để đổi màn (chọn phạm vi ⇒ đang lọc ⇒ duyệt) không làm đứt vòng nghe như khi đặt nó trong `.task`
/// của một view con.
///
/// - `start` lấy chương đã tải theo phạm vi (`AIBookDataInspector.fetchDownloadedChapters`, ngoài main) rồi chạy bộ lọc.
/// - `.preparingModel` (model LAC tải về lần đầu / nạp + tự kiểm) ⇒ dòng "Tải model" / "Nạp model…" ở màn đang lọc
///   (`modelStep`); sự kiện đọc chương đầu tiên đánh dấu xong (✓).
/// - "Dừng" (`stop`): bộ lọc thôi đọc, phân tích nốt phần đã đọc rồi phát `.finished` ⇒ sang màn duyệt như khi đọc hết.
/// - Đóng sheet (`cancel`): huỷ ngay, không duyệt. Gọi lại nhiều lần / sau khi đã xong đều vô hại.
/// - `.finished`: có name ⇒ tra cờ NE / VP ngoài main (`decorateExtractedNames`, như luồng AI: name đã có trong Name / VP
///   của truyện bỏ chọn sẵn) rồi sang màn duyệt + toast; không có ⇒ về bước chọn với dòng báo.
/// - `.failed(msg)` (kể cả tải model lỗi) ⇒ `.failed`: màn đang lọc hiện lỗi + "Thử lại" (`retry`, chạy lại đúng cấu hình).
/// Gói tạm khi đóng màn duyệt chưa Lưu: `+Drafts`. Không chạy nền khi sheet đóng, không lên hub (anh Bửu chốt).
@MainActor
@Observable
final class LocalNameFilterSession {
    enum Phase: Equatable {
        /// Chọn phạm vi / tuỳ chọn.
        case setup
        /// Đang lấy danh sách chương đã tải của phạm vi.
        case preparing
        case running
        /// Đã bấm "Dừng": chờ bộ lọc phân tích nốt phần đã đọc.
        case stopping
        /// Bộ lọc báo lỗi (`failureMessage`): màn đang lọc hiện lỗi + "Thử lại".
        case failed
        /// Có name ⇒ màn duyệt (`reviewNames`).
        case review
    }

    enum Notice: Equatable {
        case info(String)
        case error(String)
    }

    /// Bước chuẩn bị model LAC của lượt đang chạy. `hidden` = bộ lọc không phát `.preparingModel` (model đã nạp sẵn).
    enum ModelStep: Equatable {
        case hidden
        /// Đang tải về lần đầu, 0…1.
        case downloading(Double)
        /// Đang nạp + tự kiểm; `downloaded` = trước đó có tải.
        case loading(downloaded: Bool)
        case ready(downloaded: Bool)

        var wasDownloaded: Bool {
            switch self {
            case .hidden: return false
            case .downloading: return true
            case .loading(let downloaded), .ready(let downloaded): return downloaded
            }
        }
    }

    /// Tham số của lần bấm "Bắt đầu lọc" — "Thử lại" chạy lại đúng y như vậy.
    struct StartRequest {
        let bookId: String
        let fromChapterIndex: Int?
        let limit: Int?
        let convertsTraditional: Bool
        let configuration: LocalNameFilter.Configuration
        /// Chỉ số chương (0-based) ⇒ số chương hiển thị (`AINameScanChapter.number`), cho mô tả phạm vi của gói tạm.
        let chapterNumbers: [Int: Int]
    }

    private(set) var phase: Phase = .setup
    /// Dòng báo ở đầu bước chọn sau một lượt không ra name / lỗi; bấm "Bắt đầu lọc" lần sau thì xoá.
    private(set) var notice: Notice?
    /// Lỗi của phase `.failed`.
    private(set) var failureMessage: String?
    private(set) var modelStep: ModelStep = .hidden
    private(set) var chaptersRead = 0
    private(set) var totalChapters = 0
    /// Danh sách tạm theo lần cập nhật gần nhất (+ hàng vừa rơi ra, xem `LocalNameFilterLiveRow`).
    private(set) var liveRows: [LocalNameFilterLiveRow] = []
    /// Số name của lần cập nhật gần nhất (không tính hàng vừa rơi ra).
    private(set) var liveNameCount = 0
    /// Số chương đã đọc lúc chụp lần cập nhật gần nhất; `nil` = chưa có lần nào.
    private(set) var lastUpdateChapter: Int?
    /// Tăng mỗi lần danh sách tạm đổi — view gắn hiệu ứng theo số này.
    private(set) var updateGeneration = 0
    /// Danh sách đưa vào màn duyệt lúc mở (đã gắn cờ NE / VP). Bản đang duyệt: `latestReviewNames`.
    private(set) var reviewNames: [AIExtractedName] = []

    // Gói tạm (`+Drafts`) — không quan sát: đổi mỗi lần chạm ô chọn, không cần vẽ lại sheet.
    /// Truyện + gói của màn duyệt đang mở (lượt lọc mới ⇒ gói mới; mở từ gói ⇒ đúng gói đó).
    @ObservationIgnored var reviewContext: ReviewContext?
    /// Danh sách đang duyệt mới nhất (màn duyệt báo qua `onNamesChange`).
    @ObservationIgnored var latestReviewNames: [AIExtractedName] = []
    /// Đã bấm Lưu ⇒ đóng sheet không giữ gói (lưu xong mới xoá gói, lưu lỗi thì ghi lại — `LocalNameFilterSheet.save`).
    @ObservationIgnored var savePending = false

    @ObservationIgnored private var run: LocalNameFilterRun?
    @ObservationIgnored private var consumeTask: Task<Void, Never>?
    @ObservationIgnored private var previousNames: [LocalNameFilter.Name]?
    @ObservationIgnored private var lastRequest: StartRequest?
    /// Chỉ số các chương của lượt đang chạy, đúng thứ tự đọc.
    @ObservationIgnored private var runChapterIndices: [Int] = []

    var isActive: Bool {
        phase == .preparing || phase == .running || phase == .stopping
    }

    /// `fromChapterIndex` = chỉ số chương bắt đầu (`nil` = từ chương đã tải đầu tiên), `limit` = số chương tối đa
    /// (`nil` = tới hết) — đúng nghĩa tham số của `fetchDownloadedChapters`.
    func start(_ request: StartRequest) {
        guard phase == .setup else { return }
        notice = nil
        failureMessage = nil
        lastRequest = request
        resetProgress()
        phase = .preparing
        consumeTask = Task { @MainActor [weak self] in
            let chapters = await AIBookDataInspector.shared.fetchDownloadedChapters(
                bookId: request.bookId,
                fromChapterIndex: request.fromChapterIndex,
                limit: request.limit
            )
            guard !Task.isCancelled, let self, self.phase == .preparing else { return }
            guard !chapters.isEmpty else {
                self.failToSetup("Không có chương đã tải nào trong phạm vi này")
                return
            }
            self.totalChapters = chapters.count
            self.runChapterIndices = chapters.map(\.index)
            let run = LocalNameFilterRun.start(
                bookId: request.bookId,
                chapters: chapters,
                convertsTraditional: request.convertsTraditional,
                configuration: request.configuration
            )
            self.run = run
            self.phase = .running
            for await event in run.events {
                guard !Task.isCancelled else { break }
                await self.handle(event)
                // Sự kiện cuối ⇒ thôi nghe ngay, kể cả khi stream đóng trễ: "Thử lại" bấm sau đó chạy lượt mới, task cũ
                // không được tới bước "dừng mà không báo kết quả" bên dưới và đè lên lượt mới.
                if case .finished = event { break }
                if case .failed = event { break }
            }
            // Stream đóng mà không có sự kiện cuối (không nên xảy ra) ⇒ đừng để sheet kẹt ở màn đang lọc.
            if !Task.isCancelled, self.phase == .running || self.phase == .stopping {
                AppLogger.shared.log("❌ [LọcName] Bộ lọc dừng mà không báo kết quả")
                self.failRun("Lọc name dừng giữa chừng, không có kết quả")
            }
        }
    }

    /// "Thử lại" ở màn lỗi: chạy lại đúng cấu hình lần trước.
    func retry() {
        guard phase == .failed, let request = lastRequest else { return }
        phase = .setup
        start(request)
    }

    /// "Quay lại" ở màn lỗi: về bước chọn, lỗi thành dòng báo.
    func leaveFailure() {
        guard phase == .failed else { return }
        if let failureMessage { notice = .error(failureMessage) }
        failureMessage = nil
        phase = .setup
    }

    /// Mở lại một gói tạm (`LocalNameFilterSheet+Drafts`): thẳng tới màn duyệt đúng trạng thái đã giữ; đóng chưa Lưu
    /// ⇒ ghi đè đúng gói này.
    func openDraft(_ draft: LocalNameFilterDraft, bookId: String) {
        guard phase == .setup else { return }
        notice = nil
        reviewNames = draft.names
        latestReviewNames = draft.names
        reviewContext = ReviewContext(
            bookId: bookId,
            draftId: draft.id,
            filteredAt: draft.filteredAt,
            scopeLabel: draft.scopeLabel,
            chapterCount: draft.chapterCount
        )
        savePending = false
        phase = .review
    }

    /// "Dừng": thôi đọc, phân tích nốt phần đã đọc rồi sang màn duyệt (khi bộ lọc phát `.finished`). Chưa kịp chạy
    /// (đang lấy danh sách chương) ⇒ chưa đọc gì, về bước chọn.
    func stop() {
        switch phase {
        case .preparing:
            cancel()
        case .running:
            phase = .stopping
            run?.stop()
        default:
            break
        }
    }

    /// Đóng sheet / rời màn: huỷ ngay, không phát `.finished`.
    func cancel() {
        consumeTask?.cancel()
        consumeTask = nil
        run?.cancel()
        run = nil
        if isActive {
            phase = .setup
            resetProgress()
        }
    }

    private func handle(_ event: LocalNameFilter.Event) async {
        switch event {
        case .preparingModel(let fraction):
            if let fraction {
                modelStep = .downloading(min(max(fraction, 0), 1))
            } else {
                modelStep = .loading(downloaded: modelStep.wasDownloaded)
            }
        case .progress(let read, let total):
            markModelReady()
            chaptersRead = read
            totalChapters = total
        case .update(let snapshot):
            markModelReady()
            applyUpdate(snapshot)
        case .finished(let snapshot):
            await finish(snapshot)
        case .failed(let message):
            failRun(message)
        }
    }

    /// Bộ lọc bắt đầu đọc chương ⇒ model đã sẵn sàng (dòng model hiện ✓).
    private func markModelReady() {
        switch modelStep {
        case .downloading, .loading:
            modelStep = .ready(downloaded: modelStep.wasDownloaded)
        case .hidden, .ready:
            break
        }
    }

    private func applyUpdate(_ snapshot: LocalNameFilter.Snapshot) {
        liveRows = LocalNameFilterLiveRow.rows(current: snapshot.names, previous: previousNames)
        previousNames = snapshot.names
        liveNameCount = snapshot.names.count
        lastUpdateChapter = snapshot.chaptersRead
        updateGeneration += 1
    }

    private func finish(_ snapshot: LocalNameFilter.Snapshot) async {
        run = nil
        guard let request = lastRequest, !snapshot.names.isEmpty else {
            consumeTask = nil
            phase = .setup
            resetProgress()
            // Bấm "Dừng" trước khi đọc xong khối chương đầu ⇒ chưa phân tích gì, đừng báo như đã lọc mà không thấy.
            let narrowed = (lastRequest?.configuration.categories.count ?? 0) < LocalNameFilter.Category.allCases.count
            notice = snapshot.chaptersRead == 0
                ? .info("Đã dừng trước khi đọc xong chương nào")
                : .info(narrowed ? "Không tìm thấy name nào thuộc loại đã chọn" : "Không tìm thấy name nào")
            return
        }
        let raw = snapshot.names.map { name in
            AIExtractedName(
                original: name.term,
                suggestedMeaning: name.meaning,
                category: name.category.label,
                occurrenceCount: name.count,
                isSelected: true
            )
        }
        // Gắn cờ NE / VP + bỏ chọn name đã có — đọc Names.txt / VietPhrase.txt của truyện, chạy ngoài main như luồng AI
        // (`AIRuntimeCoordinator+BatchExtraction`).
        let bookId = request.bookId
        let decorated = await Task.detached(priority: .userInitiated) {
            AIBookDataInspector.shared.decorateExtractedNames(names: raw, bookId: bookId)
        }.value
        // Đóng sheet trong lúc tra ⇒ `cancel()` đã huỷ task này và đưa phase về bước chọn.
        guard !Task.isCancelled, phase == .running || phase == .stopping else { return }
        consumeTask = nil
        let known = decorated.filter { $0.hasInBookNames || $0.hasInBookVP }.count
        let numbers = runChapterIndices.prefix(snapshot.chaptersRead).map { request.chapterNumbers[$0] ?? $0 + 1 }
        reviewNames = decorated
        latestReviewNames = decorated
        reviewContext = ReviewContext(
            bookId: bookId,
            draftId: UUID(),
            filteredAt: Date(),
            scopeLabel: LocalNameFilterDraft.scopeLabel(chapterNumbers: Array(numbers)),
            chapterCount: snapshot.chaptersRead
        )
        savePending = false
        phase = .review
        AppLogger.shared.log("🔎 [LọcName] Màn duyệt: \(decorated.count) name, \(known) đã có trong Name / VP (bỏ chọn sẵn)")
        ToastManager.shared.show(
            message: known > 0 ? "Lọc xong: \(decorated.count) name · \(known) đã có" : "Lọc xong: \(decorated.count) name",
            type: .success
        )
    }

    /// Lỗi của lượt lọc (bộ lọc phát `.failed`, kể cả tải model lỗi) ⇒ màn lỗi có "Thử lại".
    private func failRun(_ message: String) {
        run = nil
        consumeTask = nil
        resetProgress()
        failureMessage = message
        phase = .failed
    }

    /// Lỗi trước khi bộ lọc chạy (phạm vi không có chương) — "Thử lại" vô ích ⇒ về bước chọn với dòng báo.
    private func failToSetup(_ message: String) {
        run = nil
        consumeTask = nil
        phase = .setup
        resetProgress()
        notice = .error(message)
    }

    private func resetProgress() {
        modelStep = .hidden
        chaptersRead = 0
        totalChapters = 0
        liveRows = []
        liveNameCount = 0
        lastUpdateChapter = nil
        previousNames = nil
        runChapterIndices = []
    }
}
