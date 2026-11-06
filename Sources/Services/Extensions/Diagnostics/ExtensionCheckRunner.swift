import Foundation

/// Điều phối một lượt **Kiểm tra tiện ích** (tiện ích JS): tối đa `maxParallelExtensions` tiện ích cùng lúc (cửa sổ
/// trượt như `LegadoCorpusRunner`), bên trong một tiện ích các script chạy **lần lượt** (`ExtensionCheckProbe`) — mỗi
/// trang nguồn chỉ nhận một request một lúc. Một lượt tại một thời điểm; màn trình bày thăm dò `status()`.
///
/// Không đụng thư viện. Kết quả sống ở bộ nhớ trong lúc chạy; xong/dừng (kể cả sau "Chạy lại" một tiện ích) thì ghi
/// một file vào `extension_check_reports/` (`CheckReportStore`, 1.3.759 — trước đó không ghi ra đĩa) để xem lại ở trang
/// Báo cáo kiểm tra; chia sẻ qua `ExtensionCheckReportShare`. Từ khoá tìm thử đọc một lần lúc bắt đầu từ lịch sử tìm
/// kiếm (`SearchHistoryStore`).
actor ExtensionCheckRunner {
    static let shared = ExtensionCheckRunner()
    static let maxParallelExtensions = 3

    /// Bản chụp những gì bộ kiểm cần của một tiện ích đã cài (`Extension` là bản ghi của tầng View).
    struct Target: Sendable {
        let packageId: String
        let name: String
        let localPath: String
        let downloadUrl: String
        let configJson: String
        let type: String
    }

    enum StartError: Error, Sendable {
        case busy
        case noTargets

        var message: String {
            switch self {
            case .busy: return "Đang có một lượt kiểm tra khác. Dừng lượt đó rồi mở lại."
            case .noTargets: return "Không có tiện ích đã cài nào để kiểm tra."
            }
        }
    }

    private struct Job {
        let runId: String
        let startedAt: Date
        let targets: [Target]
        let keywords: [String]
        /// Tên phạm vi của màn kiểm tra — tên báo cáo đã lưu.
        let title: String?
        var results: [String: ExtensionCheckReport.ExtensionResult] = [:]
        var state: ExtensionCheckReport.State = .running
        var finishedAt: Date?
        var task: Task<Void, Never>?
        var cancelRequested = false
    }

    private var job: Job?

    init() {}

    // MARK: - Lệnh

    /// Bắt đầu một lượt và trả trạng thái ngay (không chờ chạy xong). `title` = tên phạm vi của màn kiểm tra.
    func start(_ targets: [Target], title: String? = nil) throws -> ExtensionCheckReport {
        if let current = job, current.state == .running {
            throw StartError.busy
        }
        guard !targets.isEmpty else { throw StartError.noTargets }
        let keywords = Self.historyKeywords()
        let newJob = Job(runId: UUID().uuidString, startedAt: Date(), targets: targets, keywords: keywords, title: title)
        job = newJob
        CheckReportStore.markActive(.script, startedAt: newJob.startedAt)
        launch(targets, runId: newJob.runId, keywords: keywords)
        AppLogger.shared.log(
            "🧪 [ExtCheck] Bắt đầu \(newJob.runId): \(targets.count) tiện ích, song song \(Self.maxParallelExtensions), "
                + "\(keywords.count) từ khoá trong lịch sử"
        )
        return Self.makeReport(newJob)
    }

    /// Chạy lại **một** tiện ích của lượt đã xong (đóng trình duyệt "Mở link lỗi", nút "Chạy lại") — kết quả mới thay
    /// kết quả cũ của tiện ích đó, các tiện ích khác giữ nguyên.
    func retry(packageId: String) throws -> ExtensionCheckReport {
        guard var current = job else { throw StartError.noTargets }
        guard current.state != .running else { throw StartError.busy }
        guard let target = current.targets.first(where: { $0.packageId == packageId }) else {
            throw StartError.noTargets
        }
        current.results.removeValue(forKey: packageId)
        current.state = .running
        current.finishedAt = nil
        current.cancelRequested = false
        job = current
        CheckReportStore.markActive(.script, startedAt: current.startedAt)
        launch([target], runId: current.runId, keywords: current.keywords)
        return Self.makeReport(current)
    }

    func status() -> ExtensionCheckReport? {
        job.map { Self.makeReport($0) }
    }

    /// `runId == nil` ⇒ huỷ lượt đang chạy (nếu có). Huỷ lượt đã xong là no-op.
    func cancel(runId: String?) {
        guard let current = job, current.state == .running else { return }
        if let runId, runId != current.runId { return }
        job?.cancelRequested = true
        current.task?.cancel()
        AppLogger.shared.log("🧪 [ExtCheck] Yêu cầu dừng \(current.runId)")
    }

    // MARK: - Ghi nhận

    private func launch(_ targets: [Target], runId: String, keywords: [String]) {
        let runner = self
        job?.task = Task {
            await ExtensionCheckRunner.runPool(targets: targets, keywords: keywords) { result in
                await runner.record(result, runId: runId)
            }
            await runner.finish(runId: runId)
        }
    }

    private func record(_ result: ExtensionCheckReport.ExtensionResult, runId: String) {
        guard job?.runId == runId, job?.state == .running else { return }
        job?.results[result.packageId] = result
    }

    private func finish(runId: String) {
        guard var current = job, current.runId == runId else { return }
        current.state = current.cancelRequested ? .cancelled : .finished
        current.finishedAt = Date()
        current.task = nil
        job = current
        let report = Self.makeReport(current)
        writeReport(report, startedAt: current.startedAt)
        AppLogger.shared.log(
            "🧪 [ExtCheck] \(report.state.rawValue): đạt đủ \(report.fullyPassed), có lỗi \(report.withProblems), "
                + "tổng \(report.totalExtensions)"
        )
    }

    /// Ghi bản cuối (cùng file cho mọi lần "Chạy lại" của lượt). Dừng trước khi có kết quả nào ⇒ không ghi. Lỗi ghi
    /// chỉ log — không làm hỏng lượt chạy.
    private func writeReport(_ report: ExtensionCheckReport, startedAt: Date) {
        defer { CheckReportStore.markInactive(.script, startedAt: startedAt) }
        guard !report.results.isEmpty else { return }
        do {
            try CheckReportStore.write(report, kind: .script, startedAt: startedAt)
        } catch {
            AppLogger.shared.log("❌ [ExtCheck] Không ghi được báo cáo: \(error.localizedDescription)")
        }
    }

    // MARK: - Dựng báo cáo / chạy song song

    private static func makeReport(_ job: Job) -> ExtensionCheckReport {
        ExtensionCheckReport(
            runId: job.runId,
            state: job.state,
            startedAt: LegadoCorpusReport.isoString(job.startedAt),
            finishedAt: job.finishedAt.map { LegadoCorpusReport.isoString($0) },
            totalExtensions: job.targets.count,
            results: job.targets.compactMap { job.results[$0.packageId] },
            title: job.title
        )
    }

    /// Cửa sổ trượt `maxParallelExtensions` tiện ích. Task cha bị huỷ ⇒ probe con nhận huỷ và không nhận tiện ích mới.
    /// `onUpdate` nhận cả bản giữa chừng lẫn bản cuối của mỗi tiện ích.
    private static func runPool(
        targets: [Target],
        keywords: [String],
        onUpdate: @escaping @Sendable (ExtensionCheckReport.ExtensionResult) async -> Void
    ) async {
        await withTaskGroup(of: ExtensionCheckReport.ExtensionResult.self) { group in
            var nextIndex = 0
            while nextIndex < targets.count, nextIndex < maxParallelExtensions {
                let target = targets[nextIndex]
                nextIndex += 1
                group.addTask { await ExtensionCheckProbe.run(target, historyKeywords: keywords, onUpdate: onUpdate) }
            }
            while let result = await group.next() {
                await onUpdate(result)
                guard !Task.isCancelled, nextIndex < targets.count else { continue }
                let target = targets[nextIndex]
                nextIndex += 1
                group.addTask { await ExtensionCheckProbe.run(target, historyKeywords: keywords, onUpdate: onUpdate) }
            }
        }
    }

    /// Lịch sử tìm kiếm dùng chung (màn Tìm kiếm + Tìm trên kệ), mới nhất trước.
    private static func historyKeywords() -> [String] {
        let json = UserDefaults.standard.string(forKey: SearchHistoryStore.storageKey) ?? "[]"
        return SearchHistoryStore.decode(json)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

extension ExtensionCheckRunner.Target {
    init(_ ext: Extension) {
        self.init(packageId: ext.packageId, name: ext.name, localPath: ext.localPath, downloadUrl: ext.downloadUrl,
                  configJson: ext.configJson, type: ext.type)
    }
}
