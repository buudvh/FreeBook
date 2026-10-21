import Foundation

/// Bộ chạy nghiệm thu (dev, không UI) cho nguồn Legado đã cài, điều khiển qua debug server (`legado.corpus.*`).
///
/// Mỗi nguồn chạy `LegadoCorpusProbe` (lối vào theo `checkKeyWord` → chi tiết → mục lục → nội dung chương đầu) qua
/// facade `SourceRuntime.shared`. Tối đa `maxParallelSources` nguồn cùng lúc (mỗi lời gọi engine chiếm một thread
/// riêng), cửa sổ trượt: xong một nguồn mới nhận nguồn kế. Một lượt tại một thời điểm.
///
/// Vòng đời: lượt chạy **không** gắn với kết nối debug — client rớt mạng thì lượt vẫn chạy tiếp, nối lại rồi hỏi
/// `legado.corpus.status`. Huỷ bằng `legado.corpus.cancel`. Báo cáo ghi ở `applicationSupport/legado_reports/` mỗi
/// `checkpointInterval` nguồn và khi kết thúc/huỷ (app có thể bị iOS treo giữa chừng khi khoá màn hình).
///
/// Không ghi dữ liệu người dùng: chỉ thư mục báo cáo, cùng trạng thái engine mà một lượt duyệt nguồn thường cũng ghi
/// (cookie, biến/cache nguồn); trạng thái truyện dùng `bookId` có namespace `corpus-runner:<packageId>` (xem
/// `LegadoCorpusProbe`).
actor LegadoCorpusRunner {
    static let shared = LegadoCorpusRunner()
    static let maxParallelSources = 4
    static let checkpointInterval = 50

    enum StartError: Error, Sendable {
        case busy(runId: String)
        case snapshotNotReady
        case noSources(skipped: Int)

        var message: String {
            switch self {
            case .busy(let runId):
                return "Đang có lượt nghiệm thu \(runId) chạy — huỷ hoặc chờ xong rồi chạy lại"
            case .snapshotNotReady:
                return "Danh sách nguồn Legado chưa nạp xong — mở app tới màn chính rồi thử lại"
            case .noSources(let skipped):
                return skipped > 0
                    ? "Không có nguồn nào chạy được (\(skipped) nguồn bị bỏ qua: không có trên app / không phải Legado chữ / đang tắt)"
                    : "Không có nguồn Legado chữ nào đang bật"
            }
        }
    }

    enum CancelOutcome: Sendable, Equatable {
        case cancelling(runId: String)
        case notRunning
        case unknownRun
    }

    private struct Job {
        let runId: String
        let request: LegadoCorpusRequest
        let startedAt: Date
        let totalSources: Int
        var results: [LegadoCorpusReport.SourceResult]
        var inFlight: [String: String] = [:]
        var state: LegadoCorpusReport.State = .running
        var cancelRequested = false
        var finishedAt: Date?
        var reportPath: String?
        var task: Task<Void, Never>?
        var attemptedSinceCheckpoint = 0
    }

    private var job: Job?

    init() {}

    // MARK: - Lệnh

    /// Bắt đầu một lượt và trả trạng thái ngay (không chờ chạy xong — client debug timeout sau 30 giây).
    func start(_ request: LegadoCorpusRequest) async throws -> LegadoCorpusReport {
        if let current = job, current.state == .running {
            throw StartError.busy(runId: current.runId)
        }
        guard await LegadoCorpusCandidate.waitForLegadoSnapshot() else {
            throw StartError.snapshotNotReady
        }
        // Actor tái nhập: một `start` khác có thể đã chen vào trong lúc chờ ở trên.
        if let current = job, current.state == .running {
            throw StartError.busy(runId: current.runId)
        }

        let selection = LegadoCorpusCandidate.select(for: request)
        guard !selection.candidates.isEmpty else {
            throw StartError.noSources(skipped: selection.skipped.count)
        }

        let runId = UUID().uuidString
        let candidates = selection.candidates
        let keyword = request.defaultKeyword
        let newJob = Job(
            runId: runId,
            request: request,
            startedAt: Date(),
            totalSources: candidates.count + selection.skipped.count,
            results: selection.skipped
        )
        job = newJob

        let runner = self
        let task = Task {
            await LegadoCorpusRunner.runPool(
                candidates: candidates,
                keyword: keyword,
                onStart: { candidate in await runner.markStarted(candidate, runId: runId) },
                onResult: { result in await runner.record(result, runId: runId) }
            )
            await runner.finish(runId: runId)
        }
        job?.task = task

        AppLogger.shared.log(
            "🧪 [LegadoCorpus] Bắt đầu \(runId): \(candidates.count) nguồn, bỏ qua \(selection.skipped.count), "
                + "song song \(Self.maxParallelSources), từ khoá mặc định '\(keyword)'"
        )
        return Self.makeReport(newJob, includeSources: false)
    }

    /// Trạng thái lượt gần nhất (đang chạy hoặc đã xong trong phiên app này). `nil` khi chưa có lượt nào.
    func status(includeSources: Bool) -> LegadoCorpusReport? {
        guard let current = job else { return nil }
        return Self.makeReport(current, includeSources: includeSources)
    }

    /// `runId == nil` ⇒ huỷ lượt đang chạy (nếu có). Huỷ lượt đã xong là no-op hợp lệ.
    func cancel(runId: String?) -> CancelOutcome {
        guard let current = job else {
            return runId == nil ? .notRunning : .unknownRun
        }
        if let runId, runId != current.runId {
            return .unknownRun
        }
        guard current.state == .running else { return .notRunning }
        job?.cancelRequested = true
        current.task?.cancel()
        AppLogger.shared.log("🧪 [LegadoCorpus] Yêu cầu huỷ \(current.runId)")
        return .cancelling(runId: current.runId)
    }

    /// Nguồn Legado chữ để client chọn. `nil` khi bảng chụp chưa sẵn sàng.
    static func availableSources() async -> [LegadoCorpusSourceInfo]? {
        guard await LegadoCorpusCandidate.waitForLegadoSnapshot() else { return nil }
        return LegadoCorpusSourceInfo.textSources()
    }

    // MARK: - Ghi nhận tiến độ

    private func markStarted(_ candidate: LegadoCorpusCandidate, runId: String) {
        guard job?.runId == runId else { return }
        job?.inFlight[candidate.packageId] = candidate.name
    }

    private func record(_ result: LegadoCorpusReport.SourceResult, runId: String) {
        guard job?.runId == runId else { return }
        job?.results.append(result)
        job?.inFlight.removeValue(forKey: result.packageId)
        job?.attemptedSinceCheckpoint += 1
        if let pending = job?.attemptedSinceCheckpoint, pending >= Self.checkpointInterval {
            job?.attemptedSinceCheckpoint = 0
            writeReport()
        }
    }

    private func finish(runId: String) {
        guard var current = job, current.runId == runId else { return }
        current.state = current.cancelRequested ? .cancelled : .finished
        current.finishedAt = Date()
        current.inFlight = [:]
        current.task = nil
        job = current
        writeReport()
        if let finished = job {
            AppLogger.shared.log(Self.makeReport(finished, includeSources: false).summaryLine)
        }
    }

    /// Ghi bản đầy đủ (kèm từng nguồn). Lỗi ghi chỉ log — không làm hỏng lượt chạy.
    private func writeReport() {
        guard let current = job else { return }
        let plannedPath = LegadoCorpusReportStore.directoryName + "/"
            + LegadoCorpusReportStore.fileName(for: current.startedAt)
        var snapshot = current
        snapshot.reportPath = plannedPath
        let report = Self.makeReport(snapshot, includeSources: true)
        do {
            let path = try LegadoCorpusReportStore.write(report, startedAt: current.startedAt)
            job?.reportPath = path
        } catch {
            AppLogger.shared.log("❌ [LegadoCorpus] Không ghi được báo cáo: \(error.localizedDescription)")
        }
    }

    // MARK: - Dựng báo cáo / chạy song song

    private static func makeReport(_ job: Job, includeSources: Bool) -> LegadoCorpusReport {
        LegadoCorpusReport.make(
            runId: job.runId,
            state: job.state,
            startedAt: job.startedAt,
            finishedAt: job.finishedAt,
            selection: job.request.selection.label,
            defaultKeyword: job.request.defaultKeyword,
            totalSources: job.totalSources,
            results: job.results,
            inFlight: job.inFlight.values.sorted(),
            reportPath: job.reportPath,
            includeSources: includeSources
        )
    }

    /// Cửa sổ trượt `maxParallelSources` nguồn. Task cha bị huỷ ⇒ task con nhận huỷ (probe trả `.cancelled` ngay nhờ
    /// `LegadoCorpusDeadline`) và không nhận nguồn mới.
    private static func runPool(
        candidates: [LegadoCorpusCandidate],
        keyword: String,
        onStart: @escaping @Sendable (LegadoCorpusCandidate) async -> Void,
        onResult: @escaping @Sendable (LegadoCorpusReport.SourceResult) async -> Void
    ) async {
        await withTaskGroup(of: LegadoCorpusReport.SourceResult.self) { group in
            var nextIndex = 0
            while nextIndex < candidates.count, nextIndex < LegadoCorpusRunner.maxParallelSources {
                let candidate = candidates[nextIndex]
                nextIndex += 1
                await onStart(candidate)
                group.addTask { await LegadoCorpusProbe.run(candidate, defaultKeyword: keyword) }
            }
            while let result = await group.next() {
                await onResult(result)
                guard !Task.isCancelled, nextIndex < candidates.count else { continue }
                let candidate = candidates[nextIndex]
                nextIndex += 1
                await onStart(candidate)
                group.addTask { await LegadoCorpusProbe.run(candidate, defaultKeyword: keyword) }
            }
        }
    }
}
