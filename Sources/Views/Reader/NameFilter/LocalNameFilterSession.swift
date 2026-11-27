import Foundation
import Observation

/// Trạng thái một lượt "Lọc name local" của `LocalNameFilterSheet`: giữ `LocalNameFilterRun` (bộ lọc chạy nền) và vòng
/// nghe sự kiện của nó, để đổi màn (chọn phạm vi ⇒ đang lọc ⇒ duyệt) không làm đứt vòng nghe như khi đặt nó trong `.task`
/// của một view con.
///
/// - `start` lấy chương đã tải theo phạm vi (`AIBookDataInspector.fetchDownloadedChapters`, ngoài main) rồi chạy bộ lọc.
/// - "Dừng" (`stop`): bộ lọc thôi đọc, phân tích nốt phần đã đọc rồi phát `.finished` ⇒ sang màn duyệt như khi đọc hết.
/// - Đóng sheet (`cancel`): huỷ ngay, không duyệt. Gọi lại nhiều lần / sau khi đã xong đều vô hại.
/// - `.finished`: có name ⇒ màn duyệt + toast "Lọc xong: N name mới · ẩn M name đã có"; không có ⇒ về bước chọn với dòng
///   báo. `.failed(msg)` ⇒ về bước chọn, hiện `msg`.
/// Không chạy nền khi sheet đóng, không lên hub, không lưu tiến độ (anh Bửu chốt).
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
        /// Có name ⇒ màn duyệt (`reviewNames`).
        case review
    }

    enum Notice: Equatable {
        case info(String)
        case error(String)
    }

    private(set) var phase: Phase = .setup
    /// Dòng báo ở đầu bước chọn sau một lượt không ra name / lỗi; bấm "Bắt đầu lọc" lần sau thì xoá.
    private(set) var notice: Notice?
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
    /// Danh sách đưa vào màn duyệt, chọn sẵn hết.
    private(set) var reviewNames: [AIExtractedName] = []

    @ObservationIgnored private var run: LocalNameFilterRun?
    @ObservationIgnored private var consumeTask: Task<Void, Never>?
    @ObservationIgnored private var previousNames: [LocalNameFilter.Name]?

    var isActive: Bool {
        phase == .preparing || phase == .running || phase == .stopping
    }

    /// `fromChapterIndex` = chỉ số chương bắt đầu (`nil` = từ chương đã tải đầu tiên), `limit` = số chương tối đa
    /// (`nil` = tới hết) — đúng nghĩa tham số của `fetchDownloadedChapters`.
    func start(
        bookId: String,
        fromChapterIndex: Int?,
        limit: Int?,
        convertsTraditional: Bool,
        configuration: LocalNameFilter.Configuration
    ) {
        guard phase == .setup else { return }
        notice = nil
        resetProgress()
        phase = .preparing
        consumeTask = Task { @MainActor [weak self] in
            let chapters = await AIBookDataInspector.shared.fetchDownloadedChapters(
                bookId: bookId,
                fromChapterIndex: fromChapterIndex,
                limit: limit
            )
            guard !Task.isCancelled, let self, self.phase == .preparing else { return }
            guard !chapters.isEmpty else {
                self.fail("Không có chương đã tải nào trong phạm vi này")
                return
            }
            self.totalChapters = chapters.count
            let run = LocalNameFilterRun.start(
                bookId: bookId,
                chapters: chapters,
                convertsTraditional: convertsTraditional,
                configuration: configuration
            )
            self.run = run
            self.phase = .running
            for await event in run.events {
                guard !Task.isCancelled else { break }
                self.handle(event)
            }
            // Stream đóng mà không có sự kiện cuối (không nên xảy ra) ⇒ đừng để sheet kẹt ở màn đang lọc.
            if !Task.isCancelled, self.phase == .running || self.phase == .stopping {
                AppLogger.shared.log("❌ [LọcName] Bộ lọc dừng mà không báo kết quả")
                self.fail("Lọc name dừng giữa chừng, không có kết quả")
            }
        }
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

    private func handle(_ event: LocalNameFilter.Event) {
        switch event {
        case .progress(let read, let total):
            chaptersRead = read
            totalChapters = total
        case .update(let snapshot):
            applyUpdate(snapshot)
        case .finished(let snapshot):
            finish(snapshot)
        case .failed(let message):
            fail(message)
        }
    }

    private func applyUpdate(_ snapshot: LocalNameFilter.Snapshot) {
        liveRows = LocalNameFilterLiveRow.rows(current: snapshot.names, previous: previousNames)
        previousNames = snapshot.names
        liveNameCount = snapshot.names.count
        lastUpdateChapter = snapshot.chaptersRead
        updateGeneration += 1
    }

    private func finish(_ snapshot: LocalNameFilter.Snapshot) {
        run = nil
        consumeTask = nil
        let hidden = snapshot.hiddenKnownCount
        guard !snapshot.names.isEmpty else {
            phase = .setup
            resetProgress()
            notice = .info("Không tìm thấy name mới · ẩn \(hidden) name đã có")
            return
        }
        reviewNames = snapshot.names.map { name in
            AIExtractedName(
                original: name.term,
                suggestedMeaning: name.meaning,
                category: name.kind.label,
                occurrenceCount: name.count,
                isSelected: true
            )
        }
        phase = .review
        ToastManager.shared.show(
            message: "Lọc xong: \(snapshot.names.count) name mới · ẩn \(hidden) name đã có",
            type: .success
        )
    }

    private func fail(_ message: String) {
        run = nil
        consumeTask = nil
        phase = .setup
        resetProgress()
        notice = .error(message)
    }

    private func resetProgress() {
        chaptersRead = 0
        totalChapters = 0
        liveRows = []
        liveNameCount = 0
        lastUpdateChapter = nil
        previousNames = nil
    }
}
